import json
import logging

import httpx
from sqlalchemy import select, or_
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.config import settings
from app.models.space import Slot, Container, Zone, Location
from app.models.item import Item
from app.schemas.speech import ParsedItem, MatchedSlot
from app.schemas import reminder as reminder_schemas
from app.services.search_service import SearchService
from app.services.reminder_service import ReminderService

logger = logging.getLogger(__name__)

PARSE_PROMPT = """Extract structured item information from this Chinese natural language input about home storage.

User input: "{text}"

Return ONLY a JSON object:
{{
  "items": [
    {{
      "label": "Item name (be specific, include brand if mentioned)",
      "brand": "Brand name if mentioned",
      "category": "category",
      "tags": ["tag1", "tag2"],
      "is_chargeable": false,
      "slot_name_hint": "层级/抽屉名称提示",
      "container_name_hint": "储物模块名称提示",
      "zone_name_hint": "分区名称提示"
    }}
  ]
}}

Rules:
- Extract ALL items mentioned
- slot_name_hint: the drawer/layer name (e.g., "第二层抽屉", "左侧挂衣区")
- container_name_hint: the storage unit name (e.g., "大衣柜", "电视柜", "书桌")
- zone_name_hint: the room/area name (e.g., "主卧", "客厅", "书房")
- is_chargeable: true for electronics, battery tools, rechargeable devices
- If no location hints found, leave them as empty strings"""


class SpeechService:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def parse_item_from_text(self, text: str) -> ParsedItem:
        """Use AI to extract structured item info from natural language."""
        if not settings.ai_api_key:
            return self._regex_parse(text)

        try:
            content = await self._llm_parse(PARSE_PROMPT.format(text=text))
            if content:
                data = json.loads(content)
                items = data.get("items", [])
                if items:
                    first = items[0]
                    return ParsedItem(
                        label=first.get("label", text),
                        brand=first.get("brand"),
                        category=first.get("category"),
                        tags=first.get("tags", []),
                        is_chargeable=first.get("is_chargeable", False),
                        slot_name_hint=first.get("slot_name_hint"),
                        container_name_hint=first.get("container_name_hint"),
                        zone_name_hint=first.get("zone_name_hint"),
                    )
        except Exception as e:
            logger.error(f"NLP parsing failed: {e}")

        return self._regex_parse(text)

    async def _llm_parse(self, prompt: str) -> str | None:
        prefer_openai = settings.ai_provider in ("openai", "custom")

        if prefer_openai:
            content = await self._openai_chat(prompt)
            if content:
                return content
            return await self._anthropic_chat(prompt)
        content = await self._anthropic_chat(prompt)
        if content:
            return content
        return await self._openai_chat(prompt)

    async def _openai_chat(self, prompt: str) -> str | None:
        try:
            async with httpx.AsyncClient(timeout=30.0) as client:
                response = await client.post(
                    f"{settings.ai_base_url.rstrip('/')}/v1/chat/completions",
                    headers={
                        "Authorization": f"Bearer {settings.ai_api_key}",
                        "Content-Type": "application/json",
                    },
                    json={
                        "model": settings.ai_model,
                        "max_tokens": 500,
                        "messages": [{"role": "user", "content": prompt}],
                    },
                )
                if response.status_code != 200:
                    return None
                content = response.json()["choices"][0]["message"]["content"].strip()
                return self._strip_code_fence(content)
        except Exception:
            return None

    async def _anthropic_chat(self, prompt: str) -> str | None:
        try:
            async with httpx.AsyncClient(timeout=30.0) as client:
                response = await client.post(
                    f"{settings.ai_base_url.rstrip('/')}/anthropic/v1/messages",
                    headers={
                        "x-api-key": settings.ai_api_key,
                        "anthropic-version": "2023-06-01",
                        "Content-Type": "application/json",
                    },
                    json={
                        "model": settings.ai_model,
                        "max_tokens": 500,
                        "messages": [{"role": "user", "content": prompt}],
                    },
                )
                if response.status_code != 200:
                    return None
                content = response.json()["content"][0]["text"].strip()
                return self._strip_code_fence(content)
        except Exception:
            return None

    @staticmethod
    def _strip_code_fence(content: str) -> str:
        if content.startswith("```"):
            content = content.split("\n", 1)[1].rsplit("\n```", 1)[0]
        return content.strip()

    def _regex_parse(self, text: str) -> ParsedItem:
        """Fallback: simple regex parsing."""
        import re
        item = ParsedItem(label=text)

        # Try: "zone container slot 有/放了 item"
        m = re.match(r'(\S+?)(\S+?)(\S+?)[有放]{1,2}(.+)', text)
        if m:
            item.zone_name_hint = m.group(1)
            item.container_name_hint = m.group(2)
            item.slot_name_hint = m.group(3)
            item.label = m.group(4).strip()

        # Check for chargeable keywords
        charge_keywords = ['充电', '电池', '电子', '手机', '平板', '电脑', '笔记本', '耳机', '相机', '电钻']
        for kw in charge_keywords:
            if kw in text:
                item.is_chargeable = True
                break

        return item

    async def try_match_slot(self, parsed: ParsedItem, location_id: str | None = None) -> MatchedSlot | None:
        stmt = select(Slot).join(Container, Slot.container_id == Container.id).join(Zone, Container.zone_id == Zone.id).options(
            selectinload(Slot.container).selectinload(Container.zone).selectinload(Zone.location)
        )

        # Build fuzzy match conditions
        conditions = []
        if parsed.slot_name_hint:
            conditions.append(Slot.name.ilike(f"%{parsed.slot_name_hint}%"))
        if parsed.container_name_hint:
            conditions.append(Container.name.ilike(f"%{parsed.container_name_hint}%"))
        if parsed.zone_name_hint:
            conditions.append(Zone.name.ilike(f"%{parsed.zone_name_hint}%"))

        if conditions:
            stmt = stmt.where(or_(*conditions))
        if location_id:
            stmt = stmt.where(Zone.location_id == location_id)

        stmt = stmt.limit(1)
        result = await self.db.execute(stmt)
        slot = result.scalar_one_or_none()

        if not slot:
            return None

        c = slot.container
        z = c.zone
        loc = z.location
        return MatchedSlot(
            slot_id=slot.id, slot_name=slot.name,
            container_name=c.name, zone_name=z.name,
            location_name=loc.name,
            breadcrumb=f"{loc.name} / {z.name} / {c.name} / {slot.name}",
        )

    async def add_item_from_speech(self, parsed: ParsedItem, slot_id: str) -> Item:
        item = Item(
            slot_id=slot_id,
            label=parsed.label,
            brand=parsed.brand,
            category=parsed.category,
            tags=parsed.tags,
            is_chargeable=parsed.is_chargeable,
        )
        self.db.add(item)
        await self.db.commit()
        await self.db.refresh(item)
        await SearchService(self.db).index_item_record(item)
        if item.is_chargeable:
            await ReminderService(self.db).complete_charge(
                reminder_schemas.ChargeCompleteRequest(
                    item_id=item.id,
                    next_reminder_days=item.charge_cycle_days or 90,
                )
            )
        return item
