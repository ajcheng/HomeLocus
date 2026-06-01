# HomeLocus 家庭物品存放管理系统

> 空间拓扑数字化 + AI 多模态识别 + 混合智能检索 + 语音输入

## 解决什么？

找不到东西、忘记放哪了、设备忘充电 — 通过拍照识别 + 语音录入 + 空间地图，精准管理家中每件物品。

## 技术栈

| 层 | 选型 |
|---|---|
| 后端 | Python 3.12 + FastAPI |
| 前端 | Flutter (Android/iOS/Web) |
| 数据库 | PostgreSQL 16 |
| 搜索引擎 | Meilisearch |
| 向量库 | Qdrant |
| 对象存储 | MinIO (S3 兼容) |
| 异步任务 | Celery + Redis |
| AI | DeepSeek-V4 Vision + PaddleOCR |

## 快速启动

```bash
# 1. 启动依赖服务
docker compose -f docker/docker-compose.yml up -d

# 2. 安装后端依赖
cd backend && python3.12 -m venv .venv
source .venv/bin/activate && pip install -r requirements.txt

# 3. 数据库迁移
cp .env.example .env
alembic upgrade head

# 4. 启动后端
uvicorn app.main:app --reload --port 8000

# 5. 启动前端
cd ../frontend && flutter run
```

## 核心 API

| 模块 | 端点 | 说明 |
|---|---|---|
| 空间管理 | `/api/v1/space/*` | 地点→分区→储物模块→层级 CRUD |
| 物品管理 | `/api/v1/items/*` | 拍照上传 + AI 识别 + 历史快照 |
| 语音输入 | `/api/v1/speech/*` | 语音→NLP解析→空间匹配→入库 |
| 混合检索 | `/api/v1/search/hybrid` | 文本+语义+以图搜图 |
| 定时提醒 | `/api/v1/reminders/*` | 充电提醒 + 借出归位提醒 |

## 项目结构

```
HomeLocus/
├── backend/           # FastAPI 后端
├── frontend/          # Flutter 前端
├── docker/            # Docker Compose
└── docs/              # 文档
```

## License

MIT
