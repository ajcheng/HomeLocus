from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.schemas import search as schemas
from app.services.search_service import SearchService

router = APIRouter()


def get_search_service(db: AsyncSession = Depends(get_db)) -> SearchService:
    return SearchService(db)


@router.post("/hybrid", response_model=schemas.HybridSearchResponse)
async def hybrid_search(
    data: schemas.HybridSearchRequest,
    svc: SearchService = Depends(get_search_service),
):
    results = await svc.search(
        text=data.text,
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
