from typing import Optional

from sqlalchemy import select, or_, distinct
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
        category: Optional[str] = None,
        limit: int = 20,
    ) -> list[dict]:
        # Meilisearch text search (vector optional)
        hits = search_engine.hybrid_search(
            text=text, vector=vector, location_id=location_id, category=category, limit=limit
        )

        # Fallback to DB when index empty or Meilisearch unavailable
        if text and len(hits) < limit:
            db_hits = await self._search_db(text, location_id, category, limit)
            seen = {h["id"] for h in hits}
            for h in db_hits:
                if h["id"] not in seen:
                    hits.append(h)
                    seen.add(h["id"])
            hits = hits[:limit]

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

    async def _location_id_for_slot(self, slot_id: str) -> str:
        stmt = (
            select(Location.id)
            .join(Zone, Zone.location_id == Location.id)
            .join(Container, Container.zone_id == Zone.id)
            .join(Slot, Slot.container_id == Container.id)
            .where(Slot.id == slot_id)
        )
        result = await self.db.execute(stmt)
        return result.scalar_one_or_none() or ""

    async def index_item_record(self, item: Item) -> None:
        """Index a DB item into Meilisearch after add/confirm."""
        location_id = await self._location_id_for_slot(item.slot_id)
        tags = item.tags if isinstance(item.tags, list) else []
        search_engine.index_text(
            item.id,
            item.label,
            item.brand,
            tags,
            "",
            location_id,
            item.category,
        )

    async def reindex_all_items(self) -> int:
        """Rebuild Meilisearch index from all items in DB."""
        result = await self.db.execute(select(Item))
        items = list(result.scalars().all())
        for item in items:
            await self.index_item_record(item)
        return len(items)

    async def list_categories(self, location_id: str | None = None) -> list[str]:
        stmt = select(distinct(Item.category)).where(Item.category.isnot(None), Item.category != "")
        if location_id:
            stmt = (
                stmt.join(Slot, Item.slot_id == Slot.id)
                .join(Container, Slot.container_id == Container.id)
                .join(Zone, Container.zone_id == Zone.id)
                .where(Zone.location_id == location_id)
            )
        result = await self.db.execute(stmt.order_by(Item.category))
        return [row[0] for row in result.all() if row[0]]

    async def _search_db(
        self, text: str, location_id: str | None, category: str | None, limit: int
    ) -> list[dict]:
        pattern = f"%{text}%"
        stmt = (
            select(Item, Slot, Container, Zone, Location)
            .join(Slot, Item.slot_id == Slot.id)
            .join(Container, Slot.container_id == Container.id)
            .join(Zone, Container.zone_id == Zone.id)
            .join(Location, Zone.location_id == Location.id)
            .where(
                or_(
                    Item.label.ilike(pattern),
                    Item.brand.ilike(pattern),
                    Item.category.ilike(pattern),
                    Item.ai_label_raw.ilike(pattern),
                )
            )
        )
        if location_id:
            stmt = stmt.where(Location.id == location_id)
        if category:
            stmt = stmt.where(Item.category == category)
        stmt = stmt.order_by(Item.updated_at.desc()).limit(limit)
        result = await self.db.execute(stmt)
        rows = result.all()
        return [
            {
                "id": item.id,
                "label": item.label,
                "item_label": item.label,
                "score": 0.9,
                "slot_id": slot.id,
                "breadcrumb": f"{loc.name} / {zone.name} / {container.name} / {slot.name}",
                "thumbnail_url": item.thumbnail_path or "",
                "last_updated": item.updated_at.isoformat() if item.updated_at else None,
            }
            for item, slot, container, zone, loc in rows
        ]

    async def list_recent_items(self, limit: int = 20, location_id: str | None = None) -> list[dict]:
        stmt = (
            select(Item, Slot, Container, Zone, Location)
            .join(Slot, Item.slot_id == Slot.id)
            .join(Container, Slot.container_id == Container.id)
            .join(Zone, Container.zone_id == Zone.id)
            .join(Location, Zone.location_id == Location.id)
        )
        if location_id:
            stmt = stmt.where(Location.id == location_id)
        stmt = stmt.order_by(Item.updated_at.desc()).limit(limit)
        result = await self.db.execute(stmt)
        return [
            {
                "id": item.id,
                "item_label": item.label,
                "slot_id": slot.id,
                "breadcrumb": f"{loc.name} / {zone.name} / {container.name} / {slot.name}",
            }
            for item, slot, container, zone, loc in result.all()
        ]

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
