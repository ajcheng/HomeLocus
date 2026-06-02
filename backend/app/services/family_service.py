from datetime import datetime, timezone

from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.family import Family, FamilyMember, Invitation
from app.models.user import User
from app.schemas import family as schemas


class FamilyService:
    def __init__(self, db: AsyncSession):
        self.db = db

    # ---- Family CRUD ----
    async def create_family(self, user: User, name: str) -> Family:
        family = Family(name=name, created_by=user.id)
        self.db.add(family)
        await self.db.flush()

        # Creator is admin
        member = FamilyMember(family_id=family.id, user_id=user.id, role="admin")
        self.db.add(member)
        await self.db.commit()
        await self.db.refresh(family)
        return family

    async def list_families(self, user: User) -> list[dict]:
        result = await self.db.execute(
            select(Family, FamilyMember.role)
            .join(FamilyMember, FamilyMember.family_id == Family.id)
            .where(FamilyMember.user_id == user.id)
            .order_by(Family.created_at)
        )
        rows = result.all()
        families = []
        for fam, role in rows:
            count_result = await self.db.execute(
                select(func.count()).select_from(FamilyMember).where(FamilyMember.family_id == fam.id)
            )
            member_count = count_result.scalar() or 0
            families.append(schemas.FamilyResponse(
                id=fam.id, name=fam.name, member_count=member_count,
                role=role, created_at=fam.created_at,
            ))
        return families

    async def get_family(self, family_id: str) -> Family | None:
        result = await self.db.execute(
            select(Family).where(Family.id == family_id).options(selectinload(Family.members))
        )
        return result.scalar_one_or_none()

    async def get_members(self, family_id: str) -> list[FamilyMember]:
        result = await self.db.execute(
            select(FamilyMember, User.username)
            .join(User, FamilyMember.user_id == User.id)
            .where(FamilyMember.family_id == family_id)
            .order_by(FamilyMember.joined_at)
        )
        rows = result.all()
        return [
            schemas.MemberResponse(
                id=member.id, user_id=member.user_id,
                username=username, role=member.role,
                joined_at=member.joined_at,
            )
            for member, username in rows
        ]

    async def update_member_role(self, family_id: str, user_id: str, new_role: str) -> bool:
        result = await self.db.execute(
            select(FamilyMember).where(
                FamilyMember.family_id == family_id,
                FamilyMember.user_id == user_id,
            )
        )
        member = result.scalar_one_or_none()
        if not member:
            return False
        member.role = new_role
        await self.db.commit()
        return True

    async def remove_member(self, family_id: str, user_id: str) -> bool:
        result = await self.db.execute(
            select(FamilyMember).where(
                FamilyMember.family_id == family_id,
                FamilyMember.user_id == user_id,
            )
        )
        member = result.scalar_one_or_none()
        if not member:
            return False
        await self.db.delete(member)
        await self.db.commit()
        return True

    # ---- Invitations ----
    async def create_invitation(self, user: User, family_id: str, max_uses: int = 10) -> Invitation:
        inv = Invitation(family_id=family_id, created_by=user.id, max_uses=max_uses)
        self.db.add(inv)
        await self.db.commit()
        await self.db.refresh(inv)
        return inv

    async def list_invitations(self, family_id: str) -> list[Invitation]:
        result = await self.db.execute(
            select(Invitation)
            .where(Invitation.family_id == family_id, Invitation.is_active == True)
            .order_by(Invitation.created_at.desc())
        )
        return list(result.scalars().all())

    async def join_by_code(self, user: User, code: str) -> Family | None:
        now = datetime.now(timezone.utc)
        result = await self.db.execute(
            select(Invitation).where(
                Invitation.code == code,
                Invitation.is_active == True,
                Invitation.expires_at > now,
            )
        )
        inv = result.scalar_one_or_none()
        if not inv or inv.use_count >= inv.max_uses:
            return None

        # Check not already a member
        existing = await self.db.execute(
            select(FamilyMember).where(
                FamilyMember.family_id == inv.family_id,
                FamilyMember.user_id == user.id,
            )
        )
        if existing.scalar_one_or_none():
            raise ValueError("Already a member of this family")

        member = FamilyMember(family_id=inv.family_id, user_id=user.id, role="member")
        self.db.add(member)
        inv.use_count += 1
        await self.db.commit()
        return await self.get_family(inv.family_id)

    async def check_access(self, user: User, family_id: str) -> str | None:
        """Check if user has access to this family. Returns role or None."""
        result = await self.db.execute(
            select(FamilyMember.role).where(
                FamilyMember.family_id == family_id,
                FamilyMember.user_id == user.id,
            )
        )
        role = result.scalar_one_or_none()
        return role

    async def check_admin(self, user: User, family_id: str) -> bool:
        role = await self.check_access(user, family_id)
        return role == "admin"
