import json
import logging
import os

import httpx
from sqlalchemy import select, or_
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.config import settings
from app.models.space import Slot, Container, Zone, Location
from app.models.item import Item
from app.schemas.speech import ParsedItem, MatchedSlot
from app.utils.voice_parser import parse_voice_text
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

    async def transcribe(self, audio_path: str) -> str:
        """Speech-to-text via ASR gateway (Qwen3-ASR)，与 app_local 一致。"""
        gateway = (settings.asr_gateway_url or "").rstrip("/")
        if gateway:
            mime = "audio/wav"
            if audio_path.endswith(".m4a"):
                mime = "audio/mp4"
            elif audio_path.endswith(".mp3"):
                mime = "audio/mpeg"
            elif audio_path.endswith(".ogg"):
                mime = "audio/ogg"
            headers = {}
            if settings.asr_gateway_api_key:
                headers["Authorization"] = f"Bearer {settings.asr_gateway_api_key}"
            try:
                async with httpx.AsyncClient(timeout=120.0) as client:
                    with open(audio_path, "rb") as audio_file:
                        response = await client.post(
                            f"{gateway}/transcribe",
                            files={"file": (os.path.basename(audio_path), audio_file, mime)},
                            data={"language": settings.asr_language or "Chinese"},
                            headers=headers,
                        )
                    if response.status_code != 200:
                        logger.error("ASR gateway HTTP %s: %s", response.status_code, response.text[:300])
                        return ""
                    payload = response.json()
                    text = (payload.get("text") or "").strip()
                    if text:
                        logger.info("ASR gateway transcription: %s...", text[:80])
                    return text
            except Exception as e:
                logger.error("ASR gateway failed: %s", e)
                return ""

        if not settings.ai_api_key:
            logger.warning("ASR skipped: no ASR_GATEWAY_URL and no AI_API_KEY")
            return ""

        mime = "audio/wav"
        if audio_path.endswith(".m4a"):
            mime = "audio/mp4"
        try:
            async with httpx.AsyncClient(timeout=90.0) as client:
                with open(audio_path, "rb") as audio_file:
                    response = await client.post(
                        f"{settings.ai_base_url.rstrip('/')}/v1/audio/transcriptions",
                        headers={"Authorization": f"Bearer {settings.ai_api_key}"},
                        files={"file": (os.path.basename(audio_path), audio_file, mime)},
                        data={"model": settings.asr_model, "language": "zh"},
                    )
                if response.status_code != 200:
                    return ""
                return (response.json().get("text") or "").strip()
        except Exception as e:
            logger.error("Whisper ASR failed: %s", e)
            return ""

    async def parse_item_from_text(self, text: str) -> ParsedItem:
        """优先使用本地规则解析（与 app_local 一致），再尝试 LLM 补充位置提示。"""
        parsed_local = parse_voice_text(text)
        item = ParsedItem(
            label=parsed_local.label or text,
            color=parsed_local.color,
            tags=parsed_local.tags or [],
            raw_recognition=text,
        )

        if not settings.ai_api_key:
            regex_item = self._regex_parse(text)
            item.slot_name_hint = regex_item.slot_name_hint
            item.container_name_hint = regex_item.container_name_hint
            item.zone_name_hint = regex_item.zone_name_hint
            item.is_chargeable = regex_item.is_chargeable
            return item

        try:
            content = await self._llm_parse(PARSE_PROMPT.format(text=text))
            if content:
                data = json.loads(content)
                items = data.get("items", [])
                if items:
                    first = items[0]
                    merged_tags = list(dict.fromkeys((parsed_local.tags or []) + first.get("tags", [])))
                    return ParsedItem(
                        label=parsed_local.label or first.get("label", text),
                        brand=first.get("brand"),
                        category=first.get("category"),
                        color=parsed_local.color,
                        tags=merged_tags,
                        raw_recognition=text,
                        is_chargeable=first.get("is_chargeable", False),
                        slot_name_hint=first.get("slot_name_hint"),
                        container_name_hint=first.get("container_name_hint"),
                        zone_name_hint=first.get("zone_name_hint"),
                    )
        except Exception as e:
            logger.error(f"NLP parsing failed: {e}")

        regex_item = self._regex_parse(text)
        item.slot_name_hint = regex_item.slot_name_hint
        item.container_name_hint = regex_item.container_name_hint
        item.zone_name_hint = regex_item.zone_name_hint
        item.is_chargeable = regex_item.is_chargeable
        return item

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

    async def add_item_from_speech(self, parsed: ParsedItem, slot_id: str, transcription: str = "") -> Item:
        item = Item(
            is_confirmed=True,
            slot_id=slot_id,
            label=parsed.label,
            brand=parsed.brand,
            category=parsed.category,
            color=parsed.color,
            purpose=getattr(parsed, "purpose", None),
            tags=parsed.tags,
            raw_recognition=parsed.raw_recognition or transcription or parsed.label,
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
