"""HomeLocus YOLO Vision API — OpenVINO 本地检测，输出 HomeLocus 兼容 JSON。"""
from __future__ import annotations

import os
import tempfile
import uuid
from pathlib import Path
from typing import Optional

from fastapi import Depends, FastAPI, File, Form, Header, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from app.config import settings
from app.detector import YoloDetector
from app.homelocus_mapper import to_homelocus_response

app = FastAPI(
    title="HomeLocus YOLO Vision",
    description="OpenVINO YOLO11 物品检测，输出 HomeLocus 识别格式（含中文类名）",
    version="1.0.0",
)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

_detector: YoloDetector | None = None


def get_detector() -> YoloDetector:
    global _detector
    if _detector is None:
        _detector = YoloDetector(settings.models_dir)
    return _detector


def verify_api_key(x_api_key: Optional[str] = Header(None, alias="X-API-Key")) -> None:
    if settings.api_key and x_api_key != settings.api_key:
        raise HTTPException(status_code=401, detail="Invalid API key")


class HealthResponse(BaseModel):
    status: str = "ok"
    models_dir: str
    default_model: str
    default_device: str


class ConfigResponse(BaseModel):
    models_dir: str
    default_model: str
    default_device: str
    default_conf: float
    supported_models: list[str] = Field(default_factory=lambda: ["yolo11", "worldv2", "both"])


@app.get("/health", response_model=HealthResponse)
def health():
    return HealthResponse(
        status="ok",
        models_dir=settings.models_dir,
        default_model=settings.default_model,
        default_device=settings.default_device,
    )


@app.get("/v1/config", response_model=ConfigResponse)
def get_config():
    return ConfigResponse(
        models_dir=settings.models_dir,
        default_model=settings.default_model,
        default_device=settings.default_device,
        default_conf=settings.default_conf,
    )


@app.post("/v1/analyze", dependencies=[Depends(verify_api_key)])
async def analyze(
    file: UploadFile = File(...),
    model: str = Form(default=""),
    device: str = Form(default=""),
    conf: float = Form(default=-1),
    lang: str = Form(default="zh"),
):
    """
    HomeLocus 主识别接口。
    返回 `{ items, summary, provider, detections_zh, raw }`，与 backend `ai_recognition.analyze_image` 对齐。
    """
    suffix = Path(file.filename or "image.jpg").suffix or ".jpg"
    max_bytes = settings.max_upload_mb * 1024 * 1024
    content = await file.read()
    if len(content) > max_bytes:
        raise HTTPException(status_code=413, detail=f"File too large (max {settings.max_upload_mb}MB)")

    tmp = os.path.join(tempfile.gettempdir(), f"yolo_{uuid.uuid4().hex}{suffix}")
    try:
        with open(tmp, "wb") as f:
            f.write(content)
        report = get_detector().detect_file(
            Path(tmp),
            model=model or settings.default_model,
            device=device or None,
            conf=conf if conf >= 0 else None,
        )
        report["image_width"] = report.get("image_width") or 0
        report["image_height"] = report.get("image_height") or 0
        return to_homelocus_response(report, lang=lang if lang in ("zh", "en") else "zh")
    finally:
        try:
            os.unlink(tmp)
        except OSError:
            pass


@app.post("/v1/detect", dependencies=[Depends(verify_api_key)])
async def detect_raw(
    file: UploadFile = File(...),
    model: str = Form(default=""),
    device: str = Form(default=""),
    conf: float = Form(default=-1),
):
    """原始 YOLO 检测报告（含中英文类名与 xyxy）。"""
    suffix = Path(file.filename or "image.jpg").suffix or ".jpg"
    content = await file.read()
    tmp = os.path.join(tempfile.gettempdir(), f"yolo_{uuid.uuid4().hex}{suffix}")
    try:
        with open(tmp, "wb") as f:
            f.write(content)
        report = get_detector().detect_file(
            Path(tmp),
            model=model or settings.default_model,
            device=device or None,
            conf=conf if conf >= 0 else None,
        )
        zh = to_homelocus_response(report, lang="zh")
        return {"report": report, "homelocus": zh}
    finally:
        try:
            os.unlink(tmp)
        except OSError:
            pass


# 兼容 Nginx 去掉前缀后的根路径健康检查
@app.get("/")
def root():
    return {"service": "homelocus-yolo-vision", "health": "/health", "analyze": "/v1/analyze"}
