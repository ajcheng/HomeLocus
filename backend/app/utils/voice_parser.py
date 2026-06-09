import re
from dataclasses import dataclass


@dataclass
class VoiceParseResult:
    label: str
    color: str | None = None
    tags: list[str] | None = None


COLOR_MAP = {
    "红色": "红",
    "绿色": "绿",
    "蓝色": "蓝",
    "黑色": "黑",
    "白色": "白",
    "黄色": "黄",
    "粉色": "粉",
    "紫色": "紫",
    "灰色": "灰",
    "棕色": "棕",
    "橙色": "橙",
}


def parse_voice_text(text: str) -> VoiceParseResult:
    raw = (text or "").strip()
    if not raw:
        return VoiceParseResult(label="")

    color: str | None = None
    tags: set[str] = set()

    for full, short in COLOR_MAP.items():
        if full in raw or short in raw:
            color = full
            tags.update({full, short})
            break

    de_parts = [p.strip() for p in raw.split("的") if p.strip()]
    label = de_parts[-1] if de_parts else raw
    label = re.sub(r"^(有一?件?|有一?个?)", "", label).strip()

    color_item = re.match(r"(.+色)的(.+)", label)
    if color_item:
        color = color or color_item.group(1)
        label = color_item.group(2).strip()
    elif color and label.startswith(color):
        label = label[len(color) :].lstrip("的").strip()

    if not label:
        label = raw

    tags.add(label)
    for part in de_parts:
        if part and len(part) <= 12:
            tags.add(part)

    for m in re.finditer(r"[\u4e00-\u9fff]{2,6}", raw):
        word = m.group(0)
        if word not in {"有一件", "有一个", "一件", "一个"}:
            tags.add(word)

    clean_tags = [t for t in tags if len(t) >= 2][:8]
    return VoiceParseResult(
        label=label[:50],
        color=color,
        tags=clean_tags,
    )
