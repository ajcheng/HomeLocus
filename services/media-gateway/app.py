"""
HomeLocus Media Gateway — 轻量图片上传服务
供纯本地 App 将图片上传后获得公网 URL，供千问等视觉大模型 imageFileUrls 使用。
"""
import os
import uuid
from datetime import datetime
from pathlib import Path

from flask import Flask, jsonify, request, send_from_directory
from werkzeug.utils import secure_filename

app = Flask(__name__)

UPLOAD_DIR = Path(os.environ.get("UPLOAD_DIR", "/data/media-gateway/uploads"))
PUBLIC_BASE_URL = os.environ.get("PUBLIC_BASE_URL", "").rstrip("/")
API_KEY = os.environ.get("MEDIA_GATEWAY_API_KEY", "")
MAX_MB = int(os.environ.get("MAX_UPLOAD_MB", "20"))
ALLOWED = {"jpg", "jpeg", "png", "webp", "gif"}

UPLOAD_DIR.mkdir(parents=True, exist_ok=True)


def _check_auth():
    if not API_KEY:
        return True
    auth = request.headers.get("Authorization", "")
    if auth.startswith("Bearer ") and auth[7:] == API_KEY:
        return True
    return request.headers.get("X-API-Key") == API_KEY


def _ext(filename: str) -> str:
    if "." not in filename:
        return "jpg"
    return filename.rsplit(".", 1)[1].lower()


@app.get("/health")
def health():
    return jsonify({"status": "ok", "service": "media-gateway"})


@app.post("/upload")
def upload():
    if not _check_auth():
        return jsonify({"success": False, "message": "Unauthorized"}), 401

    if "file" not in request.files:
        return jsonify({"success": False, "message": "缺少 file 字段"}), 400

    f = request.files["file"]
    if not f.filename:
        return jsonify({"success": False, "message": "文件名为空"}), 400

    ext = _ext(f.filename)
    if ext not in ALLOWED:
        return jsonify({"success": False, "message": f"不支持的格式: {ext}"}), 400

    f.seek(0, os.SEEK_END)
    size = f.tell()
    f.seek(0)
    if size > MAX_MB * 1024 * 1024:
        return jsonify({"success": False, "message": f"文件超过 {MAX_MB}MB"}), 400

    sub = datetime.utcnow().strftime("%Y/%m/%d")
    dest_dir = UPLOAD_DIR / sub
    dest_dir.mkdir(parents=True, exist_ok=True)
    name = f"{uuid.uuid4().hex[:12]}.{ext}"
    path = dest_dir / name
    f.save(path)

    url = f"{PUBLIC_BASE_URL}/files/{sub}/{name}"
    return jsonify({
        "success": True,
        "url": url,
        "path": str(path),
        "filename": name,
        "size": size,
    })


@app.get("/files/<path:filepath>")
def serve_file(filepath):
    # filepath 形如 2026/06/08/abc.jpg
    safe = Path(filepath)
    if ".." in safe.parts:
        return jsonify({"message": "Invalid path"}), 400
    directory = UPLOAD_DIR / safe.parent
    return send_from_directory(directory, safe.name)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", "8780")))
