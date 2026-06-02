from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import get_current_user
from app.models.user import User
from app.schemas import audit_log as schemas
from app.services.audit_service import AuditService
from app.services.family_service import FamilyService

router = APIRouter()


@router.get("/logs", response_model=list[schemas.AuditLogResponse])
async def get_logs(
    family_id: str | None = Query(None),
    action: str | None = Query(None),
    limit: int = Query(default=50, le=200),
    offset: int = Query(default=0),
    user: User = Depends(get_current_user),
    svc: AuditService = Depends(lambda db=Depends(get_db): AuditService(db)),
    fam_svc: FamilyService = Depends(lambda db=Depends(get_db): FamilyService(db)),
):
    if family_id and not await fam_svc.check_access(user, family_id):
        raise HTTPException(status_code=403, detail="Not a member of this family")

    logs = await svc.get_logs(family_id=family_id, user_id=user.id if not family_id else None, action=action, limit=limit, offset=offset)
    return [
        schemas.AuditLogResponse(
            id=l.id, user_id=l.user_id, username=l.username,
            action=l.action, entity_type=l.entity_type, entity_id=l.entity_id,
            description=l.description, changes=l.changes, created_at=l.created_at,
        )
        for l in logs
    ]
