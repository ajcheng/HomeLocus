# HomeLocus — 家庭物品存放管理系统

> 空间拓扑数字化 + AI 多模态识别 + 混合智能检索 + 语音输入

## ✨ 致谢

- **语音输入功能**由 **晴晴** 提出并推动实现
- **模糊语义搜索**（如输入"保暖穿的"自动匹配"羽绒服"）由 **晴晴** 提出

晴晴是我的得力助手，这些创新的交互方式让系统变得更加易用和智能。

## 解决什么问题？

找不到东西、忘记放哪了、设备忘充电 —— 通过拍照识别 + 语音录入 + 空间地图，精准管理家中每件物品。

## 技术栈

| 层 | 选型 |
|---|---|
| 后端 | Python 3.12 + FastAPI |
| 前端 | Flutter (Android/iOS/Web) |
| 数据库 | PostgreSQL 16 |
| 搜索引擎 | Meilisearch |
| 向量库 | Qdrant |
| 对象存储 | 本地文件 / MinIO / AWS S3（可选配置） |
| 异步任务 | Celery + Redis |
| AI | DeepSeek-V4 Vision / OpenAI / 自定义（可选配置） |

## 服务端部署

### 推荐虚拟机配置

| 环境 | CPU | 内存 | 磁盘 | 系统 |
|------|-----|------|------|------|
| 最小 | 2 核 | 4 GB | 20 GB | Ubuntu 22.04 / Rocky 9 |
| 推荐 | 4 核 | 8 GB | 50 GB | Ubuntu 22.04 / Rocky 9 |
| 含 AI | 4 核+ | 16 GB | 100 GB | Ubuntu 22.04 |

> AI 模型调用走云端 API，不需要本地 GPU。如需本地运行 CLIP/PaddleOCR，建议 8GB+ 内存。

### 快速启动

```bash
# 1. 创建存储目录
sudo mkdir -p /data/HomeLocus/uploads

# 2. 启动依赖服务
cd /path/to/HomeLocus
docker compose -f docker/docker-compose.yml up -d

# 3. 安装后端依赖
cd backend && python3.12 -m venv .venv
source .venv/bin/activate && pip install -r requirements.txt

# 4. 配置环境变量
cp .env.example .env
# 编辑 .env: 设置 AI_API_KEY、JWT_SECRET、STORAGE_BACKEND 等

# 5. 数据库迁移
alembic upgrade head

# 6. 启动后端
uvicorn app.main:app --host 0.0.0.0 --port 8000

# 7. 构建前端
cd ../frontend && flutter build web  # Web 版
# 或
flutter build apk --release --target-platform android-arm64  # Android APK
```

### 存储后端配置

在 `.env` 中设置 `STORAGE_BACKEND`：

| 值 | 说明 | 照片存储位置 |
|----|------|-------------|
| `local` | 本地文件系统（默认） | `/data/HomeLocus/uploads/` |
| `minio` | MinIO 对象存储 | MinIO bucket |
| `s3` | AWS S3 兼容存储 | S3 bucket |

Docker 部署时，本地存储目录自动映射到宿主机 `/data/HomeLocus/uploads`。

### APK 端配置

App 内 **设置页面** 支持动态配置：

- **服务器地址**：域名:端口 或 IP:端口（如 `http://192.168.1.100:8000/api/v1`）
- **AI 提供商**：DeepSeek / OpenAI / 自定义
- **API Key**：在 App 内直接输入
- **模型名称**：可切换不同模型

## 核心 API

| 模块 | 端点 | 说明 |
|---|---|---|
| 空间管理 | `/api/v1/space/*` | 四级空间拓扑 CRUD |
| 物品管理 | `/api/v1/items/*` | 拍照上传 + AI 识别 + 历史快照 |
| 语音输入 | `/api/v1/speech/*` | 语音→NLP解析→空间匹配→入库 |
| 混合检索 | `/api/v1/search/hybrid` | 文本+语义+以图搜图 |
| 定时提醒 | `/api/v1/reminders/*` | 充电提醒 + 借出归位 |
| 家庭管理 | `/api/v1/families/*` | 多成员协作 + RBAC + 邀请码 |
| 审计日志 | `/api/v1/audit/logs` | 操作追溯 |

## 项目结构

```
HomeLocus/
├── backend/           # FastAPI 后端（38 个 API 端点，13 张数据表）
├── frontend/          # Flutter 前端（8 个页面）
├── docker/            # Docker Compose 服务编排
└── docs/              # 文档
```

## License

MIT
