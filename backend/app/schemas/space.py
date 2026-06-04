from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field


# --- Location ---
class LocationCreate(BaseModel):
    name: str = Field(..., max_length=100)
    is_default: bool = False


class LocationResponse(BaseModel):
    id: str
    name: str
    is_default: bool
    created_at: datetime
    zone_count: int = 0

    model_config = {"from_attributes": True}


# --- Zone ---
class ZoneCreate(BaseModel):
    location_id: str
    name: str = Field(..., max_length=100)
    template_type: Optional[str] = None


class ZoneResponse(BaseModel):
    id: str
    location_id: str
    name: str
    template_type: Optional[str] = None

    model_config = {"from_attributes": True}


# --- Container ---
class SlotCreate(BaseModel):
    name: str = Field(..., max_length=100)
    level: int = 1


class ContainerCreate(BaseModel):
    zone_id: str
    name: str = Field(..., max_length=100)
    slots: list[SlotCreate] = []


class ContainerResponse(BaseModel):
    id: str
    zone_id: str
    name: str
    slots: list["SlotResponse"] = []

    model_config = {"from_attributes": True}


# --- Slot ---
class SlotResponse(BaseModel):
    id: str
    container_id: str
    name: str
    level: int
    item_count: int = 0

    model_config = {"from_attributes": True}


class SlotUpdate(BaseModel):
    name: Optional[str] = None
    level: Optional[int] = None


class SlotPathResponse(BaseModel):
    slot_id: str
    slot_name: str
    container_id: str
    container_name: str
    zone_id: str
    zone_name: str
    location_id: str
    location_name: str
    breadcrumb: str
