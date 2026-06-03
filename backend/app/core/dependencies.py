"""Shared FastAPI dependencies."""

from fastapi import Depends

from app.core.security import get_current_user

# Apply to all business API routers (exclude /auth register & login).
require_auth = [Depends(get_current_user)]
