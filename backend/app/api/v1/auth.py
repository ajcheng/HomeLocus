from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select, delete
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import get_current_user
from app.models.user import User
from app.schemas import auth as schemas
from app.services.auth_service import AuthService, verify_password

router = APIRouter()


def get_auth_service(db: AsyncSession = Depends(get_db)) -> AuthService:
    return AuthService(db)


@router.post("/register", response_model=schemas.TokenResponse, status_code=201)
async def register(data: schemas.RegisterRequest, svc: AuthService = Depends(get_auth_service)):
    try:
        user = await svc.register(data.username, data.email, data.password)
    except ValueError as e:
        raise HTTPException(status_code=409, detail=str(e))
    from app.services.auth_service import create_access_token
    token = create_access_token(user)
    return schemas.TokenResponse(
        access_token=token,
        user=schemas.UserResponse(id=user.id, username=user.username, email=user.email, is_active=user.is_active),
    )


@router.post("/login", response_model=schemas.TokenResponse)
async def login(data: schemas.LoginRequest, svc: AuthService = Depends(get_auth_service)):
    token = await svc.login(data.username, data.password)
    if not token:
        raise HTTPException(status_code=401, detail="Invalid username or password")
    from app.services.auth_service import decode_token
    payload = decode_token(token)
    return schemas.TokenResponse(
        access_token=token,
        user=schemas.UserResponse(id=payload.get("sub", ""), username=payload.get("username", ""), email="", is_active=True),
    )


# ---- User Management ----

@router.post("/change-password")
async def change_password(
    data: schemas.ChangePasswordRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    if not verify_password(data.old_password, user.password_hash):
        raise HTTPException(status_code=400, detail="Current password is incorrect")
    from app.services.auth_service import hash_password
    user.password_hash = hash_password(data.new_password)
    await db.commit()
    return {"status": "password_changed"}


@router.get("/users", response_model=list[schemas.UserResponse])
async def list_users(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(User).order_by(User.created_at))
    users = result.scalars().all()
    return [
        schemas.UserResponse(id=u.id, username=u.username, email=u.email, is_active=u.is_active)
        for u in users
    ]


@router.post("/users", response_model=schemas.UserResponse, status_code=201)
async def create_user(
    data: schemas.RegisterRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    from app.services.auth_service import hash_password
    existing = await db.execute(select(User).where((User.username == data.username) | (User.email == data.email)))
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=409, detail="Username or email already exists")
    new_user = User(username=data.username, email=data.email, password_hash=hash_password(data.password))
    db.add(new_user)
    await db.commit()
    await db.refresh(new_user)
    return schemas.UserResponse(id=new_user.id, username=new_user.username, email=new_user.email, is_active=new_user.is_active)


@router.delete("/users/{user_id}")
async def delete_user(
    user_id: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    if user.id == user_id:
        raise HTTPException(status_code=400, detail="Cannot delete yourself")
    target = await db.get(User, user_id)
    if not target:
        raise HTTPException(status_code=404, detail="User not found")
    await db.delete(target)
    await db.commit()
    return {"status": "deleted"}
