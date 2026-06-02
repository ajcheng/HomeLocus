import io
import uuid
import logging
from typing import Optional

from minio import Minio
from minio.error import S3Error
from PIL import Image

from app.core.config import settings

logger = logging.getLogger(__name__)


class StorageService:
    """MinIO object storage wrapper for photos, compressed images, and thumbnails."""

    def __init__(self):
        self.client = Minio(
            endpoint=settings.minio_endpoint,
            access_key=settings.minio_access_key,
            secret_key=settings.minio_secret_key,
            secure=settings.minio_secure,
        )
        self.bucket = settings.minio_bucket
        self._ensure_bucket()

    def _ensure_bucket(self):
        if not self.client.bucket_exists(self.bucket):
            self.client.make_bucket(self.bucket)
            logger.info(f"Created bucket: {self.bucket}")

    def upload_file(self, local_path: str, object_name: str, content_type: str = "image/jpeg") -> str:
        """Upload a local file to MinIO, returns object name."""
        self.client.fput_object(self.bucket, object_name, local_path, content_type=content_type)
        return object_name

    def upload_bytes(self, data: bytes, object_name: str, content_type: str = "image/jpeg") -> str:
        """Upload bytes to MinIO."""
        self.client.put_object(self.bucket, object_name, io.BytesIO(data), len(data), content_type=content_type)
        return object_name

    def get_presigned_url(self, object_name: str, expires: int = 3600) -> str:
        """Generate a presigned GET URL (default 1 hour expiry)."""
        from datetime import timedelta
        try:
            return self.client.presigned_get_object(self.bucket, object_name, expires=timedelta(seconds=expires))
        except S3Error:
            return ""

    def get_object(self, object_name: str) -> bytes | None:
        try:
            response = self.client.get_object(self.bucket, object_name)
            return response.read()
        except S3Error:
            return None

    def compress_image(self, filepath: str, quality: int = 70, max_width: int = 1200) -> io.BytesIO:
        """Create a compressed version of an image."""
        img = Image.open(filepath)
        img = img.convert("RGB")
        if img.width > max_width:
            ratio = max_width / img.width
            new_height = int(img.height * ratio)
            img = img.resize((max_width, new_height), Image.LANCZOS)
        buf = io.BytesIO()
        img.save(buf, format="JPEG", quality=quality, optimize=True)
        buf.seek(0)
        return buf

    def crop_thumbnail(self, filepath: str, bbox: dict, size: int = 200) -> io.BytesIO:
        """Crop a region from image and resize to thumbnail."""
        img = Image.open(filepath)
        x, y, w, h = bbox.get("x", 0), bbox.get("y", 0), bbox.get("w", 50), bbox.get("h", 50)
        cropped = img.crop((x, y, x + w, y + h))
        cropped = cropped.convert("RGB")
        cropped.thumbnail((size, size), Image.LANCZOS)
        buf = io.BytesIO()
        cropped.save(buf, format="JPEG", quality=80)
        buf.seek(0)
        return buf


storage_service = StorageService()
