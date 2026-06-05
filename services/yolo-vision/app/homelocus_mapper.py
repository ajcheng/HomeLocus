"""将 YOLO 检测结果映射为 HomeLocus ai_recognition 兼容格式。"""
from __future__ import annotations

from app.category_map import category_for_class, is_chargeable


def _xyxy_to_percent_bbox(xyxy: list[float], img_w: int, img_h: int) -> dict:
    x1, y1, x2, y2 = xyxy
    if img_w <= 0 or img_h <= 0:
        return {"x": 0, "y": 0, "w": 0, "h": 0}
    return {
        "x": round(max(0, x1 / img_w * 100), 2),
        "y": round(max(0, y1 / img_h * 100), 2),
        "w": round(max(0, (x2 - x1) / img_w * 100), 2),
        "h": round(max(0, (y2 - y1) / img_h * 100), 2),
    }


def _iou(a: list[float], b: list[float]) -> float:
    ax1, ay1, ax2, ay2 = a
    bx1, by1, bx2, by2 = b
    inter_x1 = max(ax1, bx1)
    inter_y1 = max(ay1, by1)
    inter_x2 = min(ax2, bx2)
    inter_y2 = min(ay2, by2)
    if inter_x2 <= inter_x1 or inter_y2 <= inter_y1:
        return 0.0
    inter = (inter_x2 - inter_x1) * (inter_y2 - inter_y1)
    area_a = (ax2 - ax1) * (ay2 - ay1)
    area_b = (bx2 - bx1) * (by2 - by1)
    union = area_a + area_b - inter
    return inter / union if union > 0 else 0.0


def _dedupe_detections(detections: list[dict], iou_thresh: float = 0.5) -> list[dict]:
    """多模型结果按 IOU 去重，保留置信度更高者。"""
    sorted_d = sorted(detections, key=lambda x: x["confidence"], reverse=True)
    kept: list[dict] = []
    for d in sorted_d:
        if any(_iou(d["xyxy"], k["xyxy"]) > iou_thresh for k in kept):
            continue
        kept.append(d)
    return kept


def to_homelocus_response(detect_report: dict, *, lang: str = "zh") -> dict:
    """
    输出与 HomeLocus AIRecognitionService.analyze_image 一致的结构：
    { "items": [...], "summary": "...", "provider": "yolo", "raw": {...} }
    """
    img_w = detect_report.get("image_width", 1)
    img_h = detect_report.get("image_height", 1)
    all_dets: list[dict] = []
    for block in detect_report.get("results", []):
        all_dets.extend(block.get("detections", []))

    merged = _dedupe_detections(all_dets)
    items = []
    labels_zh: list[str] = []

    for d in merged:
        en = d["class_name"]
        zh = d["class_name_zh"]
        label = zh if lang == "zh" else en
        labels_zh.append(zh)
        items.append({
            "label": label,
            "label_en": en,
            "label_zh": zh,
            "brand": None,
            "category": category_for_class(en),
            "bounding_box": _xyxy_to_percent_bbox(d["xyxy"], img_w, img_h),
            "is_chargeable": is_chargeable(en),
            "confidence": d["confidence"],
            "class_id": d["class_id"],
            "model": d.get("model", "yolo11"),
        })

    if labels_zh:
        unique = list(dict.fromkeys(labels_zh))
        summary = f"检测到 {len(items)} 个物品：" + "、".join(unique[:8])
        if len(unique) > 8:
            summary += f" 等（共 {len(unique)} 类）"
    else:
        summary = "未检测到明确物品（YOLO OpenVINO）"

    # 中文展示用 detections 列表
    detections_zh = [
        {
            "class_name": d["class_name_zh"],
            "class_name_en": d["class_name"],
            "confidence": d["confidence"],
            "xyxy": d["xyxy"],
            "bounding_box_pct": _xyxy_to_percent_bbox(d["xyxy"], img_w, img_h),
        }
        for d in merged
    ]

    return {
        "items": items,
        "summary": summary,
        "provider": "yolo",
        "lang": lang,
        "detection_count": len(items),
        "detections_zh": detections_zh,
        "raw": detect_report,
    }
