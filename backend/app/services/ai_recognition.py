import json
import logging
import base64
from io import BytesIO
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


class AIRecognitionService:
    """AI-powered image recognition using Anthropic-compatible Vision API."""

    def __init__(self):
        self.api_key = settings.ai_api_key
        # Use Anthropic-compatible endpoint for vision (supports image input)
        self.base_url = settings.ai_base_url.rstrip("/") + "/anthropic/v1/messages"
        self.model = settings.ai_vision_model

    async def analyze_image(self, image_path: str) -> dict:
        if not self.api_key:
            return self._simulate_detection(image_path)

        try:
            # Resize and encode image
            img = Image.open(image_path).convert("RGB")
            if max(img.size) > 1024:
                ratio = 1024 / max(img.size)
                img = img.resize((int(img.width * ratio), int(img.height * ratio)), Image.LANCZOS)
            buf = BytesIO()
            img.save(buf, format="JPEG", quality=70)
            image_b64 = base64.b64encode(buf.getvalue()).decode()

            async with httpx.AsyncClient(timeout=60.0) as client:
                response = await client.post(
                    self.base_url,
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
                    logger.error(f"Vision API error {response.status_code}: {response.text[:500]}")
                    # Try OpenAI-compatible format as fallback
                    return await self._try_openai_format(image_b64)

                result = response.json()
                content = result["content"][0]["text"]
                return self._parse_vision_response(content)

        except Exception as e:
            logger.error(f"Vision API failed: {e}, falling back to simulation")
            return self._simulate_detection(image_path)

    async def _try_openai_format(self, image_b64: str) -> dict:
        """Fallback: try OpenAI-compatible format."""
        try:
            async with httpx.AsyncClient(timeout=60.0) as client:
                response = await client.post(
                    settings.ai_base_url.rstrip("/") + "/v1/chat/completions",
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
                        "max_tokens": 2048,
                    },
                )
                if response.status_code != 200:
                    logger.error(f"OpenAI format also failed {response.status_code}: {response.text[:300]}")
                    return self._simulate_detection("")
                result = response.json()
                content = result["choices"][0]["message"]["content"]
                return self._parse_vision_response(content)
        except Exception as e:
            logger.error(f"OpenAI fallback failed: {e}")
            return self._simulate_detection("")

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

    def _simulate_detection(self, image_path: str) -> dict:
        try:
            img = Image.open(image_path)
            w, h = img.size
        except Exception:
            w, h = 800, 600
        return {"items": [], "summary": f"Image size: {w}x{h}. AI recognition not configured."}

    async def extract_text_ocr(self, image_path: str) -> list[str]:
        logger.info(f"OCR skipped for {image_path} (PaddleOCR not configured)")
        return []

    def extract_text_sync(self, image_path: str) -> list[str]:
        import asyncio
        try:
            return asyncio.run(self.extract_text_ocr(image_path))
        except Exception:
            return []


ai_recognition = AIRecognitionService()
