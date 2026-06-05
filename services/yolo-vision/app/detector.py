"""OpenVINO YOLO 检测核心（供 FastAPI 调用）。"""
from __future__ import annotations

import time
from pathlib import Path

from ultralytics import YOLO, YOLOWorld

from app.coco_names_zh import name_to_zh, names_dict_to_zh
from app.config import settings


def resolve_openvino_dir(models_root: Path, name: str) -> Path | None:
    patterns = [
        models_root / name,
        models_root.parent / name,
    ]
    for p in patterns:
        if p.is_dir() and (p / "metadata.yaml").exists():
            return p
    if models_root.exists():
        for d in models_root.glob(f"*{name}*openvino*"):
            if d.is_dir():
                return d
    return None


def find_model(kind: str, models_root: Path, explicit: str | None = None) -> Path:
    if explicit:
        p = Path(explicit)
        if p.exists():
            return p
        raise FileNotFoundError(f"模型路径不存在: {explicit}")

    aliases = {
        "yolo11": ["yolo11n_openvino_model", "yolo11s_openvino_model"],
        "worldv2": ["yolov8s-worldv2_openvino_model", "yolov8m-worldv2_openvino_model"],
    }
    for name in aliases.get(kind, []):
        found = resolve_openvino_dir(models_root, name)
        if found:
            return found
    raise FileNotFoundError(
        f"未找到 {kind} 的 OpenVINO 模型，请将模型目录挂载到 {models_root}"
    )


def _load_model(kind: str, model_path: Path, classes: list[str] | None):
    path_str = str(model_path)
    is_openvino = model_path.is_dir() or path_str.endswith("_openvino_model")
    if kind == "worldv2" and not is_openvino and path_str.endswith(".pt"):
        model = YOLOWorld(path_str)
        if classes:
            model.set_classes(classes)
        return model
    return YOLO(path_str, task="detect")


def _collect_detections(results, img_w: int, img_h: int) -> list[dict]:
    detections = []
    for r in results:
        boxes = r.boxes
        if boxes is None:
            continue
        names = r.names or {}
        for i in range(len(boxes)):
            cls_id = int(boxes.cls[i])
            en_name = names.get(cls_id, str(cls_id))
            xyxy = [float(x) for x in boxes.xyxy[i].tolist()]
            detections.append({
                "class_id": cls_id,
                "class_name": en_name,
                "class_name_zh": name_to_zh(en_name),
                "confidence": round(float(boxes.conf[i]), 4),
                "xyxy": [round(x, 2) for x in xyxy],
                "image_width": img_w,
                "image_height": img_h,
            })
    return detections


class YoloDetector:
    """缓存已加载模型，避免每次请求重新加载。"""

    def __init__(self, models_dir: str | None = None):
        self.models_root = Path(models_dir or settings.models_dir)
        self._cache: dict[str, object] = {}

    def _get_model(self, kind: str, explicit: str | None) -> tuple[object, Path]:
        key = f"{kind}:{explicit or 'default'}"
        if key not in self._cache:
            path = find_model(kind, self.models_root, explicit)
            self._cache[key] = (_load_model(kind, path, None), path)
        return self._cache[key]

    def detect_file(
        self,
        image_path: Path,
        *,
        model: str = "yolo11",
        device: str | None = None,
        conf: float | None = None,
        yolo11_model: str | None = None,
        worldv2_model: str | None = None,
    ) -> dict:
        from PIL import Image

        device = device or settings.default_device
        conf = conf if conf is not None else settings.default_conf

        with Image.open(image_path) as im:
            img_w, img_h = im.size

        tasks: list[tuple[str, str | None, str]] = []
        if model in ("yolo11", "both"):
            tasks.append(("yolo11", yolo11_model, "yolo11"))
        if model in ("worldv2", "both"):
            tasks.append(("worldv2", worldv2_model, "worldv2"))

        results_raw: list[dict] = []
        for kind, explicit, _ in tasks:
            m, model_path = self._get_model(kind, explicit)
            t0 = time.perf_counter()
            try:
                preds = m.predict(
                    source=str(image_path),
                    device=device,
                    conf=conf,
                    save=False,
                    verbose=False,
                )
            except Exception as e:
                if "GPU" in str(e) or "device" in str(e).lower():
                    preds = m.predict(
                        source=str(image_path),
                        device="cpu",
                        conf=conf,
                        save=False,
                        verbose=False,
                    )
                else:
                    raise e
            elapsed_ms = (time.perf_counter() - t0) * 1000
            dets = _collect_detections(preds, img_w, img_h)
            for d in dets:
                d["model"] = kind
            results_raw.append({
                "model": kind,
                "openvino_dir": str(model_path),
                "device": device,
                "inference_ms": round(elapsed_ms, 2),
                "count": len(dets),
                "detections": dets,
            })

        return {
            "source": str(image_path),
            "image_width": img_w,
            "image_height": img_h,
            "results": results_raw,
        }
