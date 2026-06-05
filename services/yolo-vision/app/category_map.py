"""COCO 类名 → HomeLocus category / 是否需充电提醒。"""
from __future__ import annotations

# 英文类名（小写）→ HomeLocus category
COCO_TO_CATEGORY: dict[str, str] = {
    "laptop": "electronics",
    "cell phone": "electronics",
    "tv": "electronics",
    "remote": "electronics",
    "keyboard": "electronics",
    "mouse": "electronics",
    "microwave": "electronics",
    "oven": "electronics",
    "toaster": "electronics",
    "refrigerator": "electronics",
    "hair drier": "electronics",
    "clock": "electronics",
    "book": "documents",
    "scissors": "tools",
    "knife": "tools",
    "bottle": "daily",
    "cup": "daily",
    "bowl": "daily",
    "wine glass": "daily",
    "backpack": "clothing",
    "handbag": "clothing",
    "suitcase": "clothing",
    "tie": "clothing",
    "chair": "furniture",
    "couch": "furniture",
    "bed": "furniture",
    "dining table": "furniture",
    "potted plant": "other",
    "teddy bear": "other",
    "vase": "other",
}

CHARGEABLE_CLASSES: frozenset[str] = frozenset({
    "laptop",
    "cell phone",
    "mouse",
    "keyboard",
    "remote",
    "hair drier",
    "toothbrush",
})


def category_for_class(class_name_en: str) -> str:
    return COCO_TO_CATEGORY.get(class_name_en.strip().lower(), "other")


def is_chargeable(class_name_en: str) -> bool:
    return class_name_en.strip().lower() in CHARGEABLE_CLASSES
