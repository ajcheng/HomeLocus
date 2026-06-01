from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.schemas import reminder as schemas
from app.services.reminder_service import ReminderService

router = APIRouter()


def get_reminder_service(db: AsyncSession = Depends(get_db)) -> ReminderService:
    return ReminderService(db)


@router.post("/charge/complete", response_model=schemas.ReminderResponse)
async def complete_charge(data: schemas.ChargeCompleteRequest, svc: ReminderService = Depends(get_reminder_service)):
    reminder = await svc.complete_charge(data)
    return schemas.ReminderResponse(
        id=reminder.id, item_id=reminder.item_id, reminder_type=reminder.reminder_type,
        next_remind_at=reminder.next_remind_at, cycle_days=reminder.cycle_days,
        is_resolved=reminder.is_resolved, notes=reminder.notes, created_at=reminder.created_at,
    )


@router.put("/charge/cycle")
async def update_charge_cycle(data: schemas.ChargeCycleUpdate, svc: ReminderService = Depends(get_reminder_service)):
    item = await svc.update_charge_cycle(data)
    if not item:
        raise HTTPException(status_code=404, detail="Item not found")
    return {"item_id": data.item_id, "cycle_days": data.cycle_days}


@router.post("/borrow", response_model=schemas.ReminderResponse)
async def mark_borrowed(data: schemas.BorrowRequest, svc: ReminderService = Depends(get_reminder_service)):
    reminder = await svc.mark_borrowed(data)
    return schemas.ReminderResponse(
        id=reminder.id, item_id=reminder.item_id, reminder_type=reminder.reminder_type,
        next_remind_at=reminder.next_remind_at, cycle_days=None,
        is_resolved=reminder.is_resolved, notes=reminder.notes, created_at=reminder.created_at,
    )


@router.post("/borrow/return")
async def mark_returned(data: schemas.BorrowReturnRequest, svc: ReminderService = Depends(get_reminder_service)):
    await svc.mark_returned(data)
    return {"item_id": data.item_id, "status": "returned"}


@router.get("/pending", response_model=list[schemas.ReminderResponse])
async def get_pending_reminders(location_id: str | None = None, svc: ReminderService = Depends(get_reminder_service)):
    reminders = await svc.get_pending_reminders(location_id)
    return [
        schemas.ReminderResponse(
            id=r.id, item_id=r.item_id, reminder_type=r.reminder_type,
            next_remind_at=r.next_remind_at, cycle_days=r.cycle_days,
            is_resolved=r.is_resolved, notes=r.notes, created_at=r.created_at,
        )
        for r in reminders
    ]
