import uuid
from datetime import datetime, timezone

from sqlalchemy import select, update, delete
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.item import Item, ImageSnapshot
from app.models.reminder import Reminder
from app.models.space import Slot, Container, Zone, Location
from app.services.storage_service import storage_service
from app.schemas import item as schemas
from app.schemas import reminder as reminder_schemas
from app.services.search_service import SearchService
from app.utils.search_synonyms import search_tags_for_item
from app.services.reminder_service import ReminderService


class ItemService:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def create_snapshot(self, slot_id: str, original_path: str, task_id: str) -> ImageSnapshot:
        # Mark existing snapshots as historical
        await self.db.execute(
            update(ImageSnapshot)
            .where(ImageSnapshot.slot_id == slot_id, ImageSnapshot.is_current == True)
            .values(is_current=False)
        )
        snapshot = ImageSnapshot(
            slot_id=slot_id,
            original_path=original_path,
            task_id=task_id,
            is_current=True,
        )
        self.db.add(snapshot)
        await self.db.commit()
        await self.db.refresh(snapshot)
        return snapshot

    async def get_task_status_from_db(self, task_id: str) -> schemas.TaskStatusResponse | None:
        stmt = select(ImageSnapshot).where(ImageSnapshot.task_id == task_id)
        result = await self.db.execute(stmt)
        snapshot = result.scalar_one_or_none()
        if not snapshot or not snapshot.ai_response_raw:
            return None
        items = snapshot.ai_response_raw.get("items", [])
        if not items:
            return None
        return schemas.TaskStatusResponse(
            task_id=task_id,
            status="completed",
            items=items,
        )

    async def update_task_result(self, task_id: str, items_data: list[dict]) -> ImageSnapshot:
        stmt = select(ImageSnapshot).where(ImageSnapshot.task_id == task_id)
        result = await self.db.execute(stmt)
        snapshot = result.scalar_one_or_none()
        if not snapshot:
            raise ValueError(f"Task {task_id} not found")

        snapshot.ai_response_raw = {"items": items_data}
        await self.db.commit()
        return snapshot

    async def confirm_item(self, item_id: str, data: schemas.ConfirmItemRequest) -> Item | None:
        item = await self.db.get(Item, item_id)
        if not item:
            item = Item(
                id=item_id,
                slot_id=data.slot_id,
                label=data.confirmed_label,
                brand=data.brand,
                category=data.category,
                color=data.color,
                purpose=data.purpose,
                raw_recognition=data.raw_recognition or data.confirmed_label,
                bounding_box=data.bounding_box,
                thumbnail_path=data.thumbnail_path,
                confidence=data.confidence,
                ai_label_raw=data.confirmed_label,
                is_chargeable=data.is_chargeable_device,
                charge_cycle_days=data.charge_reminder_cycle_days,
                is_confirmed=True,
            )
            self.db.add(item)
        else:
            if item.is_confirmed:
                return item
            item.label = data.confirmed_label
            if data.bounding_box:
                item.bounding_box = data.bounding_box
            if data.brand is not None:
                item.brand = data.brand
            if data.category is not None:
                item.category = data.category
            if data.color is not None:
                item.color = data.color
            if data.purpose is not None:
                item.purpose = data.purpose
            if data.raw_recognition is not None:
                item.raw_recognition = data.raw_recognition
            if data.thumbnail_path is not None:
                item.thumbnail_path = data.thumbnail_path
            if data.confidence is not None:
                item.confidence = data.confidence
            item.is_chargeable = data.is_chargeable_device
            item.charge_cycle_days = data.charge_reminder_cycle_days
            item.is_confirmed = True
        item.tags = search_tags_for_item(
            item.label,
            item.brand,
            item.category,
            item.tags if isinstance(item.tags, list) else [],
        )
        await self.db.commit()
        await self.db.refresh(item)
        await SearchService(self.db).index_item_record(item)
        if item.is_chargeable:
            await ReminderService(self.db).complete_charge(
                reminder_schemas.ChargeCompleteRequest(
                    item_id=item.id,
                    next_reminder_days=item.charge_cycle_days or 90,
                )
            )
        return item

    async def confirm_items_batch(
        self, slot_id: str, items: list[schemas.ConfirmItemRequest]
    ) -> list[Item]:
        confirmed: list[Item] = []
        for data in items:
            data.slot_id = slot_id
            item_id = data.item_id or f"item_{uuid.uuid4().hex[:8]}"
            item = await self.confirm_item(item_id, data)
            if item:
                confirmed.append(item)
        return confirmed

    async def create_manual_item(self, data: schemas.ManualItemCreate) -> Item:
        item = Item(
            slot_id=data.slot_id,
            label=data.label,
            brand=data.brand,
            category=data.category,
            color=data.color,
            purpose=data.purpose,
            raw_recognition=data.raw_recognition,
            tags=search_tags_for_item(
                data.label,
                data.brand,
                data.category,
                data.tags or [],
            ),
            is_chargeable=data.is_chargeable_device,
            charge_cycle_days=data.charge_reminder_cycle_days,
            is_confirmed=True,
        )
        self.db.add(item)
        await self.db.commit()
        await self.db.refresh(item)
        await SearchService(self.db).index_item_record(item)
        if item.is_chargeable:
            await ReminderService(self.db).complete_charge(
                reminder_schemas.ChargeCompleteRequest(
                    item_id=item.id,
                    next_reminder_days=item.charge_cycle_days or 90,
                )
            )
        return item

    async def soft_delete_item(self, item_id: str) -> bool:
        """逻辑删除：移出日常搜索，保留历史可查。"""
        item = await self.db.get(Item, item_id)
        if not item or item.is_deleted:
            return False
        item.is_deleted = True
        item.deleted_at = datetime.now(timezone.utc)
        await self.db.execute(delete(Reminder).where(Reminder.item_id == item_id))
        await self.db.commit()
        SearchService(self.db).delete_item_index(item_id)
        return True

    async def update_item_tags(self, item_id: str, tags: list[str]) -> Item | None:
        item = await self.db.get(Item, item_id)
        if not item or item.is_deleted:
            return None
        cleaned = list(dict.fromkeys(t.strip() for t in tags if t and t.strip()))[:10]
        item.tags = cleaned
        await self.db.commit()
        await self.db.refresh(item)
        if item.is_confirmed:
            await SearchService(self.db).index_item_record(item)
        return item

    async def archive_by_tag(self, tag: str, location_id: str | None = None) -> int:
        """将带指定标记的现存物品批量逻辑删除（如已完成搬回老家/送人）。"""
        tag = tag.strip()
        if not tag:
            return 0
        stmt = (
            select(Item)
            .join(Slot, Item.slot_id == Slot.id)
            .join(Container, Slot.container_id == Container.id)
            .join(Zone, Container.zone_id == Zone.id)
            .where(
                Item.is_deleted == False,
                Item.is_confirmed == True,
                Item.tags.contains([tag]),
            )
        )
        if location_id:
            stmt = stmt.where(Zone.location_id == location_id)
        result = await self.db.execute(stmt)
        items = list(result.scalars().all())
        now = datetime.now(timezone.utc)
        svc = SearchService(self.db)
        for item in items:
            item.is_deleted = True
            item.deleted_at = now
            await self.db.execute(delete(Reminder).where(Reminder.item_id == item.id))
            svc.delete_item_index(item.id)
        await self.db.commit()
        return len(items)

    async def lookup_items(self, item_ids: list[str]) -> list[dict]:
        """按 ID 批量查询物品摘要（供本机图库关联展示）。"""
        if not item_ids:
            return []
        stmt = (
            select(Item, Slot, Container, Zone, Location)
            .outerjoin(Slot, Item.slot_id == Slot.id)
            .outerjoin(Container, Slot.container_id == Container.id)
            .outerjoin(Zone, Container.zone_id == Zone.id)
            .outerjoin(Location, Zone.location_id == Location.id)
            .where(Item.id.in_(item_ids), Item.is_deleted == False)
        )
        result = await self.db.execute(stmt)
        rows = result.all()
        out: list[dict] = []
        for item, slot, container, zone, loc in rows:
            breadcrumb = (
                f"{loc.name} / {zone.name} / {container.name} / {slot.name}"
                if slot and container and zone and loc
                else "位置已删除"
            )
            out.append(
                {
                    "id": item.id,
                    "label": item.label,
                    "breadcrumb": breadcrumb,
                    "created_at": item.created_at.isoformat() if item.created_at else None,
                    "location_id": loc.id if loc else None,
                }
            )
        return out

    async def get_slot_items(self, slot_id: str) -> list[Item]:
        stmt = (
            select(Item)
            .where(Item.slot_id == slot_id, Item.is_confirmed == True, Item.is_deleted == False)
            .order_by(Item.updated_at.desc())
        )
        result = await self.db.execute(stmt)
        return list(result.scalars().all())

    async def list_gallery(
        self,
        location_id: str | None = None,
        sort_by: str = "time",
        descending: bool = True,
        limit: int = 200,
    ) -> list[schemas.GalleryItemResponse]:
        stmt = (
            select(ImageSnapshot, Slot, Container, Zone, Location)
            .join(Slot, ImageSnapshot.slot_id == Slot.id)
            .join(Container, Slot.container_id == Container.id)
            .join(Zone, Container.zone_id == Zone.id)
            .join(Location, Zone.location_id == Location.id)
            .where(ImageSnapshot.original_path.isnot(None))
        )
        if location_id:
            stmt = stmt.where(Location.id == location_id)
        if sort_by == "space":
            stmt = stmt.order_by(
                Location.name.desc() if descending else Location.name.asc(),
                Zone.name.desc() if descending else Zone.name.asc(),
                Container.name.desc() if descending else Container.name.asc(),
                Slot.name.desc() if descending else Slot.name.asc(),
                ImageSnapshot.created_at.desc(),
            )
        else:
            stmt = stmt.order_by(
                ImageSnapshot.created_at.desc() if descending else ImageSnapshot.created_at.asc()
            )
        stmt = stmt.limit(limit)
        result = await self.db.execute(stmt)
        rows = result.all()
        gallery: list[schemas.GalleryItemResponse] = []
        for snap, slot, container, zone, loc in rows:
            path = snap.compressed_path or snap.original_path
            if not path or path.startswith("/tmp"):
                continue
            label = "拍照记录"
            if snap.ai_response_raw and isinstance(snap.ai_response_raw, dict):
                items = snap.ai_response_raw.get("items") or []
                if items:
                    label = items[0].get("label") or label
            gallery.append(
                schemas.GalleryItemResponse(
                    id=snap.id,
                    label=label,
                    image_url=storage_service.get_presigned_url(path),
                    thumbnail_url=storage_service.get_presigned_url(path),
                    breadcrumb=f"{loc.name} / {zone.name} / {container.name} / {slot.name}",
                    created_at=snap.created_at,
                    slot_id=snap.slot_id,
                )
            )
        return gallery

    def item_to_response(self, item: Item) -> schemas.ItemResponse:
        return schemas.ItemResponse(
            id=item.id,
            slot_id=item.slot_id,
            label=item.label,
            brand=item.brand,
            category=item.category,
            color=item.color,
            purpose=item.purpose,
            raw_recognition=item.raw_recognition,
            tags=item.tags or [],
            thumbnail_path=item.thumbnail_path,
            is_chargeable=item.is_chargeable,
            charge_cycle_days=item.charge_cycle_days,
            is_borrowed=item.is_borrowed,
            borrower=item.borrower,
            confidence=item.confidence,
            is_deleted=item.is_deleted,
            deleted_at=item.deleted_at,
            created_at=item.created_at,
        )

    async def get_slot_history(self, slot_id: str) -> list[ImageSnapshot]:
        stmt = (
            select(ImageSnapshot)
            .where(ImageSnapshot.slot_id == slot_id)
            .options(selectinload(ImageSnapshot.item))
            .order_by(ImageSnapshot.created_at.desc())
        )
        result = await self.db.execute(stmt)
        return list(result.scalars().all())

    async def rollback_to_snapshot(self, snapshot_id: str) -> ImageSnapshot | None:
        target = await self.db.get(ImageSnapshot, snapshot_id)
        if not target:
            return None
        await self.db.execute(
            update(ImageSnapshot)
            .where(ImageSnapshot.slot_id == target.slot_id, ImageSnapshot.is_current == True)
            .values(is_current=False)
        )
        target.is_current = True
        await self.db.commit()
        await self.db.refresh(target)
        return target
