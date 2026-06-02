from datetime import datetime
from typing import Optional

from pydantic import BaseModel


class AuditLogResponse(BaseModel):
    id: str
    user_id: str
    username: str
    action: str
    entity_type: str
    entity_id: Optional[str] = None
    description: Optional[str] = None
    changes: Optional[dict] = None
    created_at: datetime

    model_config = {"from_attributes": True}
