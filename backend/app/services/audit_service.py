from sqlalchemy import select, desc
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.audit_log import AuditLog


class AuditService:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def log(
        self,
        user_id: str,
        username: str,
        action: str,
        entity_type: str,
        entity_id: str | None = None,
        description: str | None = None,
        changes: dict | None = None,
        family_id: str | None = None,
    ):
        entry = AuditLog(
            user_id=user_id,
            username=username,
            family_id=family_id,
            action=action,
            entity_type=entity_type,
            entity_id=entity_id,
            description=description,
            changes=changes,
        )
        self.db.add(entry)
        await self.db.commit()

    async def get_logs(
        self,
        family_id: str | None = None,
        user_id: str | None = None,
        action: str | None = None,
        entity_id: str | None = None,
        limit: int = 50,
        offset: int = 0,
    ) -> list[AuditLog]:
        stmt = select(AuditLog).order_by(desc(AuditLog.created_at))

        if family_id:
            stmt = stmt.where(AuditLog.family_id == family_id)
        if user_id:
            stmt = stmt.where(AuditLog.user_id == user_id)
        if action:
            stmt = stmt.where(AuditLog.action == action)
        if entity_id:
            stmt = stmt.where(AuditLog.entity_id == entity_id)

        stmt = stmt.limit(min(limit, 200)).offset(offset)
        result = await self.db.execute(stmt)
        return list(result.scalars().all())
