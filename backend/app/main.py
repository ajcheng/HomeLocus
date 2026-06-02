import os
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse

from app.api.v1.router import router as v1_router
from app.core.security_middleware import RateLimitMiddleware

WEB_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(__file__))), "frontend", "build", "web")


@asynccontextmanager
async def lifespan(app: FastAPI):
    yield


app = FastAPI(
    title="HomeLocus API",
    description="""
## 家庭物品存放管理系统

### 核心功能
- **空间管理**: 四级空间拓扑（地点→分区→储物模块→层级）
- **AI 识别**: 拍照自动识别物品（DeepSeek-V4 Vision + PaddleOCR）
- **混合检索**: Meilisearch 文本 + Qdrant 向量 + RRF 融合 + 语义扩展
- **多成员协作**: 家庭创建/邀请码加入/RBAC 角色管理
- **定时提醒**: 充电提醒 + 借出归位提醒（Celery Beat）
- **平面图**: CAD/JPG 导入 + 多边形锚点

### 认证
所有业务接口需要 Bearer Token（注册/登录接口除外）。
""",
    version="0.2.0",
    lifespan=lifespan,
    docs_url="/api/docs",
    redoc_url="/api/redoc",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Rate limiting: 200 requests per 60s per IP
app.add_middleware(RateLimitMiddleware, max_requests=200, window_seconds=60)

app.include_router(v1_router, prefix="/api/v1")


@app.get("/health")
async def health_check():
    return {"status": "ok"}


@app.get("/app/{rest:path}")
async def spa_fallback(rest: str = ""):
    index = os.path.join(WEB_DIR, "index.html")
    if os.path.isfile(index):
        return FileResponse(index)
    return {"message": "Web app not built. Run: cd frontend && flutter build web"}


@app.get("/app")
async def spa_root():
    index = os.path.join(WEB_DIR, "index.html")
    if os.path.isfile(index):
        return FileResponse(index)
    return {"message": "Web app not built. Run: cd frontend && flutter build web"}


# Serve Flutter build assets
if os.path.isdir(WEB_DIR):
    app.mount("/", StaticFiles(directory=WEB_DIR, html=True), name="web")
