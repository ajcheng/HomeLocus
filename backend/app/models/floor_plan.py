import uuid
from datetime import datetime
from typing import Optional

from sqlalchemy import String, DateTime, ForeignKey, Float, func
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class FloorPlan(Base):
    __tablename__ = "floor_plans"

    id: Mapped[str] = mapped_column(String(50), primary_key=True, default=lambda: f"fp_{uuid.uuid4().hex[:8]}")
    location_id: Mapped[str] = mapped_column(String(50), ForeignKey("locations.id"), nullable=False)
    image_path: Mapped[str] = mapped_column(String(500), nullable=False)
    # Actual dimensions for scaling: (width_mm, height_mm)
    real_width_mm: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    real_height_mm: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    anchors: Mapped[list["PlanAnchor"]] = relationship(back_populates="floor_plan", cascade="all, delete-orphan")


class PlanAnchor(Base):
    """A polygon region on the floor plan that maps to a Zone."""

    __tablename__ = "plan_anchors"

    id: Mapped[str] = mapped_column(String(50), primary_key=True, default=lambda: f"pa_{uuid.uuid4().hex[:8]}")
    floor_plan_id: Mapped[str] = mapped_column(String(50), ForeignKey("floor_plans.id"), nullable=False)
    zone_id: Mapped[Optional[str]] = mapped_column(String(50), ForeignKey("zones.id"), nullable=True)
    # Polygon points as percentage of image (0-100): [{x, y}, {x, y}, ...]
    polygon_points: Mapped[list] = mapped_column(JSONB, default=list)
    label: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)
    color: Mapped[str] = mapped_column(String(10), default="#4A90D9")

    floor_plan: Mapped["FloorPlan"] = relationship(back_populates="anchors")
