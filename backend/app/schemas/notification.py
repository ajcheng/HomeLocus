from pydantic import BaseModel, Field


class RegisterDeviceTokenRequest(BaseModel):
    token: str = Field(..., min_length=10, max_length=512)
    platform: str = Field(default="android", max_length=20)


class RegisterDeviceTokenResponse(BaseModel):
    status: str = "ok"
    token_id: str
