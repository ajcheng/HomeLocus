"""
HomeLocus ASR Gateway — 语音识别服务
支持 Qwen3-ASR（PyTorch CPU），供纯本地 App 上传音频获取文本。
"""
import logging
import os
import tempfile
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Optional

from fastapi import FastAPI, File, Form, HTTPException, Header, UploadFile
from pydantic import BaseModel

logger = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO)

API_KEY = os.environ.get("ASR_GATEWAY_API_KEY", "")
ASR_BACKEND = os.environ.get("ASR_BACKEND", "mock")  # mock | qwen_pytorch
ASR_MODEL_DIR = os.environ.get("ASR_MODEL_DIR", "Qwen/Qwen3-ASR-0.6B")
ASR_LANGUAGE = os.environ.get("ASR_LANGUAGE", "Chinese")

_LANG_ALIASES = {
    "zh": "Chinese",
    "zh-cn": "Chinese",
    "zh-hans": "Chinese",
    "cn": "Chinese",
    "en": "English",
    "en-us": "English",
    "yue": "Cantonese",
    "cantonese": "Cantonese",
}


def _normalize_language(language: Optional[str]) -> Optional[str]:
    if not language:
        return None
    key = language.strip().lower()
    if key in _LANG_ALIASES:
        return _LANG_ALIASES[key]
    return language.strip()

_model = None


def _check_auth(authorization: Optional[str], x_api_key: Optional[str]):
    if not API_KEY:
        return
    token = None
    if authorization and authorization.startswith("Bearer "):
        token = authorization[7:]
    if token != API_KEY and x_api_key != API_KEY:
        raise HTTPException(status_code=401, detail="Unauthorized")


def _load_qwen_model():
    global _model
    if _model is not None:
        return _model
    try:
        from qwen_asr import Qwen3ASRModel
        import torch
    except ImportError as e:
        raise RuntimeError("未安装 qwen-asr，请使用 Dockerfile.qwen 构建镜像") from e

    model_id = ASR_MODEL_DIR or "Qwen/Qwen3-ASR-0.6B"
    logger.info("Loading Qwen3 ASR model: %s (CPU)", model_id)
    kwargs = {
        "device_map": "cpu",
        "low_cpu_mem_usage": True,
    }
    try:
        _model = Qwen3ASRModel.from_pretrained(
            model_id,
            dtype=torch.float32,
            **kwargs,
        )
    except TypeError:
        _model = Qwen3ASRModel.from_pretrained(
            model_id,
            torch_dtype=torch.float32,
            **kwargs,
        )
    logger.info("Qwen3 ASR model loaded")
    return _model


def _extract_text(result) -> str:
    if result is None:
        return ""
    if isinstance(result, list):
        if not result:
            return ""
        return _extract_text(result[0])
    if hasattr(result, "text"):
        return str(result.text).strip()
    if isinstance(result, dict):
        return str(result.get("text", "")).strip()
    return str(result).strip()


def _transcribe_file(path: str, language: Optional[str]) -> str:
    backend = ASR_BACKEND.lower()
    lang = _normalize_language(language or ASR_LANGUAGE)

    if backend == "mock":
        return "[ASR mock] 请配置 ASR_BACKEND=qwen_pytorch 并安装模型"

    if backend == "qwen_pytorch":
        model = _load_qwen_model()
        kwargs = {"audio": path}
        if lang:
            kwargs["language"] = lang
        result = model.transcribe(**kwargs)
        text = _extract_text(result)
        if not text:
            raise RuntimeError("识别结果为空")
        return text

    raise RuntimeError(f"未知 ASR_BACKEND: {backend}")


@asynccontextmanager
async def lifespan(app: FastAPI):
    if ASR_BACKEND.lower() == "qwen_pytorch":
        try:
            _load_qwen_model()
        except Exception as e:
            logger.error("启动时加载 ASR 模型失败: %s", e)
    yield


app = FastAPI(title="HomeLocus ASR Gateway", version="1.1.0", lifespan=lifespan)


class TranscribeResponse(BaseModel):
    success: bool
    text: str
    backend: str
    language: Optional[str] = None


@app.get("/health")
def health():
    return {
        "status": "ok",
        "service": "asr-gateway",
        "backend": ASR_BACKEND,
        "model": ASR_MODEL_DIR,
        "model_loaded": _model is not None,
    }


@app.post("/transcribe", response_model=TranscribeResponse)
async def transcribe(
    file: UploadFile = File(...),
    language: Optional[str] = Form(None),
    authorization: Optional[str] = Header(None),
    x_api_key: Optional[str] = Header(None, alias="X-API-Key"),
):
    _check_auth(authorization, x_api_key)

    suffix = Path(file.filename or "audio.wav").suffix or ".wav"
    with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
        content = await file.read()
        if not content:
            raise HTTPException(status_code=400, detail="音频为空")
        tmp.write(content)
        tmp_path = tmp.name

    try:
        text = _transcribe_file(tmp_path, language)
        return TranscribeResponse(
            success=True,
            text=text,
            backend=ASR_BACKEND,
            language=language or ASR_LANGUAGE,
        )
    except Exception as e:
        logger.exception("ASR failed")
        raise HTTPException(status_code=500, detail=str(e)) from e
    finally:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=int(os.environ.get("PORT", "8781")))
