import json
import logging
import base64
from io import BytesIO
from pathlib import Path
from typing import Optional

import httpx
from PIL import Image

from app.core.config import settings

logger = logging.getLogger(__name__)

DETECTION_PROMPT = """Analyze this image of a storage space (drawer, cabinet, shelf, etc.).

For each distinct item you can identify:
1. Name/label (be specific, include brand if visible)
2. Bounding box: approximate [x, y, width, height] as percentage of image (0-100)
3. Category (electronics, clothing, documents, tools, etc.)
4. Whether this looks like a chargeable device

Respond ONLY in JSON format:
{
  "items": [
    {
      "label": "Item name",
      "brand": "Brand if visible",
      "category": "category",
      "bounding_box": {"x": 10, "y": 20, "w": 30, "h": 25},
      "is_chargeable": false,
      "confidence": 0.95
    }
  ],
  "summary": "Brief description of the storage space"
}

If you cannot identify any items clearly, return: {"items": [], "summary": "No clear items detected"}"""

OCR_PROMPT = """Read ALL visible text in this image (labels, brands, handwriting, receipts, tags).
Return ONLY JSON:
{"lines": ["line1", "line2"]}
Use Chinese where shown. If no text, return {"lines": []}"""


class AIRecognitionService:
    """AI-powered image recognition (OpenAI-compatible or Anthropic Vision API)."""

    def __init__(self):
        self.api_key = settings.ai_api_key
        self.base_url = settings.ai_base_url.rstrip("/")
        self.model = settings.ai_vision_model

    def _prefers_openai_api(self) -> bool:
        return settings.ai_provider in ("openai", "custom")

    def _use_yolo(self) -> bool:
        provider = (settings.recognition_provider or "yolo").lower()
        if provider == "vision":
            return False
        if not (settings.yolo_api_url or "").strip():
            return False
        return provider in ("yolo", "auto")

    async def analyze_image(self, image_path: str) -> dict:
        if self._use_yolo():
            try:
                result = await self._analyze_yolo(image_path)
                if result.get("items") is not None:
                    return result
            except Exception as e:
                logger.warning(f"YOLO recognition failed: {e}")
                if (settings.recognition_provider or "").lower() == "yolo":
                    return self._simulate_detection(
                        image_path,
                        reason=f"YOLO 不可用: {e}",
                    )

        if not self.api_key:
            return self._simulate_detection(image_path)

        try:
            img = Image.open(image_path).convert("RGB")
            if max(img.size) > 1024:
                ratio = 1024 / max(img.size)
                img = img.resize((int(img.width * ratio), int(img.height * ratio)), Image.LANCZOS)
            buf = BytesIO()
            img.save(buf, format="JPEG", quality=70)
            image_b64 = base64.b64encode(buf.getvalue()).decode()

            if self._prefers_openai_api():
                result = await self._try_openai_format(image_b64)
                if result.get("items") is not None or result.get("summary"):
                    return result
                return await self._try_anthropic_format(image_b64)

            result = await self._try_anthropic_format(image_b64)
            if result.get("items") is not None or result.get("summary"):
                return result
            return await self._try_openai_format(image_b64)

        except Exception as e:
            logger.error(f"Vision API failed: {e}, falling back to simulation")
            return self._simulate_detection(image_path)

    async def _try_openai_format(self, image_b64: str) -> dict:
        """OpenAI-compatible vision (FlowBar / OpenAI / DeepSeek relay)."""
        try:
            async with httpx.AsyncClient(timeout=120.0) as client:
                response = await client.post(
                    f"{self.base_url}/v1/chat/completions",
                    headers={
                        "Authorization": f"Bearer {self.api_key}",
                        "Content-Type": "application/json",
                    },
                    json={
                        "model": self.model,
                        "messages": [{
                            "role": "user",
                            "content": [
                                {"type": "text", "text": DETECTION_PROMPT},
                                {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{image_b64}"}},
                            ],
                        }],
                        "max_tokens": 4096,
                    },
                )
                if response.status_code != 200:
                    logger.error(f"OpenAI vision error {response.status_code}: {response.text[:300]}")
                    return {"items": [], "summary": ""}
                result = response.json()
                content = result["choices"][0]["message"]["content"] or ""
                if not content.strip():
                    content = result["choices"][0]["message"].get("reasoning_content", "")
                return self._parse_vision_response(content)
        except Exception as e:
            logger.error(f"OpenAI vision failed: {e}")
            return {"items": [], "summary": ""}

    async def _try_anthropic_format(self, image_b64: str) -> dict:
        """Anthropic-compatible vision endpoint."""
        try:
            async with httpx.AsyncClient(timeout=120.0) as client:
                response = await client.post(
                    f"{self.base_url}/anthropic/v1/messages",
                    headers={
                        "x-api-key": self.api_key,
                        "anthropic-version": "2023-06-01",
                        "Content-Type": "application/json",
                    },
                    json={
                        "model": self.model,
                        "max_tokens": 2048,
                        "messages": [{
                            "role": "user",
                            "content": [
                                {"type": "text", "text": DETECTION_PROMPT},
                                {
                                    "type": "image",
                                    "source": {
                                        "type": "base64",
                                        "media_type": "image/jpeg",
                                        "data": image_b64,
                                    },
                                },
                            ],
                        }],
                    },
                )
                if response.status_code != 200:
                    logger.error(f"Anthropic vision error {response.status_code}: {response.text[:300]}")
                    return {"items": [], "summary": ""}
                result = response.json()
                content = result["content"][0]["text"]
                return self._parse_vision_response(content)
        except Exception as e:
            logger.error(f"Anthropic vision failed: {e}")
            return {"items": [], "summary": ""}

    def _parse_vision_response(self, content: str) -> dict:
        content = content.strip()
        if content.startswith("```"):
            lines = content.split("\n")
            if lines[0].startswith("```"):
                lines = lines[1:]
            if lines and lines[-1].startswith("```"):
                lines = lines[:-1]
            content = "\n".join(lines)
        try:
            return json.loads(content)
        except json.JSONDecodeError:
            import re
            match = re.search(r'\{[^{]*"items"\s*:\s*\[.*?\][^}]*\}', content, re.DOTALL)
            if match:
                try:
                    return json.loads(match.group())
                except json.JSONDecodeError:
                    pass
            return {"items": [], "summary": content[:200]}

    async def _analyze_yolo(self, image_path: str) -> dict:
        """调用 homelocus-yolo-vision FastAPI（/v1/analyze）。"""
        base = settings.yolo_api_url.rstrip("/")
        url = f"{base}/v1/analyze" if not base.endswith("/v1/analyze") else base
        headers = {}
        if settings.yolo_api_key:
            headers["X-API-Key"] = settings.yolo_api_key
        filename = Path(image_path).name or "image.jpg"
        data = {
            "model": settings.yolo_model,
            "conf": str(settings.yolo_conf),
            "lang": "zh",
        }
        async with httpx.AsyncClient(timeout=settings.yolo_timeout, verify=False) as client:
            with open(image_path, "rb") as f:
                files = {"file": (filename, f, "image/jpeg")}
                response = await client.post(url, files=files, data=data, headers=headers)
        if response.status_code != 200:
            raise RuntimeError(f"YOLO API {response.status_code}: {response.text[:300]}")
        body = response.json()
        items = body.get("items", [])
        for item in items:
            if "label" not in item and item.get("label_zh"):
                item["label"] = item["label_zh"]
        return {
            "items": items,
            "summary": body.get("summary", ""),
            "provider": body.get("provider", "yolo"),
            "detections_zh": body.get("detections_zh"),
        }

    def _simulate_detection(self, image_path: str, reason: str = "") -> dict:
        try:
            img = Image.open(image_path)
            w, h = img.size
        except Exception:
            w, h = 800, 600
        msg = reason or f"Image size: {w}x{h}. AI recognition not configured."
        return {"items": [], "summary": msg}

    async def _image_to_b64(self, image_path: str) -> str:
        img = Image.open(image_path).convert("RGB")
        if max(img.size) > 1024:
            ratio = 1024 / max(img.size)
            img = img.resize((int(img.width * ratio), int(img.height * ratio)), Image.LANCZOS)
        buf = BytesIO()
        img.save(buf, format="JPEG", quality=70)
        return base64.b64encode(buf.getvalue()).decode()

    async def extract_text_ocr(self, image_path: str) -> list[str]:
        """Extract text via Vision API when PaddleOCR is not deployed."""
        if not self.api_key:
            logger.info(f"OCR skipped for {image_path} (AI_API_KEY not configured)")
            return []
        try:
            image_b64 = await self._image_to_b64(image_path)
            if self._prefers_openai_api():
                raw = await self._vision_text_openai(image_b64, OCR_PROMPT)
            else:
                raw = await self._vision_text_anthropic(image_b64, OCR_PROMPT)
            if not raw:
                return []
            data = self._parse_vision_response(raw)
            lines = data.get("lines", [])
            if isinstance(lines, list):
                return [str(x).strip() for x in lines if str(x).strip()]
        except Exception as e:
            logger.error(f"Vision OCR failed for {image_path}: {e}")
        return []

    async def _vision_text_openai(self, image_b64: str, prompt: str) -> str | None:
        try:
            async with httpx.AsyncClient(timeout=60.0) as client:
                response = await client.post(
                    f"{self.base_url}/v1/chat/completions",
                    headers={
                        "Authorization": f"Bearer {self.api_key}",
                        "Content-Type": "application/json",
                    },
                    json={
                        "model": self.model,
                        "messages": [{
                            "role": "user",
                            "content": [
                                {"type": "text", "text": prompt},
                                {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{image_b64}"}},
                            ],
                        }],
                        "max_tokens": 1024,
                    },
                )
                if response.status_code != 200:
                    return None
                return response.json()["choices"][0]["message"]["content"].strip()
        except Exception:
            return None

    async def _vision_text_anthropic(self, image_b64: str, prompt: str) -> str | None:
        try:
            async with httpx.AsyncClient(timeout=60.0) as client:
                response = await client.post(
                    f"{self.base_url}/anthropic/v1/messages",
                    headers={
                        "x-api-key": self.api_key,
                        "anthropic-version": "2023-06-01",
                        "Content-Type": "application/json",
                    },
                    json={
                        "model": self.model,
                        "max_tokens": 1024,
                        "messages": [{
                            "role": "user",
                            "content": [
                                {"type": "image", "source": {"type": "base64", "media_type": "image/jpeg", "data": image_b64}},
                                {"type": "text", "text": prompt},
                            ],
                        }],
                    },
                )
                if response.status_code != 200:
                    return None
                return response.json()["content"][0]["text"].strip()
        except Exception:
            return None

    def extract_text_sync(self, image_path: str) -> list[str]:
        import asyncio
        try:
            return asyncio.run(self.extract_text_ocr(image_path))
        except Exception:
            return []


ai_recognition = AIRecognitionService()
