from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field


class BatchConfirmRequest(BaseModel):
    slot_id: str
    items: list["ConfirmItemRequest"]


class ConfirmItemRequest(BaseModel):
    confirmed_label: str = Field(..., max_length=200)
    slot_id: str = Field(..., max_length=50)
    item_id: Optional[str] = None
    bounding_box: Optional[dict] = None
    brand: Optional[str] = None
    category: Optional[str] = None
    thumbnail_path: Optional[str] = None
    confidence: Optional[float] = None
    is_chargeable_device: bool = False
    charge_reminder_cycle_days: int = 90


class ManualItemCreate(BaseModel):
    slot_id: str = Field(..., max_length=50)
    label: str = Field(..., max_length=200)
    brand: Optional[str] = None
    category: Optional[str] = None
    is_chargeable_device: bool = False
    charge_reminder_cycle_days: int = 90


class UploadResponse(BaseModel):
    task_id: str
    status: str = "processing"
    slot_id: str


class TaskStatusResponse(BaseModel):
    task_id: str
    status: str  # "processing" | "completed" | "failed"
    items: list[dict] = []
    error: Optional[str] = None


class ItemResponse(BaseModel):
    id: str
    slot_id: str
    label: str
    brand: Optional[str] = None
    category: Optional[str] = None
    tags: list = []
    thumbnail_path: Optional[str] = None
    is_chargeable: bool = False
    charge_cycle_days: Optional[int] = None
    is_borrowed: bool = False
    borrower: Optional[str] = None
    confidence: Optional[float] = None
    created_at: datetime

    model_config = {"from_attributes": True}


class HistorySnapshotResponse(BaseModel):
    id: str
    slot_id: str
    original_path: str
    compressed_path: Optional[str] = None
    is_current: bool
    created_at: datetime
    items: list[ItemResponse] = []


class RollbackRequest(BaseModel):
    snapshot_id: str
