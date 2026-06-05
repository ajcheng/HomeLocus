from sqlalchemy import select, func, delete, or_
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.family import Family, FamilyMember
from app.models.floor_plan import FloorPlan
from app.models.item import ImageSnapshot, Item
from app.models.reminder import Reminder
from app.models.space import Location, Zone, Container, Slot
from app.schemas import space as schemas
from app.services.space_templates import HOME_SPACE_TEMPLATE


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

    async def list_locations(self, user_id: str | None = None) -> list[dict]:
        stmt = (
            select(
                Location,
                func.count(Zone.id).label("zone_count"),
                Family.name.label("family_name"),
            )
            .outerjoin(Zone, Zone.location_id == Location.id)
            .outerjoin(Family, Family.id == Location.family_id)
            .group_by(Location.id, Family.name)
        )
        if user_id:
            fam_ids_subq = (
                select(FamilyMember.family_id).where(FamilyMember.user_id == user_id)
            )
            stmt = stmt.where(
                or_(Location.family_id.is_(None), Location.family_id.in_(fam_ids_subq))
            )
        stmt = stmt.order_by(Location.is_default.desc(), Location.created_at)
        result = await self.db.execute(stmt)
        rows = result.all()
        return [
            schemas.LocationResponse(
                id=row.Location.id,
                name=row.Location.name,
                is_default=row.Location.is_default,
                created_at=row.Location.created_at,
                zone_count=row.zone_count,
                family_id=row.Location.family_id,
                family_name=row.family_name,
            )
            for row in rows
        ]

    async def get_location(self, location_id: str) -> Location | None:
        return await self.db.get(Location, location_id)

    async def delete_location(self, location_id: str) -> bool:
        """删除地点及下属分区/物品；先清理平面图与快照等外键依赖。"""
        result = await self.db.execute(
            select(Location)
            .where(Location.id == location_id)
            .options(
                selectinload(Location.zones)
                .selectinload(Zone.containers)
                .selectinload(Container.slots)
            )
        )
        loc = result.scalar_one_or_none()
        if not loc:
            return False

        slot_ids: list[str] = []
        for zone in loc.zones:
            for container in zone.containers:
                slot_ids.extend(s.id for s in container.slots)

        if slot_ids:
            item_rows = await self.db.execute(
                select(Item.id).where(Item.slot_id.in_(slot_ids))
            )
            item_ids = [r[0] for r in item_rows.all()]
            if item_ids:
                await self.db.execute(delete(Reminder).where(Reminder.item_id.in_(item_ids)))
            await self.db.execute(delete(ImageSnapshot).where(ImageSnapshot.slot_id.in_(slot_ids)))

        fp_rows = await self.db.execute(
            select(FloorPlan).where(FloorPlan.location_id == location_id)
        )
        for fp in fp_rows.scalars().all():
            await self.db.delete(fp)

        await self.db.delete(loc)
        await self.db.commit()
        return True

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

        # Reload with slots eagerly to avoid async lazy-load issues
        stmt = select(Container).where(Container.id == container.id).options(selectinload(Container.slots))
        result = await self.db.execute(stmt)
        return result.scalar_one()

    async def list_containers(self, zone_id: str | None = None) -> list[Container]:
        stmt = select(Container).options(selectinload(Container.slots))
        if zone_id:
            stmt = stmt.where(Container.zone_id == zone_id)
        result = await self.db.execute(stmt)
        return list(result.scalars().all())

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

    async def get_zone_path(self, zone_id: str) -> schemas.ZonePathResponse | None:
        stmt = (
            select(Zone, Location)
            .join(Location, Zone.location_id == Location.id)
            .where(Zone.id == zone_id)
        )
        result = await self.db.execute(stmt)
        row = result.first()
        if not row:
            return None
        zone, location = row
        return schemas.ZonePathResponse(
            zone_id=zone.id,
            zone_name=zone.name,
            location_id=location.id,
            location_name=location.name,
        )

    async def get_slot_path(self, slot_id: str) -> schemas.SlotPathResponse | None:
        stmt = (
            select(Slot, Container, Zone, Location)
            .join(Container, Slot.container_id == Container.id)
            .join(Zone, Container.zone_id == Zone.id)
            .join(Location, Zone.location_id == Location.id)
            .where(Slot.id == slot_id)
        )
        result = await self.db.execute(stmt)
        row = result.first()
        if not row:
            return None
        slot, container, zone, location = row
        return schemas.SlotPathResponse(
            slot_id=slot.id,
            slot_name=slot.name,
            container_id=container.id,
            container_name=container.name,
            zone_id=zone.id,
            zone_name=zone.name,
            location_id=location.id,
            location_name=location.name,
            breadcrumb=f"{location.name} / {zone.name} / {container.name} / {slot.name}",
        )

    async def apply_home_template(self, location_id: str) -> int:
        """Apply standard home zones/containers/slots to an existing location. Returns slot count."""
        location = await self.db.get(Location, location_id)
        if not location:
            raise ValueError(f"Location {location_id} not found")

        count = 0
        for zone_name, containers in HOME_SPACE_TEMPLATE.items():
            zone = Zone(location_id=location_id, name=zone_name)
            self.db.add(zone)
            await self.db.flush()
            for container_name, slots in containers:
                container = Container(zone_id=zone.id, name=container_name)
                self.db.add(container)
                await self.db.flush()
                for slot_name, level in slots:
                    self.db.add(Slot(container_id=container.id, name=slot_name, level=level))
                    count += 1
        await self.db.commit()
        return count
