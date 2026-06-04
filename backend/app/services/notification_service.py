import logging

import httpx

from app.core.config import settings

logger = logging.getLogger(__name__)


class NotificationService:
    """Push notification service for FCM (Firebase Cloud Messaging)."""

    def __init__(self):
        self.enabled = bool(settings.fcm_server_key.strip())

    async def _send_fcm(self, device_token: str, title: str, body: str, data: dict | None = None) -> bool:
        if not self.enabled:
            return False
        try:
            async with httpx.AsyncClient(timeout=15.0) as client:
                response = await client.post(
                    "https://fcm.googleapis.com/fcm/send",
                    headers={
                        "Authorization": f"key={settings.fcm_server_key}",
                        "Content-Type": "application/json",
                    },
                    json={
                        "to": device_token,
                        "notification": {"title": title, "body": body},
                        "data": {k: str(v) for k, v in (data or {}).items()},
                    },
                )
                if response.status_code == 200:
                    payload = response.json()
                    if payload.get("failure", 0) > 0:
                        logger.warning(f"FCM partial failure: {payload}")
                        return False
                    return True
                logger.error(f"FCM HTTP {response.status_code}: {response.text[:200]}")
        except Exception as e:
            logger.error(f"FCM send failed: {e}")
        return False

    async def _tokens_for_user(self, user_id: str) -> list[str]:
        from app.core.database import async_session
        from app.services.push_token_service import PushTokenService

        async with async_session() as session:
            svc = PushTokenService(session)
            if user_id == "system":
                return await svc.list_all_active_tokens()
            return await svc.list_tokens_for_user(user_id)

    async def send_push(self, user_id: str, title: str, body: str, data: dict | None = None) -> bool:
        """Send push to all registered devices for user (or all users when user_id=system)."""
        logger.info(f"[PUSH] To user {user_id}: {title} — {body}")
        if not self.enabled:
            return True

        tokens = await self._tokens_for_user(user_id)
        if not tokens:
            logger.info(f"[PUSH] No device tokens for user {user_id}")
            return False

        sent = 0
        for token in tokens:
            if await self._send_fcm(token, title, body, data):
                sent += 1
        return sent > 0

    async def notify_charge_reminder(self, user_id: str, item_label: str, days: int) -> bool:
        return await self.send_push(
            user_id,
            "充电提醒",
            f"「{item_label}」已超过 {days} 天未充电，请及时充电",
            {"type": "charge_reminder", "item_label": item_label},
        )

    async def notify_borrow_return(self, user_id: str, item_label: str, borrower: str) -> bool:
        return await self.send_push(
            user_id,
            "归位提醒",
            f"「{item_label}」借给「{borrower}」尚未归位，请确认",
            {"type": "borrow_return", "item_label": item_label, "borrower": borrower},
        )


notification_service = NotificationService()
