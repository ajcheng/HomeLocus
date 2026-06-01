from typing import Optional

from pydantic import BaseModel, Field


class SpeechAddItemResponse(BaseModel):
    transcription: str
    parsed_item: Optional["ParsedItem"] = None
    matched_slot: Optional["MatchedSlot"] = None
    needs_confirmation: bool = True


class ParsedItem(BaseModel):
    label: str = ""
    brand: Optional[str] = None
    category: Optional[str] = None
    tags: list[str] = []
    is_chargeable: bool = False
    slot_name_hint: Optional[str] = None
    container_name_hint: Optional[str] = None
    zone_name_hint: Optional[str] = None


class MatchedSlot(BaseModel):
    slot_id: str
    slot_name: str
    container_name: str
    zone_name: str
    location_name: str
    breadcrumb: str


class ConfirmedSpeechItem(BaseModel):
    transcription: str
    parsed_item: ParsedItem
    slot_id: str
