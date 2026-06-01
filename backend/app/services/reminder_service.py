from datetime import datetime, timedelta, timezone

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.reminder import Reminder
from app.models.item import Item
from app.schemas import reminder as schemas


class ReminderService:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def complete_charge(self, data: schemas.ChargeCompleteRequest) -> Reminder:
        """Mark charge as done, schedule next reminder."""
        item = await self.db.get(Item, data.item_id)

        # Resolve any existing unresolved charge reminders
        await self.db.execute(
            update(Reminder)
            .where(Reminder.item_id == data.item_id, Reminder.reminder_type == "charge", Reminder.is_resolved == False)
            .values(is_resolved=True, resolved_at=datetime.now(timezone.utc))
        )

        next_remind = datetime.now(timezone.utc) + timedelta(days=data.next_reminder_days)
        reminder = Reminder(
            item_id=data.item_id,
            reminder_type="charge",
            next_remind_at=next_remind,
            cycle_days=data.next_reminder_days,
        )
        self.db.add(reminder)
        await self.db.commit()
        await self.db.refresh(reminder)
        return reminder

    async def update_charge_cycle(self, data: schemas.ChargeCycleUpdate) -> Item | None:
        """Update the default charge cycle for an item."""
        item = await self.db.get(Item, data.item_id)
        if not item:
            return None
        item.charge_cycle_days = data.cycle_days
        item.is_chargeable = True
        await self.db.commit()
        await self.db.refresh(item)
        return item

    async def mark_borrowed(self, data: schemas.BorrowRequest) -> Reminder:
        """Mark item as borrowed, schedule return reminder."""
        item = await self.db.get(Item, data.item_id)
        item.is_borrowed = True
        item.borrower = data.borrower

        next_remind = datetime.now(timezone.utc) + timedelta(hours=data.expected_return_hours)
        reminder = Reminder(
            item_id=data.item_id,
            reminder_type="borrow",
            next_remind_at=next_remind,
            notes=f"{data.borrower or '未知'} 借出，预计 {data.expected_return_hours} 小时内归还",
        )
        self.db.add(reminder)
        await self.db.commit()
        await self.db.refresh(reminder)
        return reminder

    async def mark_returned(self, data: schemas.BorrowReturnRequest) -> Reminder | None:
        """Mark borrowed item as returned."""
        item = await self.db.get(Item, data.item_id)
        if not item:
            return None
        item.is_borrowed = False
        item.borrower = None

        await self.db.execute(
            update(Reminder)
            .where(Reminder.item_id == data.item_id, Reminder.reminder_type == "borrow", Reminder.is_resolved == False)
            .values(is_resolved=True, resolved_at=datetime.now(timezone.utc))
        )
        await self.db.commit()
        return None

    async def get_pending_reminders(self, location_id: str | None = None) -> list[Reminder]:
        """Get all unresolved reminders, optionally filtered by location."""
        stmt = (
            select(Reminder)
            .where(Reminder.is_resolved == False, Reminder.next_remind_at <= datetime.now(timezone.utc))
            .order_by(Reminder.next_remind_at)
        )
        result = await self.db.execute(stmt)
        return list(result.scalars().all())
