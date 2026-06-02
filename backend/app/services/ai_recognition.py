import json
import logging
import time
from typing import Optional
from urllib.parse import urljoin

import httpx
from PIL import Image

from app.core.config import settings

logger = logging.getLogger(__name__)

DETECTION_PROMPT = """Analyze this image of a storage space (drawer, cabinet, shelf, etc.).

For each distinct item you can identify:
1. Name/label (be specific, include brand if visible)
2. Bounding box: approximate [x, y, width, height] as percentage of image (0-100)
3. Category (electronics, clothing, documents, tools, etc.)
4. Whether this looks like a chargeable device (phone, tablet, tool battery, etc.)

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
    """AI-powered image recognition using DeepSeek-V4 Vision API."""

    def __init__(self):
        self.api_key = settings.ai_api_key
        self.base_url = settings.ai_base_url.rstrip("/") + "/v1"
        self.model = settings.ai_vision_model  # Vision-capable model

    async def analyze_image(self, image_path: str) -> dict:
        """
        Send image to vision model for object detection and labeling.
        Falls back to simulated detection if API key is not configured.
        """
        if not self.api_key:
            return self._simulate_detection(image_path)

        try:
            import base64
            with open(image_path, "rb") as f:
                image_b64 = base64.b64encode(f.read()).decode()

            async with httpx.AsyncClient(timeout=60.0) as client:
                response = await client.post(
                    f"{self.base_url}/chat/completions",
                    headers={
                        "Authorization": f"Bearer {self.api_key}",
                        "Content-Type": "application/json",
                    },
                    json={
                        "model": self.model,
                        "messages": [
                            {
                                "role": "user",
                                "content": [
                                    {"type": "text", "text": DETECTION_PROMPT},
                                    {
                                        "type": "image_url",
                                        "image_url": {"url": f"data:image/jpeg;base64,{image_b64}"},
                                    },
                                ],
                            }
                        ],
                        "max_tokens": 2048,
                        "temperature": 0.1,
                    },
                )
                response.raise_for_status()
                result = response.json()
                content = result["choices"][0]["message"]["content"]

                # Extract JSON from response
                return self._parse_vision_response(content)

        except Exception as e:
            logger.error(f"Vision API failed: {e}, falling back to simulation")
            return self._simulate_detection(image_path)

    def _parse_vision_response(self, content: str) -> dict:
        """Parse JSON from vision model response."""
        try:
            content = content.strip()
            if content.startswith("```"):
                content = content.split("\n", 1)[1]
                if content.endswith("```"):
                    content = content[:-3]
            return json.loads(content)
        except json.JSONDecodeError:
            # Try to find JSON block
            import re
            match = re.search(r'\{[^{]*"items"\s*:\s*\[.*?\][^}]*\}', content, re.DOTALL)
            if match:
                try:
                    return json.loads(match.group())
                except json.JSONDecodeError:
                    pass
            return {"items": [], "summary": content[:200]}

    def _simulate_detection(self, image_path: str) -> dict:
        """Fallback: basic image analysis without AI."""
        try:
            img = Image.open(image_path)
            w, h = img.size
        except Exception:
            w, h = 800, 600

        return {
            "items": [],
            "summary": f"Image size: {w}x{h}. Configure DEEPSEEK_API_KEY for AI recognition.",
        }

    async def extract_text_ocr(self, image_path: str) -> list[str]:
        """Extract text from image using PaddleOCR (placeholder)."""
        logger.info(f"OCR processing skipped for {image_path} (PaddleOCR not configured)")
        return []

    def extract_text_sync(self, image_path: str) -> list[str]:
        """Synchronous OCR wrapper for Celery tasks."""
        import asyncio
        try:
            return asyncio.run(self.extract_text_ocr(image_path))
        except Exception as e:
            logger.error(f"OCR sync failed: {e}")
            return []


ai_recognition = AIRecognitionService()
