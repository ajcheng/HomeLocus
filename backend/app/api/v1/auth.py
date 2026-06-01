from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.schemas import auth as schemas
from app.services.auth_service import AuthService

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
        user=schemas.UserResponse(
            id=payload.get("sub", ""),
            username=payload.get("username", ""),
            email="",
            is_active=True,
        ),
    )
