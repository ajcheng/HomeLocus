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

    # Use business task_id as Celery task id so /task-status can look up results
    process_upload.apply_async(
        args=[task_id, filepath, slot_id],
        task_id=task_id,
    )

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
        return schemas.TaskStatusResponse(
            task_id=task_id,
            status="failed",
            error=str(result.info) if result.info else "Unknown error",
        )

    # Fallback: Celery still running or result expired — check DB snapshot
    db_status = await svc.get_task_status_from_db(task_id)
    if db_status:
        return db_status

    return schemas.TaskStatusResponse(task_id=task_id, status="processing")


@router.get("/slot/{slot_id}", response_model=list[schemas.ItemResponse])
async def list_slot_items(slot_id: str, svc: ItemService = Depends(get_item_service)):
    """List all items in a storage slot (for space browser)."""
    items = await svc.get_slot_items(slot_id)
    return [svc.item_to_response(i) for i in items]


@router.post("/manual", response_model=schemas.ItemResponse, status_code=201)
async def create_manual_item(
    data: schemas.ManualItemCreate,
    svc: ItemService = Depends(get_item_service),
):
    """Add an item without photo recognition."""
    item = await svc.create_manual_item(data)
    return svc.item_to_response(item)


@router.put("/confirm/{item_id}", response_model=schemas.ItemResponse)
async def confirm_item(
    item_id: str,
    data: schemas.ConfirmItemRequest,
    svc: ItemService = Depends(get_item_service),
):
    item = await svc.confirm_item(item_id, data)
    if not item:
        raise HTTPException(status_code=404, detail="Item not found")
    return svc.item_to_response(item)


@router.post("/confirm-batch", response_model=list[schemas.ItemResponse])
async def confirm_items_batch(
    data: schemas.BatchConfirmRequest,
    svc: ItemService = Depends(get_item_service),
):
    """批量确认入库（仅用户选中的识别结果）。"""
    items = await svc.confirm_items_batch(data.slot_id, data.items)
    return [svc.item_to_response(i) for i in items]


@router.get("/history/{slot_id}", response_model=list[schemas.HistorySnapshotResponse])
async def get_slot_history(slot_id: str, svc: ItemService = Depends(get_item_service)):
    snapshots = await svc.get_slot_history(slot_id)
    return [
        schemas.HistorySnapshotResponse(
            id=s.id, slot_id=s.slot_id,
            original_path=s.original_path, compressed_path=s.compressed_path,
            is_current=s.is_current, created_at=s.created_at,
            items=[
                svc.item_to_response(i)
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
