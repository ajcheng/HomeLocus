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

# Frontend (联网版) — dev
cd frontend && flutter run -d chrome
# Frontend (联网版) — production build with real domain
bash build_local.sh web   # uses --dart-define to inject domain
bash build_local.sh apk   # Android APK

# app_local (纯本地版)
cd app_local && bash build_local.sh   # also uses --dart-define

# Full Docker deploy
docker compose -f docker/docker-compose.yml up -d
docker compose -f docker/docker-compose.yml exec backend alembic upgrade head
```

## Architecture

### 两个 Flutter 项目
| 项目 | 目录 | 数据后端 | 登录 | 识别方式 |
|------|------|---------|------|---------|
| 联网版 | `frontend/` | PostgreSQL (服务端) | JWT | Celery + AI API |
| 本地版 | `app_local/` | SQLite (手机本地) | 无 | 直连网关 + 大模型 |

**Backend:** FastAPI (Python 3.12) — 13 route modules under `app/api/v1/`, each with matching `service_*.py` and `schema_*.py`. The API router prefixes everything with `/api/v1`. Auth is JWT (HS256, 7d expiry) via `app/core/security.py:get_current_user` — `/auth/register` and `/auth/login` are public; all other endpoints require auth via `require_auth` dependency.

**Four-level spatial topology:** `Location → Zone → Container → Slot`. Location optionally links to `Family` (multi-member sharing). Items live in Slots.

**Recognition providers (configurable):** `qwen` (千问租户 API), `yolo` (本地 YOLO11), `vision` (OpenAI-compatible Vision), `auto` (fallback chain).

**Hybrid search:** Meilisearch (text) + Qdrant (vector) + RRF fusion + search synonyms (`backend/app/utils/search_synonyms.py` — bidirectional expansion, e.g. "保暖穿的" ↔ "羽绒服").

**Three lightweight gateway services** under `services/`:
- `media-gateway` (Flask) — image upload → public URL for vision model
- `asr-gateway` (FastAPI) — audio → text via Qwen3-ASR
- `yolo-vision` (Flask) — OpenVINO + YOLO11 local detection

**Celery tasks:** `process_upload` (recognition.py) — image storage → compression → OCR → Vision API → thumbnails. `check_pending_reminders` (scheduler.py) — every 10 min, scans for due reminders.

**Config:** `BaseSettings` in `app/core/config.py`, loaded from `.env`. Docker compose uses `${VAR:-default}` syntax.

**Domain injection:** Production domain (`ajcheng.com`) is never in source code. Flutter uses `--dart-define` via `build_local.sh` (gitignored). Backend uses `.env` (gitignored). Tracking-safe defaults are always `localhost` or `example.com`.

## Key Patterns

- **ID generation:** Prefixed UUIDs truncated to 8 chars (`loc_xxx`, `item_xxx`, `fam_xxx`, etc.)
- **Async DB:** All routes use `AsyncSession` via `Depends(get_db)`. Services accept `db: AsyncSession` in `__init__`. Lazy-loading relationships must use `selectinload()`.
- **Storage backend:** `StorageService` (strategy pattern) — `LocalStorage`, `S3Storage`. Set `STORAGE_BACKEND=local` for filesystem, `minio`/`s3` for object storage.
- **AI Vision:** Uses Anthropic-compatible Messages API at `{AI_BASE_URL}/anthropic/v1/messages` with `x-api-key` header. Image is resized to max 1024px before base64 encoding.
- **Qdrant ID mapping:** Uses MD5→UUID for string IDs (Qdrant only accepts UUID/uint64).
- **Deployment:** SCP images through SSH jump host `sx` → target `nginx`. `deploy/deploy.sh` automates the full flow.
- **Recognition pipeline:** Celery writes AI results to `ImageSnapshot` only — items await user confirmation before committing to DB.

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

## Testing

```bash
cd backend && pytest     # tests/ directory
```
