import uuid
import secrets
from datetime import datetime, timedelta, timezone
from typing import Optional

from sqlalchemy import String, DateTime, ForeignKey, Boolean, Text, func, Integer
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class Family(Base):
    __tablename__ = "families"

    id: Mapped[str] = mapped_column(String(50), primary_key=True, default=lambda: f"fam_{uuid.uuid4().hex[:8]}")
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    created_by: Mapped[str] = mapped_column(String(50), ForeignKey("users.id"), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    members: Mapped[list["FamilyMember"]] = relationship(back_populates="family", cascade="all, delete-orphan")
    invitations: Mapped[list["Invitation"]] = relationship(back_populates="family", cascade="all, delete-orphan")


class FamilyMember(Base):
    __tablename__ = "family_members"

    id: Mapped[str] = mapped_column(String(50), primary_key=True, default=lambda: f"fmb_{uuid.uuid4().hex[:8]}")
    family_id: Mapped[str] = mapped_column(String(50), ForeignKey("families.id"), nullable=False)
    user_id: Mapped[str] = mapped_column(String(50), ForeignKey("users.id"), nullable=False)
    role: Mapped[str] = mapped_column(String(20), default="member")  # "admin" or "member"
    joined_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    family: Mapped["Family"] = relationship(back_populates="members")


class Invitation(Base):
    __tablename__ = "invitations"

    id: Mapped[str] = mapped_column(String(50), primary_key=True, default=lambda: f"inv_{uuid.uuid4().hex[:8]}")
    family_id: Mapped[str] = mapped_column(String(50), ForeignKey("families.id"), nullable=False)
    code: Mapped[str] = mapped_column(String(10), unique=True, default=lambda: secrets.token_urlsafe(8)[:8])
    created_by: Mapped[str] = mapped_column(String(50), ForeignKey("users.id"), nullable=False)
    expires_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc) + timedelta(days=7),
    )
    max_uses: Mapped[int] = mapped_column(Integer, default=10)
    use_count: Mapped[int] = mapped_column(Integer, default=0)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    family: Mapped["Family"] = relationship(back_populates="invitations")
