from typing import Optional

from pydantic import BaseModel, Field


class HybridSearchRequest(BaseModel):
    text: Optional[str] = None
    image_file: Optional[str] = None
    location_id: Optional[str] = None
    category: Optional[str] = None
    limit: int = Field(default=20, ge=1, le=100)


class SearchResultItem(BaseModel):
    thumbnail_url: Optional[str] = None
    item_label: str
    breadcrumb: str
    slot_id: str
    last_updated: Optional[str] = None
    score: float = 0.0


class HybridSearchResponse(BaseModel):
    results: list[SearchResultItem]
    total: int
