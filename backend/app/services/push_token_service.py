from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.device_token import DevicePushToken


class PushTokenService:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def register(self, user_id: str, token: str, platform: str = "android") -> DevicePushToken:
        result = await self.db.execute(
            select(DevicePushToken).where(DevicePushToken.token == token)
        )
        existing = result.scalar_one_or_none()
        if existing:
            existing.user_id = user_id
            existing.platform = platform
            existing.is_active = True
            await self.db.commit()
            await self.db.refresh(existing)
            return existing

        record = DevicePushToken(user_id=user_id, token=token, platform=platform)
        self.db.add(record)
        await self.db.commit()
        await self.db.refresh(record)
        return record

    async def list_tokens_for_user(self, user_id: str) -> list[str]:
        result = await self.db.execute(
            select(DevicePushToken.token).where(
                DevicePushToken.user_id == user_id,
                DevicePushToken.is_active == True,
            )
        )
        return [row[0] for row in result.all()]

    async def list_all_active_tokens(self) -> list[str]:
        result = await self.db.execute(
            select(DevicePushToken.token).where(DevicePushToken.is_active == True)
        )
        return [row[0] for row in result.all()]

    async def deactivate(self, token: str) -> None:
        await self.db.execute(
            update(DevicePushToken).where(DevicePushToken.token == token).values(is_active=False)
        )
        await self.db.commit()
