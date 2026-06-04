from datetime import datetime, timedelta, timezone

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.models.reminder import Reminder
from app.models.item import Item
from app.models.space import Slot, Container, Zone, Location
from app.schemas import reminder as schemas


class ReminderService:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def complete_charge(self, data: schemas.ChargeCompleteRequest) -> Reminder:
        """Mark charge as done, schedule next reminder."""
        await self.db.get(Item, data.item_id)

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

    def _build_pending_row(
        self, reminder: Reminder, item: Item, slot: Slot, container: Container, zone: Zone, location: Location
    ) -> schemas.ReminderResponse:
        return schemas.ReminderResponse(
            id=reminder.id,
            item_id=reminder.item_id,
            reminder_type=reminder.reminder_type,
            next_remind_at=reminder.next_remind_at,
            cycle_days=reminder.cycle_days,
            is_resolved=reminder.is_resolved,
            notes=reminder.notes,
            last_notified_at=reminder.last_notified_at,
            notify_count=reminder.notify_count or 0,
            created_at=reminder.created_at,
            item_label=item.label,
            slot_id=slot.id,
            breadcrumb=f"{location.name} / {zone.name} / {container.name} / {slot.name}",
        )

    async def get_pending_reminders(self, location_id: str | None = None) -> list[schemas.ReminderResponse]:
        """Get due unresolved reminders with item location context."""
        now = datetime.now(timezone.utc)
        stmt = (
            select(Reminder, Item, Slot, Container, Zone, Location)
            .join(Item, Reminder.item_id == Item.id)
            .join(Slot, Item.slot_id == Slot.id)
            .join(Container, Slot.container_id == Container.id)
            .join(Zone, Container.zone_id == Zone.id)
            .join(Location, Zone.location_id == Location.id)
            .where(Reminder.is_resolved == False, Reminder.next_remind_at <= now)
            .order_by(Reminder.next_remind_at)
        )
        if location_id:
            stmt = stmt.where(Location.id == location_id)
        result = await self.db.execute(stmt)
        return [self._build_pending_row(*row) for row in result.all()]

    async def count_pending_reminders(self, location_id: str | None = None) -> int:
        rows = await self.get_pending_reminders(location_id)
        return len(rows)

    async def reschedule_after_notify(self, reminder: Reminder) -> None:
        """Push next notification window (default 24h) until user resolves."""
        now = datetime.now(timezone.utc)
        reminder.last_notified_at = now
        reminder.notify_count = (reminder.notify_count or 0) + 1
        reminder.next_remind_at = now + timedelta(hours=settings.reminder_repeat_hours)
        await self.db.commit()
