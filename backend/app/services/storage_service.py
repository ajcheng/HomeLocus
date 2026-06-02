import io
import os
import logging
import shutil
from typing import Optional

from PIL import Image

from app.core.config import settings

logger = logging.getLogger(__name__)


class LocalStorage:
    """Local filesystem storage backend."""

    def __init__(self, base_path: str):
        self.base_path = base_path
        os.makedirs(base_path, exist_ok=True)

    def upload_file(self, local_path: str, object_name: str, content_type: str = "image/jpeg") -> str:
        dest = os.path.join(self.base_path, object_name)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        shutil.copy2(local_path, dest)
        return object_name

    def upload_bytes(self, data: bytes, object_name: str, content_type: str = "image/jpeg") -> str:
        dest = os.path.join(self.base_path, object_name)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        with open(dest, "wb") as f:
            f.write(data)
        return object_name

    def get_presigned_url(self, object_name: str, expires: int = 3600) -> str:
        return f"/api/v1/files/{object_name}"

    def get_object(self, object_name: str) -> bytes | None:
        path = os.path.join(self.base_path, object_name)
        if os.path.isfile(path):
            with open(path, "rb") as f:
                return f.read()
        return None

    def delete(self, object_name: str):
        path = os.path.join(self.base_path, object_name)
        if os.path.isfile(path):
            os.unlink(path)


class S3Storage:
    """S3-compatible storage backend (MinIO or AWS S3)."""

    def __init__(self):
        from minio import Minio
        self.client = Minio(
            endpoint=settings.storage_endpoint,
            access_key=settings.storage_access_key,
            secret_key=settings.storage_secret_key,
            secure=settings.storage_secure,
        )
        self.bucket = settings.storage_bucket
        self._ensure_bucket()

    def _ensure_bucket(self):
        if not self.client.bucket_exists(self.bucket):
            self.client.make_bucket(self.bucket)
            logger.info(f"Created bucket: {self.bucket}")

    def upload_file(self, local_path: str, object_name: str, content_type: str = "image/jpeg") -> str:
        self.client.fput_object(self.bucket, object_name, local_path, content_type=content_type)
        return object_name

    def upload_bytes(self, data: bytes, object_name: str, content_type: str = "image/jpeg") -> str:
        self.client.put_object(self.bucket, object_name, io.BytesIO(data), len(data), content_type=content_type)
        return object_name

    def get_presigned_url(self, object_name: str, expires: int = 3600) -> str:
        from datetime import timedelta
        from minio.error import S3Error
        try:
            return self.client.presigned_get_object(self.bucket, object_name, expires=timedelta(seconds=expires))
        except S3Error:
            return ""

    def get_object(self, object_name: str) -> bytes | None:
        from minio.error import S3Error
        try:
            response = self.client.get_object(self.bucket, object_name)
            return response.read()
        except S3Error:
            return None

    def delete(self, object_name: str):
        from minio.error import S3Error
        try:
            self.client.remove_object(self.bucket, object_name)
        except S3Error:
            pass


class StorageService:
    """Unified storage interface: local, minio, or s3."""

    def __init__(self):
        backend = settings.storage_backend
        if backend == "local":
            self._impl = LocalStorage(settings.storage_local_path)
        elif backend in ("minio", "s3"):
            self._impl = S3Storage()
        else:
            logger.warning(f"Unknown storage backend '{backend}', falling back to local")
            self._impl = LocalStorage(settings.storage_local_path)
        logger.info(f"Storage backend: {backend}")

    @property
    def client(self):
        """Backward-compatible access to the underlying client."""
        return self._impl

    def upload_file(self, *args, **kwargs):
        return self._impl.upload_file(*args, **kwargs)

    def upload_bytes(self, *args, **kwargs):
        return self._impl.upload_bytes(*args, **kwargs)

    def get_presigned_url(self, *args, **kwargs):
        return self._impl.get_presigned_url(*args, **kwargs)

    def get_object(self, *args, **kwargs):
        return self._impl.get_object(*args, **kwargs)

    def delete(self, object_name: str):
        if hasattr(self._impl, "delete"):
            self._impl.delete(object_name)

    def compress_image(self, filepath: str, quality: int = 70, max_width: int = 1200) -> io.BytesIO:
        img = Image.open(filepath).convert("RGB")
        if img.width > max_width:
            ratio = max_width / img.width
            img = img.resize((max_width, int(img.height * ratio)), Image.LANCZOS)
        buf = io.BytesIO()
        img.save(buf, format="JPEG", quality=quality, optimize=True)
        buf.seek(0)
        return buf

    def crop_thumbnail(self, filepath: str, bbox: dict, size: int = 200) -> io.BytesIO:
        img = Image.open(filepath)
        x, y, w, h = bbox.get("x", 0), bbox.get("y", 0), bbox.get("w", 50), bbox.get("h", 50)
        cropped = img.crop((x, y, x + w, y + h)).convert("RGB")
        cropped.thumbnail((size, size), Image.LANCZOS)
        buf = io.BytesIO()
        cropped.save(buf, format="JPEG", quality=80)
        buf.seek(0)
        return buf


storage_service = StorageService()
