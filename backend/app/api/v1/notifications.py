from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import get_current_user
from app.models.user import User
from app.schemas import notification as schemas
from app.services.push_token_service import PushTokenService

router = APIRouter()


def get_push_token_service(db: AsyncSession = Depends(get_db)) -> PushTokenService:
    return PushTokenService(db)


@router.post("/device-token", response_model=schemas.RegisterDeviceTokenResponse)
async def register_device_token(
    data: schemas.RegisterDeviceTokenRequest,
    user: User = Depends(get_current_user),
    svc: PushTokenService = Depends(get_push_token_service),
):
    """Register or refresh FCM device token for the current user."""
    record = await svc.register(user.id, data.token, data.platform)
    return schemas.RegisterDeviceTokenResponse(token_id=record.id)
