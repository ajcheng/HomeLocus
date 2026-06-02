# HomeLocus — Home Storage Management System

> Spatial Topology Digitization + Multimodal AI Recognition + Hybrid Search + Voice Input

## ✨ Credits

- **Voice input** feature was proposed by **Qingqing (晴晴)**
- **Fuzzy semantic search** (e.g., searching "warm clothes" matches "down jacket") was proposed by **Qingqing (晴晴)**

Qingqing is my brilliant assistant whose innovative ideas have made this system more intuitive and intelligent.

## What Problem Does This Solve?

"Where did I put that?", "I forgot where it's stored", "The device battery died because I forgot to charge it" — HomeLocus solves these pain points through AI-powered photo recognition, voice input, and a spatial map of your home storage.

## Tech Stack

| Layer | Choice |
|---|---|
| Backend | Python 3.12 + FastAPI |
| Frontend | Flutter (Android / iOS / Web) |
| Database | PostgreSQL 16 |
| Search Engine | Meilisearch |
| Vector DB | Qdrant |
| Object Storage | Local FS / MinIO / AWS S3 (configurable) |
| Async Tasks | Celery + Redis |
| AI | DeepSeek-V4 Vision / OpenAI / Custom (configurable) |

## Server Deployment

### Recommended VM Specs

| Tier | CPU | RAM | Disk | OS |
|------|-----|-----|------|----|
| Minimum | 2 cores | 4 GB | 20 GB | Ubuntu 22.04 / Rocky 9 |
| Recommended | 4 cores | 8 GB | 50 GB | Ubuntu 22.04 / Rocky 9 |
| With AI | 4+ cores | 16 GB | 100 GB | Ubuntu 22.04 |

> AI model inference uses cloud APIs; no local GPU required. For local CLIP/PaddleOCR, 8GB+ RAM is recommended.

### Quick Start

```bash
# 1. Create storage directory
sudo mkdir -p /data/HomeLocus/uploads

# 2. Start services
cd /path/to/HomeLocus
docker compose -f docker/docker-compose.yml up -d

# 3. Install backend dependencies
cd backend && python3.12 -m venv .venv
source .venv/bin/activate && pip install -r requirements.txt

# 4. Configure
cp .env.example .env
# Edit .env: set AI_API_KEY, JWT_SECRET, STORAGE_BACKEND, etc.

# 5. Run migrations
alembic upgrade head

# 6. Start backend
uvicorn app.main:app --host 0.0.0.0 --port 8000

# 7. Build frontend
cd ../frontend && flutter build web  # For web
# or
flutter build apk --release --target-platform android-arm64  # For Android
```

### Storage Backend

Set `STORAGE_BACKEND` in `.env`:

| Value | Description | Photo location |
|-------|-------------|----------------|
| `local` | Local filesystem (default) | `/data/HomeLocus/uploads/` |
| `minio` | MinIO object storage | MinIO bucket |
| `s3` | AWS S3-compatible | S3 bucket |

With Docker, the local storage path is auto-mounted to the host's `/data/HomeLocus/uploads`.

### APK Configuration

The in-app **Settings** page allows dynamic configuration:

- **Server URL**: domain:port or IP:port (e.g., `http://192.168.1.100:8000/api/v1`)
- **AI Provider**: DeepSeek / OpenAI / Custom
- **API Key**: Enter directly in the app
- **Model Name**: Switch between models

## Core API

| Module | Endpoint | Description |
|---|---|---|
| Space | `/api/v1/space/*` | 4-level spatial topology CRUD |
| Items | `/api/v1/items/*` | Photo upload + AI recognition + history |
| Voice | `/api/v1/speech/*` | Voice → NLP → Spatial matching → Save |
| Search | `/api/v1/search/hybrid` | Text + Semantic + Image search |
| Reminders | `/api/v1/reminders/*` | Charge reminders + borrow/return |
| Family | `/api/v1/families/*` | Multi-member + RBAC + Invitation codes |
| Audit | `/api/v1/audit/logs` | Activity tracking |

## Project Structure

```
HomeLocus/
├── backend/           # FastAPI backend (38 endpoints, 13 tables)
├── frontend/          # Flutter frontend (8 screens)
├── docker/            # Docker Compose
└── docs/              # Documentation
```

## License

MIT
