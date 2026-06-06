from typing import Optional

from pydantic import BaseModel, Field


class HybridSearchRequest(BaseModel):
    text: Optional[str] = None
    image_file: Optional[str] = None
    location_id: Optional[str] = None
    category: Optional[str] = None
    tag: Optional[str] = None
    include_history: bool = False
    limit: int = Field(default=20, ge=1, le=100)


class SearchResultItem(BaseModel):
    id: Optional[str] = None
    thumbnail_url: Optional[str] = None
    item_label: str
    breadcrumb: str
    slot_id: str
    tags: list[str] = []
    is_deleted: bool = False
    deleted_at: Optional[str] = None
    last_updated: Optional[str] = None
    score: float = 0.0


class MarkTagStat(BaseModel):
    tag: str
    count: int


class HybridSearchResponse(BaseModel):
    results: list[SearchResultItem]
    total: int
