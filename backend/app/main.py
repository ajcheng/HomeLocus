import os
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse

from app.api.v1.router import router as v1_router

WEB_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(__file__))), "frontend", "build", "web")


@asynccontextmanager
async def lifespan(app: FastAPI):
    yield


app = FastAPI(
    title="HomeLocus API",
    description="家庭物品存放管理系统",
    version="0.1.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

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
