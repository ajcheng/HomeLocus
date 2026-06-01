from fastapi import APIRouter

from app.schemas import search as schemas
from app.services.search_service import search_service

router = APIRouter()


@router.post("/hybrid", response_model=schemas.HybridSearchResponse)
async def hybrid_search(data: schemas.HybridSearchRequest):
    results = await search_service.hybrid_search(
        text=data.text,
        location_id=data.location_id,
        limit=data.limit,
    )
    return schemas.HybridSearchResponse(results=results, total=len(results))
