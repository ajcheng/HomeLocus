from fastapi import APIRouter

from app.api.v1 import space, items, search, reminders, speech, auth, family, audit, floor_plan, data_policy
from app.core.dependencies import require_auth

router = APIRouter()

# Public: register / login only (other /auth/* routes enforce auth per-endpoint).
router.include_router(auth.router, prefix="/auth", tags=["Auth"])

router.include_router(family.router, prefix="/families", tags=["Family"], dependencies=require_auth)
router.include_router(space.router, prefix="/space", tags=["Space"], dependencies=require_auth)
router.include_router(items.router, prefix="/items", tags=["Items"], dependencies=require_auth)
router.include_router(search.router, prefix="/search", tags=["Search"], dependencies=require_auth)
router.include_router(reminders.router, prefix="/reminders", tags=["Reminders"], dependencies=require_auth)
router.include_router(speech.router, prefix="/speech", tags=["Speech"], dependencies=require_auth)
router.include_router(audit.router, prefix="/audit", tags=["Audit"], dependencies=require_auth)
router.include_router(floor_plan.router, prefix="/floor-plans", tags=["FloorPlans"], dependencies=require_auth)
router.include_router(data_policy.router, prefix="/data-policy", tags=["DataPolicy"], dependencies=require_auth)
