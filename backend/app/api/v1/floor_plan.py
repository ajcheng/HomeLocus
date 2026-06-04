import uuid
import os
from typing import Optional

from fastapi import APIRouter, Depends, UploadFile, File, Form, HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.database import get_db
from app.core.security import get_current_user
from app.models.user import User
from app.models.floor_plan import FloorPlan, PlanAnchor
from app.services.storage_service import storage_service

router = APIRouter()


class AnchorCreate(BaseModel):
    zone_id: Optional[str] = None
    polygon_points: list[dict]  # [{x, y}, ...] as percentages
    label: Optional[str] = None
    color: str = "#4A90D9"


class AnchorUpdate(BaseModel):
    zone_id: Optional[str] = None
    polygon_points: Optional[list[dict]] = None
    label: Optional[str] = None
    color: Optional[str] = None


class AnchorResponse(BaseModel):
    id: str
    zone_id: Optional[str] = None
    polygon_points: list[dict]
    label: Optional[str] = None
    color: str

    model_config = {"from_attributes": True}


class FloorPlanResponse(BaseModel):
    id: str
    location_id: str
    image_url: str
    real_width_mm: Optional[float] = None
    real_height_mm: Optional[float] = None
    anchors: list[AnchorResponse] = []

    model_config = {"from_attributes": True}


@router.post("/{location_id}/upload", response_model=FloorPlanResponse)
async def upload_floor_plan(
    location_id: str,
    file: UploadFile = File(...),
    real_width_mm: Optional[float] = Form(None),
    real_height_mm: Optional[float] = Form(None),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    # Save and upload
    ext = os.path.splitext(file.filename or "plan.jpg")[1] or ".jpg"
    obj_name = f"floor_plans/{location_id}/{uuid.uuid4().hex}{ext}"
    content = await file.read()
    storage_service.upload_bytes(content, obj_name)

    fp = FloorPlan(
        location_id=location_id,
        image_path=obj_name,
        real_width_mm=real_width_mm,
        real_height_mm=real_height_mm,
    )
    db.add(fp)
    await db.commit()
    await db.refresh(fp)

    return FloorPlanResponse(
        id=fp.id, location_id=fp.location_id,
        image_url=storage_service.get_presigned_url(obj_name),
        real_width_mm=fp.real_width_mm, real_height_mm=fp.real_height_mm,
        anchors=[],
    )


@router.get("/{location_id}", response_model=list[FloorPlanResponse])
async def list_floor_plans(
    location_id: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(FloorPlan)
        .where(FloorPlan.location_id == location_id)
        .options(selectinload(FloorPlan.anchors))
        .order_by(FloorPlan.created_at.desc())
    )
    plans = result.scalars().all()
    return [
        FloorPlanResponse(
            id=p.id, location_id=p.location_id,
            image_url=storage_service.get_presigned_url(p.image_path),
            real_width_mm=p.real_width_mm, real_height_mm=p.real_height_mm,
            anchors=[AnchorResponse(
                id=a.id, zone_id=a.zone_id, polygon_points=a.polygon_points,
                label=a.label, color=a.color,
            ) for a in (p.anchors or [])],
        )
        for p in plans
    ]


@router.post("/{floor_plan_id}/anchors", response_model=AnchorResponse, status_code=201)
async def add_anchor(
    floor_plan_id: str,
    data: AnchorCreate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    fp = await db.get(FloorPlan, floor_plan_id)
    if not fp:
        raise HTTPException(status_code=404, detail="Floor plan not found")

    anchor = PlanAnchor(
        floor_plan_id=floor_plan_id,
        zone_id=data.zone_id,
        polygon_points=data.polygon_points,
        label=data.label,
        color=data.color,
    )
    db.add(anchor)
    await db.commit()
    await db.refresh(anchor)
    return AnchorResponse(
        id=anchor.id, zone_id=anchor.zone_id,
        polygon_points=anchor.polygon_points, label=anchor.label, color=anchor.color,
    )


@router.put("/anchors/{anchor_id}", response_model=AnchorResponse)
async def update_anchor(
    anchor_id: str,
    data: AnchorUpdate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    anchor = await db.get(PlanAnchor, anchor_id)
    if not anchor:
        raise HTTPException(status_code=404, detail="Anchor not found")
    if data.zone_id is not None:
        anchor.zone_id = data.zone_id
    if data.polygon_points is not None:
        anchor.polygon_points = data.polygon_points
    if data.label is not None:
        anchor.label = data.label
    if data.color is not None:
        anchor.color = data.color
    await db.commit()
    await db.refresh(anchor)
    return AnchorResponse(
        id=anchor.id,
        zone_id=anchor.zone_id,
        polygon_points=anchor.polygon_points,
        label=anchor.label,
        color=anchor.color,
    )


@router.delete("/anchors/{anchor_id}")
async def delete_anchor(
    anchor_id: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    anchor = await db.get(PlanAnchor, anchor_id)
    if not anchor:
        raise HTTPException(status_code=404, detail="Anchor not found")
    await db.delete(anchor)
    await db.commit()
    return {"status": "deleted"}


@router.delete("/{floor_plan_id}")
async def delete_floor_plan(
    floor_plan_id: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    fp = await db.get(FloorPlan, floor_plan_id)
    if not fp:
        raise HTTPException(status_code=404, detail="Floor plan not found")
    await db.delete(fp)
    await db.commit()
    return {"status": "deleted"}
