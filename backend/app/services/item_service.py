import uuid
from datetime import datetime

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.item import Item, ImageSnapshot
from app.models.space import Slot
from app.schemas import item as schemas
from app.services.search_service import SearchService


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
        for item_data in items_data:
            item_kwargs = dict(
                slot_id=snapshot.slot_id,
                label=item_data.get("label", "unknown"),
                brand=item_data.get("brand"),
                tags=item_data.get("tags", []),
                bounding_box=item_data.get("bounding_box"),
                thumbnail_path=item_data.get("thumbnail_path"),
                confidence=item_data.get("confidence"),
                ai_label_raw=item_data.get("label"),
            )
            if item_data.get("id"):
                item_kwargs["id"] = item_data["id"]
            item = Item(**item_kwargs)
            self.db.add(item)
        await self.db.commit()
        return snapshot

    async def confirm_item(self, item_id: str, data: schemas.ConfirmItemRequest) -> Item | None:
        item = await self.db.get(Item, item_id)
        if not item:
            # Recognition items may exist only in Celery result if DB persist failed
            item = Item(
                id=item_id,
                slot_id=data.slot_id,
                label=data.confirmed_label,
                brand=data.brand,
                bounding_box=data.bounding_box,
                thumbnail_path=data.thumbnail_path,
                confidence=data.confidence,
                ai_label_raw=data.confirmed_label,
                is_chargeable=data.is_chargeable_device,
                charge_cycle_days=data.charge_reminder_cycle_days,
            )
            self.db.add(item)
        else:
            item.label = data.confirmed_label
            if data.bounding_box:
                item.bounding_box = data.bounding_box
            if data.brand is not None:
                item.brand = data.brand
            if data.thumbnail_path is not None:
                item.thumbnail_path = data.thumbnail_path
            if data.confidence is not None:
                item.confidence = data.confidence
            item.is_chargeable = data.is_chargeable_device
            item.charge_cycle_days = data.charge_reminder_cycle_days
        await self.db.commit()
        await self.db.refresh(item)
        await SearchService(self.db).index_item_record(item)
        return item

    async def get_slot_items(self, slot_id: str, current_only: bool = True) -> list[Item]:
        stmt = select(Item).where(Item.slot_id == slot_id)
        if current_only:
            stmt = stmt.where(Item.snapshot_id == None)
        result = await self.db.execute(stmt.order_by(Item.created_at.desc()))
        return list(result.scalars().all())

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
