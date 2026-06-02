import uuid
import logging
import os
import io
import asyncio

from app.tasks.celery_app import celery_app
from app.services.storage_service import storage_service
from app.services.ai_recognition import ai_recognition

logger = logging.getLogger(__name__)


@celery_app.task(bind=True, max_retries=3, default_retry_delay=60)
def process_upload(self, task_id: str, filepath: str, slot_id: str):
    """
    Full AI recognition pipeline:
    1. Upload original + compressed to storage
    2. OCR + Vision AI (inline, no subtask .get())
    3. Crop thumbnails
    """
    logger.info(f"[{task_id}] Starting recognition for {filepath}")

    result = {"task_id": task_id, "status": "processing", "items": [], "summary": "", "ocr_texts": []}

    try:
        # Step 1: Upload original
        orig_name = f"{slot_id}/originals/{uuid.uuid4().hex}.jpg"
        storage_service.upload_file(filepath, orig_name)
        result["original_url"] = storage_service.get_presigned_url(orig_name)

        # Step 2: Compress
        compressed_buf = storage_service.compress_image(filepath)
        comp_name = f"{slot_id}/compressed/{uuid.uuid4().hex}.jpg"
        storage_service.upload_bytes(compressed_buf.getvalue(), comp_name)
        result["compressed_url"] = storage_service.get_presigned_url(comp_name)
        logger.info(f"[{task_id}] Images stored")

        # Step 3: OCR (inline)
        ocr_texts = ai_recognition.extract_text_sync(filepath)
        result["ocr_texts"] = ocr_texts

        # Step 4: Vision AI (run async in sync context via asyncio)
        vision_result = asyncio.run(ai_recognition.analyze_image(filepath))
        result["summary"] = vision_result.get("summary", "")
        logger.info(f"[{task_id}] Vision detected {len(vision_result.get('items', []))} items")

        # Step 5: Crop thumbnails
        for i, item in enumerate(vision_result.get("items", [])):
            if item.get("bounding_box"):
                try:
                    thumb_buf = storage_service.crop_thumbnail(filepath, item["bounding_box"])
                    thumb_name = f"{slot_id}/thumbnails/{uuid.uuid4().hex}.jpg"
                    storage_service.upload_bytes(thumb_buf.getvalue(), thumb_name)
                    item["thumbnail_path"] = thumb_name
                    item["thumbnail_url"] = storage_service.get_presigned_url(thumb_name)
                except Exception as e:
                    logger.warning(f"[{task_id}] Thumbnail crop failed: {e}")
            item["id"] = f"item_{uuid.uuid4().hex[:8]}"

        result["items"] = vision_result.get("items", [])
        result["status"] = "completed"
        logger.info(f"[{task_id}] Pipeline completed: {len(result['items'])} items")

    except Exception as e:
        logger.error(f"[{task_id}] Pipeline failed: {e}")
        result["status"] = "failed"
        result["error"] = str(e)

    finally:
        try:
            os.unlink(filepath)
        except OSError:
            pass

    return result
