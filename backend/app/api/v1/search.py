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
            thumbnail_url=r.get("thumbnail_url"),
            item_label=r.get("label", r.get("item_label", "")),
            breadcrumb=r.get("breadcrumb", ""),
            slot_id=r.get("slot_id", ""),
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
                item_label=r["item_label"],
                breadcrumb=r.get("breadcrumb", ""),
                slot_id=r.get("slot_id", ""),
                score=1.0,
            )
            for r in rows
        ],
        total=len(rows),
    )


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
    if data.text and len(data.text) >= 2:
        expanded = await semantic_search.expand_query(data.text)
        search_terms = " ".join(expanded)

    results = await svc.search(
        text=search_terms,
        location_id=data.location_id,
        category=data.category,
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
    # Save temp file
    suffix = os.path.splitext(file.filename or "search.jpg")[1] or ".jpg"
    with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
        tmp.write(await file.read())
        tmp_path = tmp.name

    try:
        # Analyze image with AI
        vision_result = await ai_recognition.analyze_image(tmp_path)

        # Extract labels and use first few as search terms
        items_detected = vision_result.get("items", [])
        if items_detected:
            labels = [item.get("label", "") for item in items_detected if item.get("label")]
            search_text = " ".join(labels[:5])  # Use up to 5 detected labels
        else:
            # Fallback: use the summary as search text
            search_text = vision_result.get("summary", "")

        if not search_text:
            return schemas.HybridSearchResponse(results=[], total=0)

        results = await svc.search(text=search_text, location_id=location_id, limit=limit)
        return schemas.HybridSearchResponse(results=_result_items(results), total=len(results))

    finally:
        os.unlink(tmp_path)
