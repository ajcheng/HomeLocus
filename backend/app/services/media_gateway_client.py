import logging
import os

import httpx

from app.core.config import settings

logger = logging.getLogger(__name__)


async def upload_image_file(image_path: str) -> str:
    """上传图片到 media-gateway，返回公网 URL。"""
    base = (settings.media_gateway_url or "").rstrip("/")
    if not base:
        raise RuntimeError("MEDIA_GATEWAY_URL 未配置")

    headers = {}
    if settings.media_gateway_api_key:
        headers["Authorization"] = f"Bearer {settings.media_gateway_api_key}"

    filename = os.path.basename(image_path) or "image.jpg"
    mime = "image/jpeg"
    if filename.lower().endswith(".png"):
        mime = "image/png"

    async with httpx.AsyncClient(timeout=120.0) as client:
        with open(image_path, "rb") as f:
            response = await client.post(
                f"{base}/upload",
                files={"file": (filename, f, mime)},
                headers=headers,
            )
    if response.status_code >= 400:
        raise RuntimeError(f"media-gateway 上传失败 {response.status_code}: {response.text[:300]}")
    data = response.json()
    url = data.get("url")
    if not url:
        raise RuntimeError("media-gateway 未返回 url")
    logger.info("Uploaded image to media-gateway: %s", url[:80])
    return url
