import uuid
from datetime import datetime
from typing import Optional

from sqlalchemy import String, DateTime, ForeignKey, Integer, Boolean, Text, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class Location(Base):
    __tablename__ = "locations"

    id: Mapped[str] = mapped_column(String(50), primary_key=True, default=lambda: f"loc_{uuid.uuid4().hex[:8]}")
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    is_default: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    zones: Mapped[list["Zone"]] = relationship(back_populates="location", cascade="all, delete-orphan")


class Zone(Base):
    __tablename__ = "zones"

    id: Mapped[str] = mapped_column(String(50), primary_key=True, default=lambda: f"zone_{uuid.uuid4().hex[:8]}")
    location_id: Mapped[str] = mapped_column(String(50), ForeignKey("locations.id"), nullable=False)
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    template_type: Mapped[Optional[str]] = mapped_column(String(50), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    location: Mapped["Location"] = relationship(back_populates="zones")
    containers: Mapped[list["Container"]] = relationship(back_populates="zone", cascade="all, delete-orphan")


class Container(Base):
    __tablename__ = "containers"

    id: Mapped[str] = mapped_column(String(50), primary_key=True, default=lambda: f"ctr_{uuid.uuid4().hex[:8]}")
    zone_id: Mapped[str] = mapped_column(String(50), ForeignKey("zones.id"), nullable=False)
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    zone: Mapped["Zone"] = relationship(back_populates="containers")
    slots: Mapped[list["Slot"]] = relationship(back_populates="container", cascade="all, delete-orphan")


class Slot(Base):
    __tablename__ = "slots"

    id: Mapped[str] = mapped_column(String(50), primary_key=True, default=lambda: f"slot_{uuid.uuid4().hex[:8]}")
    container_id: Mapped[str] = mapped_column(String(50), ForeignKey("containers.id"), nullable=False)
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    level: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    container: Mapped["Container"] = relationship(back_populates="slots")
    items: Mapped[list["Item"]] = relationship(back_populates="slot", cascade="all, delete-orphan")
