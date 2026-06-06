import os
import uuid
import tempfile

from fastapi import APIRouter, Depends, UploadFile, File, Form
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.schemas import search as schemas
from app.services.search_service import SearchService
from app.services.semantic_search import semantic_search
from app.services.ai_recognition import ai_recognition

router = APIRouter()


def get_search_service(db: AsyncSession = Depends(get_db)) -> SearchService:
    return SearchService(db)


def _result_items(results: list[dict]) -> list[schemas.SearchResultItem]:
    return [
        schemas.SearchResultItem(
            id=r.get("id"),
            thumbnail_url=r.get("thumbnail_url"),
            item_label=r.get("label", r.get("item_label", "")),
            breadcrumb=r.get("breadcrumb", ""),
            slot_id=r.get("slot_id", ""),
            tags=r.get("tags") or [],
            is_deleted=r.get("is_deleted", False),
            deleted_at=r.get("deleted_at"),
            last_updated=r.get("last_updated"),
            score=r.get("score", r.get("rrf_score", 0.0)),
        )
        for r in results
    ]


@router.get("/recent", response_model=schemas.HybridSearchResponse)
async def recent_items(
    limit: int = 20,
    location_id: str | None = None,
    svc: SearchService = Depends(get_search_service),
):
    """Recently added/updated items for quick access below the search bar."""
    rows = await svc.list_recent_items(limit=limit, location_id=location_id)
    return schemas.HybridSearchResponse(
        results=[
            schemas.SearchResultItem(
                id=r.get("id"),
                item_label=r["item_label"],
                breadcrumb=r.get("breadcrumb", ""),
                slot_id=r.get("slot_id", ""),
                tags=r.get("tags") or [],
                score=1.0,
            )
            for r in rows
        ],
        total=len(rows),
    )


@router.get("/marks")
async def list_marks(
    location_id: str | None = None,
    include_history: bool = False,
    svc: SearchService = Depends(get_search_service),
):
    """各标记下的物品数量，用于筛选与批量归档。"""
    marks = await svc.list_marks(location_id=location_id, include_history=include_history)
    return {"marks": [schemas.MarkTagStat(**m) for m in marks]}


@router.get("/categories")
async def list_categories(
    location_id: str | None = None,
    svc: SearchService = Depends(get_search_service),
):
    """Distinct item categories for filter chips."""
    cats = await svc.list_categories(location_id=location_id)
    return {"categories": cats}


@router.post("/reindex")
async def reindex_search(svc: SearchService = Depends(get_search_service)):
    """Rebuild search index from database (run once after deploy)."""
    count = await svc.reindex_all_items()
    return {"status": "ok", "indexed": count}


@router.post("/hybrid", response_model=schemas.HybridSearchResponse)
async def hybrid_search(
    data: schemas.HybridSearchRequest,
    svc: SearchService = Depends(get_search_service),
):
    search_terms = data.text
    if data.text and len(data.text) >= 2 and not data.include_history:
        expanded = await semantic_search.expand_query(data.text)
        search_terms = " ".join(expanded)

    results = await svc.search(
        text=search_terms,
        location_id=data.location_id,
        category=data.category,
        tag=data.tag,
        include_history=data.include_history,
        limit=data.limit,
    )
    return schemas.HybridSearchResponse(results=_result_items(results), total=len(results))


@router.post("/by-image", response_model=schemas.HybridSearchResponse)
async def search_by_image(
    file: UploadFile = File(...),
    location_id: str | None = Form(None),
    limit: int = Form(default=20),
    svc: SearchService = Depends(get_search_service),
):
    """
    Upload an image → AI recognition extracts labels → text search finds similar items.
    """
    suffix = os.path.splitext(file.filename or "search.jpg")[1] or ".jpg"
    with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
        tmp.write(await file.read())
        tmp_path = tmp.name

    try:
        vision_result = await ai_recognition.analyze_image(tmp_path)

        items_detected = vision_result.get("items", [])
        if items_detected:
            labels = [item.get("label", "") for item in items_detected if item.get("label")]
            search_text = " ".join(labels[:5])
        else:
            search_text = vision_result.get("summary", "")

        if not search_text:
            return schemas.HybridSearchResponse(results=[], total=0)

        results = await svc.search(text=search_text, location_id=location_id, limit=limit)
        return schemas.HybridSearchResponse(results=_result_items(results), total=len(results))

    finally:
        os.unlink(tmp_path)
