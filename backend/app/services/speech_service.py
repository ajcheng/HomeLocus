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

logger = logging.getLogger(__name__)


class SpeechService:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def transcribe(self, audio_path: str) -> str:
        """
        Speech-to-text using DeepSeek API or local whisper.
        """
        # TODO: Implement ASR with OpenAI Whisper API or DeepSeek audio endpoint
        # For now, placeholder
        return ""

    async def parse_item_from_text(self, text: str) -> ParsedItem:
        """
        Use LLM to extract structured item info from natural language.
        Examples:
        - "主卧大衣柜第二层放了罗技MX Master 3鼠标"
        - "书房的五斗柜第一层有发票"
        """
        # Fallback regex-based parsing (placeholder until LLM integration)
        return ParsedItem(label=text)

    async def try_match_slot(self, parsed: ParsedItem, location_id: str | None = None) -> MatchedSlot | None:
        """
        Try to find the closest matching slot from parsed hints.
        """
        stmt = select(Slot).options(
            selectinload(Slot.container).selectinload(Container.zone).selectinload(Zone.location)
        )

        if parsed.slot_name_hint or parsed.container_name_hint:
            conditions = []
            if parsed.slot_name_hint:
                conditions.append(Slot.name.ilike(f"%{parsed.slot_name_hint}%"))
            if parsed.container_name_hint:
                conditions.append(Container.name.ilike(f"%{parsed.container_name_hint}%"))
            # Join chain
            stmt = (
                select(Slot)
                .join(Container, Slot.container_id == Container.id)
                .join(Zone, Container.zone_id == Zone.id)
                .options(
                    selectinload(Slot.container).selectinload(Container.zone).selectinload(Zone.location)
                )
                .where(or_(*conditions))
            )

        if location_id:
            stmt = stmt.where(Zone.location_id == location_id)

        stmt = stmt.limit(1)
        result = await self.db.execute(stmt)
        slot = result.scalar_one_or_none()

        if not slot:
            return None

        container = slot.container
        zone = container.zone
        location = zone.location

        return MatchedSlot(
            slot_id=slot.id,
            slot_name=slot.name,
            container_name=container.name,
            zone_name=zone.name,
            location_name=location.name,
            breadcrumb=f"{location.name} / {zone.name} / {container.name} / {slot.name}",
        )

    async def add_item_from_speech(self, parsed: ParsedItem, slot_id: str) -> Item:
        """
        Create an item record from speech-parsed data.
        """
        item = Item(
            slot_id=slot_id,
            label=parsed.label,
            brand=parsed.brand,
            tags=parsed.tags,
            is_chargeable=parsed.is_chargeable,
        )
        self.db.add(item)
        await self.db.commit()
        await self.db.refresh(item)
        return item
