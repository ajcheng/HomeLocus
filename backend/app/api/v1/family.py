from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import get_current_user
from app.models.user import User
from app.schemas import family as schemas
from app.services.family_service import FamilyService
from app.services.audit_service import AuditService

router = APIRouter()


def get_family_service(db: AsyncSession = Depends(get_db)) -> FamilyService:
    return FamilyService(db)


def get_audit_service(db: AsyncSession = Depends(get_db)) -> AuditService:
    return AuditService(db)


@router.post("", response_model=schemas.FamilyResponse, status_code=201)
async def create_family(
    data: schemas.FamilyCreate,
    user: User = Depends(get_current_user),
    svc: FamilyService = Depends(get_family_service),
    audit: AuditService = Depends(get_audit_service),
):
    family = await svc.create_family(user, data.name)
    await audit.log(user.id, user.username, "family_created", "family", family.id, f"创建家庭: {data.name}")
    return schemas.FamilyResponse(
        id=family.id, name=family.name, member_count=1, role="admin", created_at=family.created_at,
    )


@router.get("", response_model=list[schemas.FamilyResponse])
async def list_families(
    user: User = Depends(get_current_user),
    svc: FamilyService = Depends(get_family_service),
):
    return await svc.list_families(user)


@router.get("/{family_id}/members", response_model=list[schemas.MemberResponse])
async def list_members(
    family_id: str,
    user: User = Depends(get_current_user),
    svc: FamilyService = Depends(get_family_service),
):
    if not await svc.check_access(user, family_id):
        raise HTTPException(status_code=403, detail="Not a member of this family")
    return await svc.get_members(family_id)


@router.put("/{family_id}/members/{user_id}/role")
async def update_member_role(
    family_id: str,
    user_id: str,
    role: str = "member",
    user: User = Depends(get_current_user),
    svc: FamilyService = Depends(get_family_service),
    audit: AuditService = Depends(get_audit_service),
):
    if not await svc.check_admin(user, family_id):
        raise HTTPException(status_code=403, detail="Only family admin can change roles")
    ok = await svc.update_member_role(family_id, user_id, role)
    if not ok:
        raise HTTPException(status_code=404, detail="Member not found")
    await audit.log(user.id, user.username, "role_changed", "member", user_id, f"Role changed to {role}", family_id=family_id)
    return {"status": "updated"}


@router.delete("/{family_id}/members/{user_id}")
async def remove_member(
    family_id: str,
    user_id: str,
    user: User = Depends(get_current_user),
    svc: FamilyService = Depends(get_family_service),
    audit: AuditService = Depends(get_audit_service),
):
    if not await svc.check_admin(user, family_id):
        raise HTTPException(status_code=403, detail="Only family admin can remove members")
    ok = await svc.remove_member(family_id, user_id)
    if not ok:
        raise HTTPException(status_code=404, detail="Member not found")
    await audit.log(user.id, user.username, "member_removed", "member", user_id, "Removed from family", family_id=family_id)
    return {"status": "removed"}


@router.post("/{family_id}/invitations", response_model=schemas.InvitationResponse)
async def create_invitation(
    family_id: str,
    data: schemas.InvitationCreate,
    user: User = Depends(get_current_user),
    svc: FamilyService = Depends(get_family_service),
):
    if not await svc.check_admin(user, family_id):
        raise HTTPException(status_code=403, detail="Only family admin can create invitations")
    inv = await svc.create_invitation(user, family_id, data.max_uses)
    return schemas.InvitationResponse(
        id=inv.id, code=inv.code, expires_at=inv.expires_at,
        max_uses=inv.max_uses, use_count=inv.use_count, is_active=inv.is_active,
    )


@router.get("/{family_id}/invitations", response_model=list[schemas.InvitationResponse])
async def list_invitations(
    family_id: str,
    user: User = Depends(get_current_user),
    svc: FamilyService = Depends(get_family_service),
):
    if not await svc.check_access(user, family_id):
        raise HTTPException(status_code=403, detail="Not a member")
    invs = await svc.list_invitations(family_id)
    return [
        schemas.InvitationResponse(
            id=i.id, code=i.code, expires_at=i.expires_at,
            max_uses=i.max_uses, use_count=i.use_count, is_active=i.is_active,
        )
        for i in invs
    ]


@router.post("/join", response_model=schemas.FamilyResponse)
async def join_family(
    data: schemas.JoinFamilyRequest,
    user: User = Depends(get_current_user),
    svc: FamilyService = Depends(get_family_service),
    audit: AuditService = Depends(get_audit_service),
):
    try:
        family = await svc.join_by_code(user, data.invitation_code)
    except ValueError as e:
        raise HTTPException(status_code=409, detail=str(e))

    if not family:
        raise HTTPException(status_code=404, detail="Invalid or expired invitation code")

    await audit.log(user.id, user.username, "member_joined", "family", family.id, f"通过邀请码加入", family_id=family.id)
    return schemas.FamilyResponse(
        id=family.id, name=family.name, member_count=len(family.members),
        role="member", created_at=family.created_at,
    )
