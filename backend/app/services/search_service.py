from typing import Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.space import Slot, Container, Zone, Location
from app.models.item import Item
from app.services.search_engine import search_engine


class SearchService:
    """Hybrid search with breadcrumb (location chain) enrichment."""

    def __init__(self, db: AsyncSession):
        self.db = db

    async def search(
        self,
        text: Optional[str] = None,
        vector: Optional[list[float]] = None,
        location_id: Optional[str] = None,
        limit: int = 20,
    ) -> list[dict]:
        # Raw search from engines
        hits = search_engine.hybrid_search(text=text, vector=vector, location_id=location_id, limit=limit)

        # Enrich with breadcrumbs from DB
        if not hits:
            return []

        item_ids = [h["id"] for h in hits if h.get("id")]
        if item_ids:
            enriched = await self._enrich_breadcrumbs(item_ids)
            # Merge enriched data into hits
            for hit in hits:
                extra = enriched.get(hit["id"], {})
                hit.update(extra)

        return hits

    async def _enrich_breadcrumbs(self, item_ids: list[str]) -> dict[str, dict]:
        """Look up full location chain for each item."""
        stmt = (
            select(Item, Slot, Container, Zone, Location)
            .join(Slot, Item.slot_id == Slot.id)
            .join(Container, Slot.container_id == Container.id)
            .join(Zone, Container.zone_id == Zone.id)
            .join(Location, Zone.location_id == Location.id)
            .where(Item.id.in_(item_ids))
        )
        result = await self.db.execute(stmt)
        rows = result.all()

        enriched = {}
        for item, slot, container, zone, location in rows:
            enriched[item.id] = {
                "slot_id": slot.id,
                "slot_name": slot.name,
                "container_name": container.name,
                "zone_name": zone.name,
                "location_name": location.name,
                "breadcrumb": f"{location.name} / {zone.name} / {container.name} / {slot.name}",
                "thumbnail_url": item.thumbnail_path or "",
                "last_updated": item.updated_at.isoformat() if item.updated_at else None,
                "label": item.label,
            }
        return enriched

    def index_item(
        self, item_id: str, label: str, brand: str | None,
        tags: list[str], ocr_text: str, location_id: str, vector: list[float] | None = None
    ):
        """Index item in both engines."""
        search_engine.index_text(item_id, label, brand, tags, ocr_text, location_id)
        if vector:
            search_engine.index_vector(item_id, vector, {"label": label, "location_id": location_id})

    def delete_item_index(self, item_id: str):
        search_engine.delete_text_index(item_id)
        search_engine.delete_vector_index(item_id)
