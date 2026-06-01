from sqlalchemy import select, func, delete
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.space import Location, Zone, Container, Slot
from app.schemas import space as schemas


class SpaceService:
    def __init__(self, db: AsyncSession):
        self.db = db

    # ---- Location ----
    async def create_location(self, data: schemas.LocationCreate) -> Location:
        location = Location(name=data.name, is_default=data.is_default)
        self.db.add(location)
        await self.db.commit()
        await self.db.refresh(location)
        return location

    async def list_locations(self) -> list[dict]:
        result = await self.db.execute(
            select(
                Location,
                func.count(Zone.id).label("zone_count")
            )
            .outerjoin(Zone, Zone.location_id == Location.id)
            .group_by(Location.id)
            .order_by(Location.is_default.desc(), Location.created_at)
        )
        rows = result.all()
        return [
            schemas.LocationResponse(
                id=row.Location.id,
                name=row.Location.name,
                is_default=row.Location.is_default,
                created_at=row.Location.created_at,
                zone_count=row.zone_count,
            )
            for row in rows
        ]

    async def get_location(self, location_id: str) -> Location | None:
        return await self.db.get(Location, location_id)

    # ---- Zone ----
    async def create_zone(self, data: schemas.ZoneCreate) -> Zone:
        zone = Zone(location_id=data.location_id, name=data.name, template_type=data.template_type)
        self.db.add(zone)
        await self.db.commit()
        await self.db.refresh(zone)
        return zone

    async def list_zones(self, location_id: str | None = None) -> list[Zone]:
        stmt = select(Zone)
        if location_id:
            stmt = stmt.where(Zone.location_id == location_id)
        result = await self.db.execute(stmt.options(selectinload(Zone.containers)))
        return list(result.scalars().all())

    # ---- Container ----
    async def create_container(self, data: schemas.ContainerCreate) -> Container:
        container = Container(zone_id=data.zone_id, name=data.name)
        self.db.add(container)
        await self.db.flush()

        for slot_data in data.slots:
            slot = Slot(
                container_id=container.id,
                name=slot_data.name,
                level=slot_data.level,
            )
            self.db.add(slot)

        await self.db.commit()
        await self.db.refresh(container)
        return container

    async def get_container(self, container_id: str) -> Container | None:
        stmt = select(Container).where(Container.id == container_id).options(selectinload(Container.slots))
        result = await self.db.execute(stmt)
        return result.scalar_one_or_none()

    # ---- Slot ----
    async def create_slots(self, container_id: str, slots: list[schemas.SlotCreate]) -> list[Slot]:
        created = []
        for slot_data in slots:
            slot = Slot(
                container_id=container_id,
                name=slot_data.name,
                level=slot_data.level,
            )
            self.db.add(slot)
            created.append(slot)
        await self.db.commit()
        return created

    async def update_slot(self, slot_id: str, data: schemas.SlotUpdate) -> Slot | None:
        slot = await self.db.get(Slot, slot_id)
        if not slot:
            return None
        if data.name is not None:
            slot.name = data.name
        if data.level is not None:
            slot.level = data.level
        await self.db.commit()
        await self.db.refresh(slot)
        return slot

    async def delete_slot(self, slot_id: str) -> bool:
        slot = await self.db.get(Slot, slot_id)
        if not slot:
            return False
        await self.db.delete(slot)
        await self.db.commit()
        return True
