from fastapi import APIRouter

from app.api.v1 import space, items, search, reminders

router = APIRouter()

router.include_router(space.router, prefix="/space", tags=["Space"])
router.include_router(items.router, prefix="/items", tags=["Items"])
router.include_router(search.router, prefix="/search", tags=["Search"])
router.include_router(reminders.router, prefix="/reminders", tags=["Reminders"])
