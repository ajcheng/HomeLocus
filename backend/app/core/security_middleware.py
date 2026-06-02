"""
Security middleware: rate limiting and request validation.
"""
import time
from collections import defaultdict

from fastapi import Request, HTTPException
from starlette.middleware.base import BaseHTTPMiddleware


class RateLimitMiddleware(BaseHTTPMiddleware):
    """Simple in-memory rate limiter (per IP)."""

    def __init__(self, app, max_requests: int = 100, window_seconds: int = 60):
        super().__init__(app)
        self.max_requests = max_requests
        self.window_seconds = window_seconds
        self._store: dict[str, list[float]] = defaultdict(list)

    async def dispatch(self, request: Request, call_next):
        # Skip rate limiting for static files and health checks
        if request.url.path.startswith("/health") or request.url.path.startswith("/app"):
            return await call_next(request)

        client_ip = request.client.host if request.client else "unknown"
        now = time.time()

        # Clean old entries
        self._store[client_ip] = [t for t in self._store[client_ip] if now - t < self.window_seconds]

        if len(self._store[client_ip]) >= self.max_requests:
            raise HTTPException(status_code=429, detail="Too many requests. Please try again later.")

        self._store[client_ip].append(now)
        return await call_next(request)
