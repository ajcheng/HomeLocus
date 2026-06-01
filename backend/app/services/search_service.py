from typing import Optional

from app.core.config import settings


class SearchService:
    """
    Hybrid search service combining:
    - Meilisearch (text search + fuzzy matching)
    - Qdrant (vector similarity search)
    - RRF (Reciprocal Rank Fusion) for result merging
    """

    def __init__(self):
        self.qdrant_url = settings.qdrant_url
        self.meili_url = settings.meilisearch_url
        self.meili_key = settings.meilisearch_api_key

    async def hybrid_search(
        self,
        text: Optional[str] = None,
        image_vector: Optional[list[float]] = None,
        location_id: Optional[str] = None,
        limit: int = 20,
    ) -> list[dict]:
        text_results = await self._text_search(text, location_id, limit) if text else []
        vector_results = await self._vector_search(image_vector, location_id, limit) if image_vector else []

        return self._rrf_fusion(text_results, vector_results, limit)

    async def _text_search(self, text: str, location_id: Optional[str], limit: int) -> list[dict]:
        # TODO: Meilisearch client integration
        return []

    async def _vector_search(self, vector: list[float], location_id: Optional[str], limit: int) -> list[dict]:
        # TODO: Qdrant client integration
        return []

    def _rrf_fusion(self, text_results: list[dict], vector_results: list[dict], k: int) -> list[dict]:
        """Reciprocal Rank Fusion — merge and re-rank results."""
        scores: dict[str, dict] = {}
        rrf_k = 60

        for rank, item in enumerate(text_results):
            key = item.get("id")
            if key not in scores:
                scores[key] = item
            scores[key]["rrf_score"] = scores[key].get("rrf_score", 0) + 1 / (rrf_k + rank + 1)

        for rank, item in enumerate(vector_results):
            key = item.get("id")
            if key not in scores:
                scores[key] = item
            scores[key]["rrf_score"] = scores[key].get("rrf_score", 0) + 1 / (rrf_k + rank + 1)

        merged = sorted(scores.values(), key=lambda x: x.get("rrf_score", 0), reverse=True)
        return merged[:k]

    async def index_item(self, item_id: str, label: str, tags: list[str], vector: list[float], location_id: str) -> None:
        """Index an item in both Meilisearch and Qdrant."""
        # TODO: Index in Meilisearch
        # TODO: Upsert in Qdrant
        pass

    async def delete_item_index(self, item_id: str) -> None:
        """Remove item from search indices."""
        # TODO: Delete from Meilisearch
        # TODO: Delete from Qdrant
        pass


search_service = SearchService()
