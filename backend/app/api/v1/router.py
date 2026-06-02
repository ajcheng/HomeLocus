from fastapi import APIRouter

from app.api.v1 import space, items, search, reminders, speech, auth, family, audit

router = APIRouter()

router.include_router(auth.router, prefix="/auth", tags=["Auth"])
router.include_router(family.router, prefix="/families", tags=["Family"])
router.include_router(space.router, prefix="/space", tags=["Space"])
router.include_router(items.router, prefix="/items", tags=["Items"])
router.include_router(search.router, prefix="/search", tags=["Search"])
router.include_router(reminders.router, prefix="/reminders", tags=["Reminders"])
router.include_router(speech.router, prefix="/speech", tags=["Speech"])
router.include_router(audit.router, prefix="/audit", tags=["Audit"])
