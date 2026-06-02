import json
import logging
import httpx

from app.core.config import settings

logger = logging.getLogger(__name__)

EXPANSION_PROMPT = """You are a home storage search assistant. The user searched for: "{query}"

Your task: Expand this query into 3-5 specific search terms that would match items in a home storage database.
- Include synonyms, related items, and category expansions
- Consider Chinese context (e.g., "保暖穿的" should expand to "羽绒服, 棉衣, 毛衣, 围巾, 手套")
- Return ONLY a JSON array of strings, no explanation

Example:
Input: "充电的设备"
Output: ["充电宝", "手机充电器", "平板", "电动牙刷", "蓝牙耳机", "笔记本电源"]"""


class SemanticSearchService:
    """Semantic query expansion using LLM for fuzzy item matching."""

    def __init__(self):
        self.api_key = settings.ai_api_key
        self.base_url = settings.ai_base_url.rstrip("/") + "/v1"

    async def expand_query(self, query: str) -> list[str]:
        """Expand a fuzzy query into specific search terms."""
        if not self.api_key or len(query) < 2:
            return [query]

        try:
            async with httpx.AsyncClient(timeout=15.0) as client:
                response = await client.post(
                    f"{self.base_url}/chat/completions",
                    headers={
                        "Authorization": f"Bearer {self.api_key}",
                        "Content-Type": "application/json",
                    },
                    json={
                        "model": settings.ai_model,
                        "messages": [{"role": "user", "content": EXPANSION_PROMPT.format(query=query)}],
                        "max_tokens": 200,
                        "temperature": 0.3,
                    },
                )
                response.raise_for_status()
                content = response.json()["choices"][0]["message"]["content"]
                content = content.strip().strip("```json").strip("```").strip()
                terms = json.loads(content)
                if isinstance(terms, list) and terms:
                    return terms[:10]
        except Exception as e:
            logger.warning(f"Query expansion failed: {e}")

        # Fallback: return original query
        return [query]


semantic_search = SemanticSearchService()
