import os
import uuid
import tempfile

from fastapi import APIRouter, Depends, UploadFile, File, Form, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.schemas import speech as schemas
from app.services.speech_service import SpeechService

router = APIRouter()


def get_speech_service(db: AsyncSession = Depends(get_db)) -> SpeechService:
    return SpeechService(db)


@router.post("/add-item", response_model=schemas.SpeechAddItemResponse)
async def speech_add_item(
    audio: UploadFile = File(...),
    location_id: str = Form(...),
    svc: SpeechService = Depends(get_speech_service),
):
    # Save uploaded audio to temp file
    suffix = os.path.splitext(audio.filename or "recording.wav")[1] or ".wav"
    with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
        content = await audio.read()
        tmp.write(content)
        tmp_path = tmp.name

    try:
        # Step 1: ASR - Speech to text
        transcription = await svc.transcribe(tmp_path)

        if not transcription:
            return schemas.SpeechAddItemResponse(
                transcription="",
                needs_confirmation=True,
            )

        # Step 2: NLP - Parse item info from text
        parsed = await svc.parse_item_from_text(transcription)

        # Step 3: Match to nearest slot in space topology
        matched = await svc.try_match_slot(parsed, location_id)

        return schemas.SpeechAddItemResponse(
            transcription=transcription,
            parsed_item=parsed,
            matched_slot=matched,
            needs_confirmation=True,
        )
    finally:
        os.unlink(tmp_path)


@router.post("/add-item/confirm")
async def confirm_speech_item(
    data: schemas.ConfirmedSpeechItem,
    svc: SpeechService = Depends(get_speech_service),
):
    item = await svc.add_item_from_speech(data.parsed_item, data.slot_id)
    return {
        "item_id": item.id,
        "label": item.label,
        "status": "created",
    }
