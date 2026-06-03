"""Verify business API routes require Bearer token."""

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)

PROTECTED = [
    ("GET", "/api/v1/space/locations"),
    ("GET", "/api/v1/items/history/slot-1"),
    ("POST", "/api/v1/search/hybrid"),
    ("GET", "/api/v1/reminders/pending"),
    ("GET", "/api/v1/families"),
]

PUBLIC = [
    ("GET", "/health"),
    ("POST", "/api/v1/auth/login"),
]


def test_protected_routes_reject_unauthenticated():
    for method, path in PROTECTED:
        response = client.request(method, path, json={} if method == "POST" else None)
        assert response.status_code in (401, 403), f"{method} {path} -> {response.status_code}"


def test_public_routes_accessible_without_token():
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json() == {"status": "ok"}

    r = client.post("/api/v1/auth/login", json={})
    assert r.status_code == 422  # validation error, not 401
