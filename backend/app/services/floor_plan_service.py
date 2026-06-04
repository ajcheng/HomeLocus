from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.item import Item
from app.models.space import Zone, Container, Slot


class FloorPlanService:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def zone_item_counts(self, location_id: str) -> dict[str, int]:
        """Count items per zone within a location."""
        stmt = (
            select(Zone.id, func.count(Item.id))
            .join(Container, Container.zone_id == Zone.id)
            .join(Slot, Slot.container_id == Container.id)
            .outerjoin(Item, Item.slot_id == Slot.id)
            .where(Zone.location_id == location_id)
            .group_by(Zone.id)
        )
        result = await self.db.execute(stmt)
        return {row[0]: int(row[1]) for row in result.all()}
