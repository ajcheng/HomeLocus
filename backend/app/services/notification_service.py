import logging

logger = logging.getLogger(__name__)


class NotificationService:
    """Push notification service for FCM (Firebase Cloud Messaging)."""

    def __init__(self):
        self.enabled = False  # Set to True when FCM is configured
        # TODO: Configure FCM when credentials are available
        # import firebase_admin
        # from firebase_admin import credentials, messaging
        # cred = credentials.Certificate("firebase-key.json")
        # firebase_admin.initialize_app(cred)

    async def send_push(self, user_id: str, title: str, body: str, data: dict | None = None) -> bool:
        """
        Send a push notification to a user's device.
        Falls back to logging until FCM is configured.
        """
        logger.info(f"[PUSH] To user {user_id}: {title} — {body}")
        # TODO: Look up user's FCM tokens and send via Firebase
        # message = messaging.Message(
        #     notification=messaging.Notification(title=title, body=body),
        #     data=data or {},
        #     token=device_token,
        # )
        # messaging.send(message)
        return True

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
