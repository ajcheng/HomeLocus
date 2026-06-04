from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.schemas import space as schemas
from app.services.space_service import SpaceService

router = APIRouter()


def get_space_service(db: AsyncSession = Depends(get_db)) -> SpaceService:
    return SpaceService(db)


# ---- Location ----
@router.post("/locations", response_model=schemas.LocationResponse)
async def create_location(data: schemas.LocationCreate, svc: SpaceService = Depends(get_space_service)):
    location = await svc.create_location(data)
    return schemas.LocationResponse(id=location.id, name=location.name, is_default=location.is_default, created_at=location.created_at, zone_count=0)


@router.get("/locations", response_model=list[schemas.LocationResponse])
async def list_locations(svc: SpaceService = Depends(get_space_service)):
    return await svc.list_locations()


@router.delete("/locations/{location_id}")
async def delete_location(location_id: str, svc: SpaceService = Depends(get_space_service)):
    ok = await svc.delete_location(location_id)
    if not ok:
        raise HTTPException(status_code=404, detail="Location not found")
    return {"status": "deleted"}


@router.post("/locations/{location_id}/apply-template")
async def apply_location_template(location_id: str, svc: SpaceService = Depends(get_space_service)):
    """Apply standard home template (客厅/主卧/…) to an existing location."""
    try:
        count = await svc.apply_home_template(location_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="Location not found")
    return {"status": "ok", "slots_created": count}


# ---- Zone ----
@router.post("/zones", response_model=schemas.ZoneResponse)
async def create_zone(data: schemas.ZoneCreate, svc: SpaceService = Depends(get_space_service)):
    location = await svc.get_location(data.location_id)
    if not location:
        raise HTTPException(status_code=404, detail="Location not found")
    zone = await svc.create_zone(data)
    return schemas.ZoneResponse(id=zone.id, location_id=zone.location_id, name=zone.name, template_type=zone.template_type)


@router.get("/zones", response_model=list[schemas.ZoneResponse])
async def list_zones(location_id: str | None = None, svc: SpaceService = Depends(get_space_service)):
    zones = await svc.list_zones(location_id)
    return [schemas.ZoneResponse(id=z.id, location_id=z.location_id, name=z.name, template_type=z.template_type) for z in zones]


# ---- Container ----
@router.post("/containers", response_model=schemas.ContainerResponse, status_code=201)
async def create_container(data: schemas.ContainerCreate, svc: SpaceService = Depends(get_space_service)):
    container = await svc.create_container(data)
    return _build_container_response(container)


@router.get("/containers", response_model=list[schemas.ContainerResponse])
async def list_containers(zone_id: str | None = None, svc: SpaceService = Depends(get_space_service)):
    containers = await svc.list_containers(zone_id)
    return [_build_container_response(c) for c in containers]


@router.get("/containers/{container_id}", response_model=schemas.ContainerResponse)
async def get_container(container_id: str, svc: SpaceService = Depends(get_space_service)):
    container = await svc.get_container(container_id)
    if not container:
        raise HTTPException(status_code=404, detail="Container not found")
    return _build_container_response(container)


# ---- Slot ----
@router.post("/containers/{container_id}/slots", response_model=list[schemas.SlotResponse], status_code=201)
async def create_slots(container_id: str, data: list[schemas.SlotCreate], svc: SpaceService = Depends(get_space_service)):
    container = await svc.get_container(container_id)
    if not container:
        raise HTTPException(status_code=404, detail="Container not found")
    slots = await svc.create_slots(container_id, data)
    return [schemas.SlotResponse(id=s.id, container_id=s.container_id, name=s.name, level=s.level) for s in slots]


@router.put("/slots/{slot_id}", response_model=schemas.SlotResponse)
async def update_slot(slot_id: str, data: schemas.SlotUpdate, svc: SpaceService = Depends(get_space_service)):
    slot = await svc.update_slot(slot_id, data)
    if not slot:
        raise HTTPException(status_code=404, detail="Slot not found")
    return schemas.SlotResponse(id=slot.id, container_id=slot.container_id, name=slot.name, level=slot.level)


@router.get("/zones/{zone_id}/path", response_model=schemas.ZonePathResponse)
async def get_zone_path(zone_id: str, svc: SpaceService = Depends(get_space_service)):
    path = await svc.get_zone_path(zone_id)
    if not path:
        raise HTTPException(status_code=404, detail="Zone not found")
    return path


@router.get("/slots/{slot_id}/path", response_model=schemas.SlotPathResponse)
async def get_slot_path(slot_id: str, svc: SpaceService = Depends(get_space_service)):
    path = await svc.get_slot_path(slot_id)
    if not path:
        raise HTTPException(status_code=404, detail="Slot not found")
    return path


@router.delete("/slots/{slot_id}")
async def delete_slot(slot_id: str, svc: SpaceService = Depends(get_space_service)):
    deleted = await svc.delete_slot(slot_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Slot not found")
    return {"status": "deleted"}


def _build_container_response(container) -> schemas.ContainerResponse:
    return schemas.ContainerResponse(
        id=container.id,
        zone_id=container.zone_id,
        name=container.name,
        slots=[
            schemas.SlotResponse(id=s.id, container_id=s.container_id, name=s.name, level=s.level)
            for s in (container.slots or [])
        ],
    )
