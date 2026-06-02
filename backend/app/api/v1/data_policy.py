"""Data deletion policy endpoints."""
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select, delete
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import get_current_user
from app.models.user import User
from app.models.space import Slot
from app.models.item import Item, ImageSnapshot
from app.services.storage_service import storage_service
from app.services.audit_service import AuditService

router = APIRouter()


@router.delete("/slot/{slot_id}")
async def delete_slot_with_policy(
    slot_id: str,
    delete_photos: bool = Query(default=False, description="是否同时删除关联的照片文件"),
    keep_history: bool = Query(default=True, description="是否保留历史快照记录"),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    audit: AuditService = Depends(lambda db=Depends(get_db): AuditService(db)),
):
    """
    Delete a slot with configurable data retention policy:
    - delete_photos=true: Remove all photos from MinIO (permanent)
    - delete_photos=false: Keep photos in storage (default)
    - keep_history=true: Preserve historical snapshots (default)
    """
    slot = await db.get(Slot, slot_id)
    if not slot:
        raise HTTPException(status_code=404, detail="Slot not found")

    # Get associated snapshots and items
    snapshots_result = await db.execute(
        select(ImageSnapshot).where(ImageSnapshot.slot_id == slot_id)
    )
    snapshots = snapshots_result.scalars().all()

    items_result = await db.execute(
        select(Item).where(Item.slot_id == slot_id)
    )
    items = items_result.scalars().all()

    if delete_photos:
        # Delete photos from MinIO
        for snap in snapshots:
            if snap.original_path:
                try:
                    # Remove from MinIO if it's a MinIO path (no http prefix)
                    if not snap.original_path.startswith("http"):
                        storage_service.client.remove_object(storage_service.bucket, snap.original_path)
                except Exception:
                    pass
            if snap.compressed_path and not snap.compressed_path.startswith("http"):
                try:
                    storage_service.client.remove_object(storage_service.bucket, snap.compressed_path)
                except Exception:
                    pass

        # Delete thumbnails
        for item in items:
            if item.thumbnail_path and not item.thumbnail_path.startswith("http"):
                try:
                    storage_service.client.remove_object(storage_service.bucket, item.thumbnail_path)
                except Exception:
                    pass

        # Delete all snapshots
        await db.execute(delete(ImageSnapshot).where(ImageSnapshot.slot_id == slot_id))
        # Delete all items
        await db.execute(delete(Item).where(Item.slot_id == slot_id))
    elif not keep_history:
        # Delete history but keep current photos
        await db.execute(
            delete(ImageSnapshot).where(
                ImageSnapshot.slot_id == slot_id,
                ImageSnapshot.is_current == False,
            )
        )

    # Always delete the slot
    await db.delete(slot)

    await audit.log(
        user.id, user.username, "slot_deleted", "slot", slot_id,
        f"删除空间层级: {slot.name} (photos={delete_photos}, history={keep_history})",
    )

    await db.commit()
    return {
        "status": "deleted",
        "photos_deleted": delete_photos,
        "history_preserved": keep_history,
        "snapshots_affected": len(snapshots),
        "items_affected": len(items),
    }
