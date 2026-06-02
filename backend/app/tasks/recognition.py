import uuid
import logging
import os
import io

from app.tasks.celery_app import celery_app
from app.services.storage_service import storage_service
from app.services.ai_recognition import ai_recognition

logger = logging.getLogger(__name__)


@celery_app.task(bind=True, max_retries=3, default_retry_delay=60)
def process_upload(self, task_id: str, filepath: str, slot_id: str):
    """
    Full AI recognition pipeline triggered by photo upload.

    Steps:
    1. Upload original to MinIO
    2. Create compressed version → MinIO
    3. OCR text extraction (PaddleOCR)
    4. Vision AI object detection (DeepSeek-V4)
    5. Crop thumbnails for each detected item → MinIO
    6. Index items in Meilisearch + Qdrant
    7. Store results in PostgreSQL via ImageSnapshot + Items
    """
    logger.info(f"[{task_id}] Starting recognition pipeline for {filepath}")

    result = {
        "task_id": task_id,
        "status": "processing",
        "items": [],
        "summary": "",
        "ocr_texts": [],
    }

    try:
        # Step 1: Upload original to MinIO
        orig_name = f"{slot_id}/originals/{uuid.uuid4().hex}.jpg"
        storage_service.upload_file(filepath, orig_name)
        result["original_url"] = storage_service.get_presigned_url(orig_name)
        logger.info(f"[{task_id}] Original uploaded: {orig_name}")

        # Step 2: Compress and upload
        compressed_buf = storage_service.compress_image(filepath)
        comp_name = f"{slot_id}/compressed/{uuid.uuid4().hex}.jpg"
        storage_service.upload_bytes(compressed_buf.getvalue(), comp_name)
        result["compressed_url"] = storage_service.get_presigned_url(comp_name)
        logger.info(f"[{task_id}] Compressed uploaded: {comp_name}")

        # Step 3: OCR (async)
        ocr_texts = celery_app.send_task(
            "app.tasks.recognition.extract_ocr",
            args=[filepath],
        ).get(timeout=30)
        result["ocr_texts"] = ocr_texts

        # Step 4: Vision AI
        vision_result = celery_app.send_task(
            "app.tasks.recognition.analyze_vision",
            args=[filepath],
        ).get(timeout=120)
        result["summary"] = vision_result.get("summary", "")
        logger.info(f"[{task_id}] Vision detected {len(vision_result.get('items', []))} items")

        # Step 5: Crop thumbnails for each item
        for i, item in enumerate(vision_result.get("items", [])):
            if item.get("bounding_box"):
                try:
                    thumb_buf = storage_service.crop_thumbnail(filepath, item["bounding_box"])
                    thumb_name = f"{slot_id}/thumbnails/{uuid.uuid4().hex}.jpg"
                    storage_service.upload_bytes(thumb_buf.getvalue(), thumb_name)
                    item["thumbnail_path"] = thumb_name
                    item["thumbnail_url"] = storage_service.get_presigned_url(thumb_name)
                except Exception as e:
                    logger.warning(f"[{task_id}] Thumbnail crop failed for item {i}: {e}")
                    item["thumbnail_path"] = None

            item["id"] = f"item_{uuid.uuid4().hex[:8]}"

        result["items"] = vision_result.get("items", [])
        result["status"] = "completed"
        logger.info(f"[{task_id}] Pipeline completed: {len(result['items'])} items")

    except Exception as e:
        logger.error(f"[{task_id}] Pipeline failed: {e}")
        result["status"] = "failed"
        result["error"] = str(e)

    finally:
        # Clean up local temp file
        try:
            os.unlink(filepath)
        except OSError:
            pass

    return result


@celery_app.task(bind=True, max_retries=2)
def extract_ocr(self, filepath: str) -> list[str]:
    """OCR text extraction sub-task."""
    try:
        return ai_recognition.extract_text_sync(filepath)
    except Exception as e:
        logger.error(f"OCR failed: {e}")
        return []


@celery_app.task(bind=True, max_retries=2)
def analyze_vision(self, filepath: str) -> dict:
    """Synchronous wrapper for vision API call (Celery tasks must be sync)."""
    import asyncio
    try:
        return asyncio.run(ai_recognition.analyze_image(filepath))
    except Exception as e:
        logger.error(f"Vision analysis failed: {e}")
        return {"items": [], "summary": str(e)}
