"""常见物品俗称/同义词，用于搜索扩展与入库时自动打标。"""

# 同一组内任意词匹配时，展开为整组检索词
SYNONYM_GROUPS: list[frozenset[str]] = [
    frozenset({"充电器", "充电头", "电源适配器", "适配器", "充电线", "电源线", "快充头", "插头"}),
    frozenset({"充电宝", "移动电源", "便携电源"}),
    frozenset({"鼠标", "无线鼠标", "有线鼠标"}),
    frozenset({"键盘", "机械键盘", "无线键盘"}),
    frozenset({"耳机", "蓝牙耳机", "耳塞", "耳麦"}),
    frozenset({"遥控器", "遥控", "电视遥控"}),
    frozenset({"螺丝刀", "改锥", "起子"}),
    frozenset({"雨伞", "伞", "折叠伞"}),
    frozenset({"保温杯", "水杯", "杯子", "马克杯"}),
    frozenset({"药品", "药", "感冒药", "止痛药"}),
]


def _normalize(term: str) -> str:
    return term.strip().lower()


def expand_search_terms(query: str) -> list[str]:
    """将查询词扩展为同义词集合（含原词），用于 OR 检索。"""
    q = query.strip()
    if not q:
        return []
    terms: set[str] = {q}
    qn = _normalize(q)
    for group in SYNONYM_GROUPS:
        normalized = {_normalize(w) for w in group}
        if any(qn in w or w in qn for w in normalized):
            terms.update(group)
    return list(terms)


def search_tags_for_item(
    label: str,
    brand: str | None = None,
    category: str | None = None,
    existing_tags: list[str] | None = None,
) -> list[str]:
    """入库时生成便于检索的标签（含俗称同义词）。"""
    tags: list[str] = []
    seen: set[str] = set()

    def add(t: str | None) -> None:
        if not t:
            return
        t = t.strip()
        if len(t) < 2 or t in seen:
            return
        seen.add(t)
        tags.append(t)

    for t in existing_tags or []:
        add(t)
    add(label)
    add(brand)
    add(category)

    ln = _normalize(label)
    for group in SYNONYM_GROUPS:
        normalized = {_normalize(w) for w in group}
        if any(ln in w or w in ln for w in normalized):
            for w in group:
                add(w)

    return tags[:12]
