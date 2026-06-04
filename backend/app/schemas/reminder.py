from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field


class ChargeCompleteRequest(BaseModel):
    item_id: str
    next_reminder_days: int = Field(default=90, ge=1, le=365)


class ChargeCycleUpdate(BaseModel):
    item_id: str
    cycle_days: int = Field(..., ge=1, le=365)


class BorrowRequest(BaseModel):
    item_id: str
    expected_return_hours: int = Field(default=24, ge=1, le=720)
    borrower: Optional[str] = None


class BorrowReturnRequest(BaseModel):
    item_id: str


class ReminderResponse(BaseModel):
    id: str
    item_id: str
    reminder_type: str
    next_remind_at: datetime
    cycle_days: Optional[int] = None
    is_resolved: bool
    notes: Optional[str] = None
    last_notified_at: Optional[datetime] = None
    notify_count: int = 0
    created_at: datetime
    item_label: Optional[str] = None
    breadcrumb: Optional[str] = None
    slot_id: Optional[str] = None

    model_config = {"from_attributes": True}
