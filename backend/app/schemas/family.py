from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field


class FamilyCreate(BaseModel):
    name: str = Field(..., max_length=100)


class FamilyResponse(BaseModel):
    id: str
    name: str
    member_count: int = 0
    role: str = "member"
    created_at: datetime
    location_id: Optional[str] = None
    zone_count: int = 0

    model_config = {"from_attributes": True}


class MemberResponse(BaseModel):
    id: str
    user_id: str
    username: str
    role: str
    joined_at: datetime


class InvitationCreate(BaseModel):
    max_uses: int = Field(default=10, ge=1, le=100)


class InvitationResponse(BaseModel):
    id: str
    code: str
    expires_at: datetime
    max_uses: int
    use_count: int
    is_active: bool


class JoinFamilyRequest(BaseModel):
    invitation_code: str
