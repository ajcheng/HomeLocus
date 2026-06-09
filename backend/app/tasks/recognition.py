import uuid
import logging
import os
import asyncio

from app.tasks.celery_app import celery_app
from app.services.storage_service import storage_service
from app.services.ai_recognition import ai_recognition

logger = logging.getLogger(__name__)


def _persist_task_result(task_id: str, items: list, ocr_text: str = "") -> None:
    """仅将识别结果写入快照 JSON，不创建 Item 记录（待用户确认后再入库）。"""
    if not items and not ocr_text:
        return

    from sqlalchemy import create_engine
    from sqlalchemy.orm import sessionmaker

    from app.core.config import settings
    from app.models.item import ImageSnapshot

    try:
        engine = create_engine(settings.database_url_sync)
        Session = sessionmaker(bind=engine)
        with Session() as session:
            snapshot = session.query(ImageSnapshot).filter_by(task_id=task_id).first()
            if not snapshot:
                logger.warning(f"[{task_id}] Snapshot not found for DB persist")
                return
            snapshot.ai_response_raw = {"items": items}
            if ocr_text:
                snapshot.ocr_text = ocr_text
            session.commit()
        logger.info(f"[{task_id}] Recognition saved to snapshot only ({len(items)} items pending confirm)")
    except Exception as e:
        logger.warning(f"[{task_id}] Failed to persist snapshot: {e}")


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
        from datetime import datetime
        dated = datetime.utcnow().strftime("%Y/%m/%d")
        orig_name = f"{dated}/{slot_id}/{uuid.uuid4().hex}.jpg"
        storage_service.upload_file(filepath, orig_name)
        result["original_url"] = storage_service.get_presigned_url(orig_name)

        compressed_buf = storage_service.compress_image(filepath)
        comp_name = f"{dated}/{slot_id}/{uuid.uuid4().hex}_cmp.jpg"
        storage_service.upload_bytes(compressed_buf.getvalue(), comp_name)
        result["compressed_url"] = storage_service.get_presigned_url(comp_name)
        result["storage_original"] = orig_name
        result["storage_compressed"] = comp_name
        logger.info(f"[{task_id}] Images stored")

        try:
            from sqlalchemy import create_engine
            from sqlalchemy.orm import sessionmaker
            from app.core.config import settings
            from app.models.item import ImageSnapshot

            engine = create_engine(settings.database_url_sync)
            Session = sessionmaker(bind=engine)
            with Session() as session:
                snap = session.query(ImageSnapshot).filter_by(task_id=task_id).first()
                if snap:
                    snap.original_path = orig_name
                    snap.compressed_path = comp_name
                    session.commit()
        except Exception as e:
            logger.warning(f"[{task_id}] Failed to update snapshot paths: {e}")

        ocr_texts = ai_recognition.extract_text_sync(filepath)
        result["ocr_texts"] = ocr_texts
        ocr_blob = " ".join(ocr_texts)
        if ocr_blob:
            from sqlalchemy import create_engine
            from sqlalchemy.orm import sessionmaker
            from app.core.config import settings
            from app.models.item import ImageSnapshot

            try:
                engine = create_engine(settings.database_url_sync)
                Session = sessionmaker(bind=engine)
                with Session() as session:
                    snap = session.query(ImageSnapshot).filter_by(task_id=task_id).first()
                    if snap:
                        snap.ocr_text = ocr_blob
                        session.commit()
            except Exception as e:
                logger.warning(f"[{task_id}] Failed to save OCR text: {e}")

        vision_result = asyncio.run(ai_recognition.analyze_image(filepath))
        result["summary"] = vision_result.get("summary", "")
        logger.info(f"[{task_id}] Vision detected {len(vision_result.get('items', []))} items")

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
        logger.info(f"[{task_id}] Pipeline completed: {len(result['items'])} items (awaiting user confirm)")

        _persist_task_result(task_id, result["items"], ocr_blob)

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
