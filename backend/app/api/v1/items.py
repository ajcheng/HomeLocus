import uuid
import os

from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.config import settings
from app.schemas import item as schemas
from app.services.item_service import ItemService
from app.services.storage_service import storage_service
from app.tasks.recognition import process_upload

router = APIRouter()


def get_item_service(db: AsyncSession = Depends(get_db)) -> ItemService:
    return ItemService(db)


def _save_temp(slot_id: str, file: UploadFile) -> str:
    """Save uploaded file to temp storage, return absolute path."""
    upload_dir = os.path.join(settings.storage_local_path, slot_id)
    os.makedirs(upload_dir, exist_ok=True)
    ext = os.path.splitext(file.filename or "image.jpg")[1] or ".jpg"
    filename = f"{uuid.uuid4().hex}{ext}"
    filepath = os.path.join(upload_dir, filename)
    content = file.file.read()
    with open(filepath, "wb") as f:
        f.write(content)
    return filepath


@router.post("/upload", response_model=schemas.UploadResponse)
async def upload_image(
    slot_id: str = Form(...),
    file: UploadFile = File(...),
    svc: ItemService = Depends(get_item_service),
):
    filepath = _save_temp(slot_id, file)
    task_id = f"task_{uuid.uuid4().hex[:12]}"

    # Create snapshot record in DB
    snapshot = await svc.create_snapshot(slot_id, filepath, task_id)

    # Dispatch async AI recognition pipeline via Celery
    process_upload.delay(task_id, filepath, slot_id)

    return schemas.UploadResponse(task_id=task_id, status="processing", slot_id=slot_id)


@router.get("/task-status/{task_id}", response_model=schemas.TaskStatusResponse)
async def get_task_status(task_id: str, svc: ItemService = Depends(get_item_service)):
    from celery.result import AsyncResult
    from app.tasks.celery_app import celery_app

    result = AsyncResult(task_id, app=celery_app)

    if result.ready():
        if result.successful():
            data = result.result or {}
            items = data.get("items", [])
            return schemas.TaskStatusResponse(
                task_id=task_id,
                status="completed",
                items=items,
            )
        else:
            return schemas.TaskStatusResponse(
                task_id=task_id,
                status="failed",
                error=str(result.info) if result.info else "Unknown error",
            )
    else:
        return schemas.TaskStatusResponse(task_id=task_id, status="processing")


@router.put("/confirm/{item_id}", response_model=schemas.ItemResponse)
async def confirm_item(
    item_id: str,
    data: schemas.ConfirmItemRequest,
    svc: ItemService = Depends(get_item_service),
):
    item = await svc.confirm_item(item_id, data)
    if not item:
        raise HTTPException(status_code=404, detail="Item not found")
    return schemas.ItemResponse(
        id=item.id, slot_id=item.slot_id, label=item.label,
        brand=item.brand, tags=item.tags or [],
        thumbnail_path=item.thumbnail_path,
        is_chargeable=item.is_chargeable, charge_cycle_days=item.charge_cycle_days,
        is_borrowed=item.is_borrowed, borrower=item.borrower,
        confidence=item.confidence, created_at=item.created_at,
    )


@router.get("/history/{slot_id}", response_model=list[schemas.HistorySnapshotResponse])
async def get_slot_history(slot_id: str, svc: ItemService = Depends(get_item_service)):
    snapshots = await svc.get_slot_history(slot_id)
    return [
        schemas.HistorySnapshotResponse(
            id=s.id, slot_id=s.slot_id,
            original_path=s.original_path, compressed_path=s.compressed_path,
            is_current=s.is_current, created_at=s.created_at,
            items=[
                schemas.ItemResponse(
                    id=i.id, slot_id=i.slot_id, label=i.label,
                    brand=i.brand, tags=i.tags or [],
                    thumbnail_path=i.thumbnail_path,
                    is_chargeable=i.is_chargeable,
                    is_borrowed=i.is_borrowed,
                    confidence=i.confidence, created_at=i.created_at,
                )
                for i in (s.items or [])
            ],
        )
        for s in snapshots
    ]


@router.post("/version/rollback")
async def rollback_version(data: schemas.RollbackRequest, svc: ItemService = Depends(get_item_service)):
    snapshot = await svc.rollback_to_snapshot(data.snapshot_id)
    if not snapshot:
        raise HTTPException(status_code=404, detail="Snapshot not found")
    return {"status": "rolled_back", "snapshot_id": data.snapshot_id}
