# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
# Backend (dev)
docker compose -f docker/docker-compose.yml up -d postgres redis meilisearch qdrant
cd backend && source .venv/bin/activate
cp .env.example .env   # set AI_API_KEY, JWT_SECRET
alembic upgrade head
uvicorn app.main:app --host 0.0.0.0 --port 8000

# Celery (separate terminals)
celery -A app.tasks.celery_app worker --loglevel=info --concurrency=2
celery -A app.tasks.celery_app beat --loglevel=info

# Full Docker deploy
docker compose -f docker/docker-compose.yml up -d
docker compose -f docker/docker-compose.yml exec backend alembic upgrade head

# Frontend
cd frontend && flutter build web
cd frontend && flutter build apk --release --target-platform android-arm64
```

## Architecture

**Backend:** FastAPI (Python 3.12) — 13 route modules under `app/api/v1/`, each with matching `service_*.py` and `schema_*.py` in `app/services/` and `app/schemas/`. The API router prefixes everything with `/api/v1`. Auth is JWT (HS256, 7d expiry) via `app/core/security.py:get_current_user` — all business endpoints require it except `/auth/register` and `/auth/login`.

**Four-level spatial topology:** `Location → Zone → Container → Slot`. Location optionally links to `Family` (multi-member sharing). Items live in Slots. Seeds create a default "Demo" location.

**Config:** `BaseSettings` in `app/core/config.py`, loaded from `.env`. Key env vars: `STORAGE_BACKEND` (local/minio/s3), `AI_PROVIDER` (deepseek/openai/custom), `AI_API_KEY`, `AI_VISION_MODEL`, `JWT_SECRET`. Docker compose env vars use `${VAR:-default}` syntax.

**Frontend:** Flutter with 13 screens under `frontend/lib/screens/`. `ApiClient` is a singleton-pattern HTTP client — set `ApiClient.authToken` (static field) after login, all subsequent requests auto-attach `Authorization: Bearer`. Token is persisted in SharedPreferences. `baseUrl` defaults to `https://home.ajcheng.com:8443/api/v1`.

**Docker services:** postgres:16-alpine, redis:7-alpine, meilisearch:v1.13, qdrant/qdrant:latest, plus 3 custom images (backend, celery-worker, celery-beat). Production compose (`docker-compose.prod.yml`) keeps all ports internal — only backend binds 127.0.0.1:8000 for nginx reverse proxy.

**Celery tasks:** `process_upload` (recognition.py) — image storage → compression → OCR → Vision API → thumbnails. `check_pending_reminders` (scheduler.py) — runs every 10 min, scans for due reminders.

## Key Patterns

- **ID generation:** Prefixed UUIDs truncated to 8 chars (`loc_xxx`, `item_xxx`, `fam_xxx`, etc.)
- **Async DB:** All routes use `AsyncSession` via `Depends(get_db)`. Services accept `db: AsyncSession` in `__init__`. Lazy-loading relationships must use `selectinload()`.
- **Storage backend:** `StorageService` (strategy pattern) — `LocalStorage`, `S3Storage`. Set `STORAGE_BACKEND=local` for filesystem, `minio`/`s3` for object storage.
- **AI Vision:** Uses Anthropic-compatible Messages API at `{AI_BASE_URL}/anthropic/v1/messages` with `x-api-key` header. Image is resized to max 1024px before base64 encoding.
- **Search:** Meilisearch (text) + Qdrant (vector) with RRF fusion. Qdrant uses MD5→UUID for string IDs (Qdrant only accepts UUID/uint64).
- **Deployment:** SCP images through SSH jump host `sx` → target `nginx`. `deploy/deploy.sh` automates the full flow.

## Database Models (13 tables)

| Model | Table | Notes |
|-------|-------|-------|
| User | `users` | JWT auth, bcrypt passwords |
| Location | `locations` | Top-level, can link to Family |
| Zone | `zones` | Belongs to Location |
| Container | `containers` | Belongs to Zone |
| Slot | `slots` | Belongs to Container, holds Items |
| Item | `items` | label, tags (JSONB), bounding_box, chargeable |
| ImageSnapshot | `image_snapshots` | Version history for slot photos |
| Reminder | `reminders` | charge or borrow type, next_remind_at |
| Family | `families` | Multi-member sharing |
| FamilyMember | `family_members` | role: admin/member |
| Invitation | `invitations` | 8-char codes, 7-day expiry |
| FloorPlan | `floor_plans` | Imported images with polygon anchors |
| PlanAnchor | `plan_anchors` | Polygon points (JSONB) mapping to Zone |
| AuditLog | `audit_logs` | All operations logged |
| DevicePushToken | `device_push_tokens` | FCM push notification tokens |

## Migrations

```bash
cd backend && alembic revision --autogenerate -m "description"
alembic upgrade head
```

In Docker: `docker compose exec backend alembic upgrade head`

When deploying to production, set `DATABASE_URL_SYNC` to use the Docker service hostname (`postgres`, not `localhost`). The alembic `env.py` uses the synchronous URL from config.
