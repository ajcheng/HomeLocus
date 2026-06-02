from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.schemas import search as schemas
from app.services.search_service import SearchService
from app.services.semantic_search import semantic_search

router = APIRouter()


def get_search_service(db: AsyncSession = Depends(get_db)) -> SearchService:
    return SearchService(db)


@router.post("/hybrid", response_model=schemas.HybridSearchResponse)
async def hybrid_search(
    data: schemas.HybridSearchRequest,
    svc: SearchService = Depends(get_search_service),
):
    # Semantic query expansion for fuzzy search
    search_terms = data.text
    if data.text and len(data.text) >= 2:
        expanded = await semantic_search.expand_query(data.text)
        # Combine expanded terms for Meilisearch multi-word search
        search_terms = " ".join(expanded)

    results = await svc.search(
        text=search_terms,
        location_id=data.location_id,
        limit=data.limit,
    )

    items = [
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

    return schemas.HybridSearchResponse(results=items, total=len(items))


@router.post("/by-image", response_model=schemas.HybridSearchResponse)
async def search_by_image(
    data: schemas.HybridSearchRequest,
    svc: SearchService = Depends(get_search_service),
):
    """
    Image search: generate CLIP vector from image and search Qdrant.
    Falls back to empty results when AI is not configured.
    """
    # TODO: Generate CLIP embedding from image_file
    results = await svc.search(
        vector=None,  # CLIP embedding placeholder
        location_id=data.location_id,
        limit=data.limit,
    )

    items = [
        schemas.SearchResultItem(
            thumbnail_url=r.get("thumbnail_url"),
            item_label=r.get("label", ""),
            breadcrumb=r.get("breadcrumb", ""),
            slot_id=r.get("slot_id", ""),
            last_updated=r.get("last_updated"),
            score=r.get("score", 0.0),
        )
        for r in results
    ]

    return schemas.HybridSearchResponse(results=items, total=len(items))
