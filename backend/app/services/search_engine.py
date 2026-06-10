import hashlib
import logging
import uuid
from typing import Optional

import meilisearch
from qdrant_client import QdrantClient
from qdrant_client.models import Distance, VectorParams, PointStruct

from app.core.config import settings

logger = logging.getLogger(__name__)

VECTOR_SIZE = 512  # placeholder; CLIP generates 512-dim vectors


def _str_to_uuid(s: str) -> str:
    """Convert a string ID to a valid UUID for Qdrant."""
    h = hashlib.md5(s.encode()).hexdigest()
    return str(uuid.UUID(h))


class SearchEngine:
    """Hybrid search engine: Meilisearch (text) + Qdrant (vector)."""

    def __init__(self):
        self.meili_enabled = False
        self.qdrant_enabled = False

        try:
            self.meili = meilisearch.Client(settings.meilisearch_url, settings.meilisearch_api_key)
            self._ensure_meili_index()
            self.meili_enabled = True
        except Exception as e:
            logger.warning("Meilisearch unavailable, text index disabled: %s", e)
            self.meili = None

        try:
            self.qdrant = QdrantClient(url=settings.qdrant_url)
            self._ensure_qdrant_collection()
            self.qdrant_enabled = True
        except Exception as e:
            logger.warning("Qdrant unavailable, vector search disabled: %s", e)
            self.qdrant = None

    # ---- Meilisearch (Text Search) ----
    def _ensure_meili_index(self):
        try:
            self.meili.get_index("items")
        except meilisearch.errors.MeilisearchApiError:
            self.meili.create_index("items", {"primaryKey": "id"})
            self.meili.index("items").update_filterable_attributes(["location_id", "category", "labels"])
            self.meili.index("items").update_searchable_attributes(
                ["label", "brand", "category", "tags", "ocr_text", "color", "purpose", "raw_recognition"]
            )

    def index_text(
        self,
        item_id: str,
        label: str,
        brand: str | None,
        tags: list[str],
        ocr_text: str,
        location_id: str,
        category: str | None = None,
        color: str | None = None,
        purpose: str | None = None,
        raw_recognition: str | None = None,
    ):
        """Index an item's text metadata in Meilisearch."""
        doc = {
            "id": item_id,
            "label": label,
            "brand": brand or "",
            "category": category or "",
            "tags": tags or [],
            "ocr_text": ocr_text,
            "location_id": location_id,
            "color": color or "",
            "purpose": purpose or "",
            "raw_recognition": raw_recognition or "",
        }
        if not self.meili_enabled:
            return
        try:
            self.meili.index("items").add_documents([doc])
        except Exception as e:
            logger.error(f"Meilisearch index failed for {item_id}: {e}")

    def search_text(
        self,
        query: str,
        location_id: str | None = None,
        category: str | None = None,
        limit: int = 20,
    ) -> list[dict]:
        """Full-text search with optional location/category filter."""
        if not self.meili_enabled:
            return []
        try:
            opt_params = {"limit": limit}
            filters = []
            if location_id:
                filters.append(f'location_id = "{location_id}"')
            if category:
                filters.append(f'category = "{category}"')
            if filters:
                opt_params["filter"] = " AND ".join(filters)
            result = self.meili.index("items").search(query, opt_params)
            return [
                {"id": h["id"], "label": h.get("label", ""), "score": 1.0 - (i * 0.02)}
                for i, h in enumerate(result.get("hits", []))
            ]
        except Exception as e:
            logger.error(f"Meilisearch search failed: {e}")
            return []

    def delete_text_index(self, item_id: str):
        if not self.meili_enabled:
            return
        try:
            self.meili.index("items").delete_document(item_id)
        except Exception:
            pass

    # ---- Qdrant (Vector Search) ----
    def _ensure_qdrant_collection(self):
        try:
            self.qdrant.get_collection("items")
        except Exception:
            self.qdrant.create_collection(
                collection_name="items",
                vectors_config=VectorParams(size=VECTOR_SIZE, distance=Distance.COSINE),
            )

    def index_vector(self, item_id: str, vector: list[float], payload: dict | None = None):
        """Upsert a vector embedding for an item."""
        if not self.qdrant_enabled:
            return
        try:
            uid = _str_to_uuid(item_id)
            self.qdrant.upsert(
                collection_name="items",
                points=[PointStruct(id=uid, vector=vector, payload=payload or {})],
            )
        except Exception as e:
            logger.error(f"Qdrant upsert failed for {item_id}: {e}")

    def search_vector(self, vector: list[float], location_id: str | None = None, limit: int = 20) -> list[dict]:
        """Vector similarity search."""
        if not self.qdrant_enabled:
            return []
        try:
            results = self.qdrant.search(
                collection_name="items",
                query_vector=vector,
                limit=limit,
            )
            return [
                {"id": str(r.id), "label": r.payload.get("label", ""), "score": float(r.score)}
                for r in results
            ]
        except Exception as e:
            logger.error(f"Qdrant search failed: {e}")
            return []

    def delete_vector_index(self, item_id: str):
        if not self.qdrant_enabled:
            return
        try:
            uid = _str_to_uuid(item_id)
            self.qdrant.delete("items", points_selector=[uid])
        except Exception:
            pass

    # ---- Hybrid (RRF Fusion) ----
    def hybrid_search(
        self,
        text: str | None = None,
        vector: list[float] | None = None,
        location_id: str | None = None,
        category: str | None = None,
        limit: int = 20,
    ) -> list[dict]:
        """Combine text and vector search with RRF fusion."""
        text_results = self.search_text(text, location_id, category, limit) if text else []
        vector_results = self.search_vector(vector, location_id, limit) if vector else []

        if not text_results and not vector_results:
            return []

        if text_results and not vector_results:
            return text_results[:limit]
        if vector_results and not text_results:
            return vector_results[:limit]

        # RRF fusion
        scores: dict[str, dict] = {}
        rrf_k = 60

        for rank, item in enumerate(text_results):
            key = item["id"]
            if key not in scores:
                scores[key] = item
            scores[key]["rrf_score"] = scores[key].get("rrf_score", 0) + 1.0 / (rrf_k + rank + 1)

        for rank, item in enumerate(vector_results):
            key = item["id"]
            if key not in scores:
                scores[key] = item
            scores[key]["rrf_score"] = scores[key].get("rrf_score", 0) + 1.0 / (rrf_k + rank + 1)

        merged = sorted(scores.values(), key=lambda x: x.get("rrf_score", 0), reverse=True)
        return merged[:limit]


search_engine = SearchEngine()
