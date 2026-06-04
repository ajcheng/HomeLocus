import uuid
from datetime import datetime
from typing import Optional

from sqlalchemy import String, DateTime, ForeignKey, Integer, Boolean, Text, Float, func
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class Item(Base):
    __tablename__ = "items"

    id: Mapped[str] = mapped_column(String(50), primary_key=True, default=lambda: f"item_{uuid.uuid4().hex[:8]}")
    slot_id: Mapped[str] = mapped_column(String(50), ForeignKey("slots.id"), nullable=False)
    label: Mapped[str] = mapped_column(String(200), nullable=False)
    brand: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)
    category: Mapped[Optional[str]] = mapped_column(String(50), nullable=True)
    tags: Mapped[Optional[list]] = mapped_column(JSONB, default=list)

    # Bounding box in source image
    bounding_box: Mapped[Optional[dict]] = mapped_column(JSONB, nullable=True)
    # Path to cropped thumbnail
    thumbnail_path: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)

    # Lifecycle flags
    is_chargeable: Mapped[bool] = mapped_column(Boolean, default=False)
    charge_cycle_days: Mapped[Optional[int]] = mapped_column(Integer, default=90)
    is_borrowed: Mapped[bool] = mapped_column(Boolean, default=False)
    borrower: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)

    # AI recognition metadata
    confidence: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    ai_label_raw: Mapped[Optional[str]] = mapped_column(String(200), nullable=True)

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    slot: Mapped["Slot"] = relationship(back_populates="items")
    snapshots: Mapped[list["ImageSnapshot"]] = relationship(back_populates="item", cascade="all, delete-orphan")
    reminders: Mapped[list["Reminder"]] = relationship(back_populates="item", cascade="all, delete-orphan")


class ImageSnapshot(Base):
    __tablename__ = "image_snapshots"

    id: Mapped[str] = mapped_column(String(50), primary_key=True, default=lambda: f"snap_{uuid.uuid4().hex[:8]}")
    item_id: Mapped[str] = mapped_column(String(50), ForeignKey("items.id"), nullable=True)
    slot_id: Mapped[str] = mapped_column(String(50), ForeignKey("slots.id"), nullable=False)
    original_path: Mapped[str] = mapped_column(String(500), nullable=False)
    compressed_path: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)
    ocr_text: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    ai_response_raw: Mapped[Optional[dict]] = mapped_column(JSONB, nullable=True)
    is_current: Mapped[bool] = mapped_column(Boolean, default=True)
    task_id: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    item: Mapped[Optional["Item"]] = relationship(back_populates="snapshots")
