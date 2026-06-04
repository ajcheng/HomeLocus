import logging
from datetime import datetime, timezone

from celery.schedules import crontab
from sqlalchemy import select, update

from app.tasks.celery_app import celery_app

logger = logging.getLogger(__name__)

celery_app.conf.beat_schedule = {
    "check-pending-reminders-every-10-minutes": {
        "task": "app.tasks.scheduler.check_pending_reminders",
        "schedule": crontab(minute="*/10"),
    },
    "cleanup-expired-invitations-daily": {
        "task": "app.tasks.scheduler.cleanup_expired_invitations",
        "schedule": crontab(hour=3, minute=0),
    },
}


@celery_app.task
def check_pending_reminders():
    """
    Scan due reminders, send push, then reschedule next notify in 24h until resolved.
    """
    from app.core.database import async_session
    from app.models.reminder import Reminder
    from app.models.item import Item
    from app.services.notification_service import notification_service
    from app.services.reminder_service import ReminderService
    import asyncio

    async def _scan():
        async with async_session() as session:
            now = datetime.now(timezone.utc)
            result = await session.execute(
                select(Reminder, Item)
                .join(Item, Reminder.item_id == Item.id)
                .where(
                    Reminder.is_resolved == False,
                    Reminder.next_remind_at <= now,
                )
                .order_by(Reminder.next_remind_at)
            )
            rows = result.all()
            svc = ReminderService(session)

            for reminder, item in rows:
                logger.info(
                    f"  [{reminder.reminder_type}] {item.label}: "
                    f"due {reminder.next_remind_at.isoformat()} "
                    f"(notify #{reminder.notify_count or 0})"
                    f"{' — ' + (reminder.notes or '')}"
                )
                user_id = "system"
                if reminder.reminder_type == "charge":
                    await notification_service.notify_charge_reminder(
                        user_id, item.label, item.charge_cycle_days or 90
                    )
                elif reminder.reminder_type == "borrow":
                    await notification_service.notify_borrow_return(
                        user_id, item.label, item.borrower or "未知"
                    )
                await svc.reschedule_after_notify(reminder)

            if rows:
                logger.info(f"Processed {len(rows)} due reminders (next in 24h if unresolved)")
            return len(rows)

    try:
        count = asyncio.run(_scan())
        return {"status": "ok", "pending": count}
    except Exception as e:
        logger.error(f"Reminder scan failed: {e}")
        return {"status": "error", "error": str(e)}


@celery_app.task
def cleanup_expired_invitations():
    """Deactivate expired invitations."""
    from app.core.database import async_session
    from app.models.family import Invitation
    import asyncio

    async def _cleanup():
        async with async_session() as session:
            now = datetime.now(timezone.utc)
            result = await session.execute(
                update(Invitation)
                .where(Invitation.is_active == True, Invitation.expires_at <= now)
                .values(is_active=False)
            )
            await session.commit()
            return result.rowcount

    try:
        count = asyncio.run(_cleanup())
        logger.info(f"Deactivated {count} expired invitations")
        return {"status": "ok", "deactivated": count}
    except Exception as e:
        logger.error(f"Invitation cleanup failed: {e}")
        return {"status": "error", "error": str(e)}


@celery_app.task
def send_reminder_notification(reminder_id: str, item_label: str, reminder_type: str, notes: str | None = None):
    """Send push notification for a specific reminder (placeholder)."""
    logger.info(f"NOTIFICATION: [{reminder_type}] {item_label}: {notes or 'Reminder due'}")
    return {"status": "ok", "reminder_id": reminder_id}
