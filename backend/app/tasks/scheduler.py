from celery.schedules import crontab

from app.tasks.celery_app import celery_app

celery_app.conf.beat_schedule = {
    "check-pending-reminders-every-10-minutes": {
        "task": "app.tasks.recognition.check_pending_reminders",
        "schedule": crontab(minute="*/10"),
    },
}


@celery_app.task
def check_pending_reminders():
    """
    Periodic task: scan for due reminders and push notifications.
    """
    # TODO: Query DB for reminders where next_remind_at <= now() and is_resolved == false
    # TODO: Push notification to user
    pass
