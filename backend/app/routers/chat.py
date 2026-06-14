import logging
import os
import uuid
from pathlib import Path

from fastapi import APIRouter, HTTPException, UploadFile, File, Form, Depends
from pydantic import BaseModel

from app.core.database import save_message, get_messages
from app.core.session_manager import SessionManager
from app.services.stt import STTService
from app.services.translation import TranslationService
from app.services.tts import TTSService
from app.models.translation import TranslationContext

logger = logging.getLogger(__name__)
router = APIRouter()

UPLOAD_DIR = Path("/app/uploads")
UPLOAD_DIR.mkdir(parents=True, exist_ok=True)

ALLOWED_MIME = {
    "image/jpeg", "image/png", "image/gif", "image/webp",
    "audio/mpeg", "audio/mp4", "audio/wav", "audio/ogg",
    "audio/webm", "audio/aac", "audio/x-m4a",
    "video/mp4", "video/webm",
    "application/pdf",
    "application/msword",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "application/vnd.ms-excel",
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    "text/plain",
}

MAX_FILE_SIZE = 25 * 1024 * 1024  # 25 MB

_session_manager: SessionManager | None = None


def set_session_manager(sm: SessionManager):
    global _session_manager
    _session_manager = sm


class TextMessageRequest(BaseModel):
    participant_id: str
    participant_name: str
    content: str


@router.get("/{session_id}/messages")
async def list_messages(session_id: str):
    messages = await get_messages(session_id)
    return {"messages": messages}


@router.post("/{session_id}/messages")
async def send_text_message(session_id: str, req: TextMessageRequest):
    msg = await save_message(
        session_id=session_id,
        participant_id=req.participant_id,
        participant_name=req.participant_name,
        message_type="text",
        content=req.content,
    )
    if not msg:
        msg = {
            "id": str(uuid.uuid4()),
            "session_id": session_id,
            "participant_id": req.participant_id,
            "participant_name": req.participant_name,
            "message_type": "text",
            "content": req.content,
            "file_url": None,
            "file_name": None,
            "mime_type": None,
            "duration_ms": None,
        }

    # Broadcast via WebSocket
    sm = _session_manager
    if sm:
        await sm.broadcast_to_session(
            session_id,
            {"type": "chat_message", "data": msg},
        )

    return msg


@router.post("/{session_id}/upload")
async def upload_file(
    session_id: str,
    participant_id: str = Form(...),
    participant_name: str = Form(...),
    message_type: str = Form("image"),  # image | voice | file
    duration_ms: int = Form(None),
    file: UploadFile = File(...),
):
    content_type = file.content_type or "application/octet-stream"
    if content_type not in ALLOWED_MIME:
        raise HTTPException(status_code=415, detail=f"File type not supported: {content_type}")

    data = await file.read()
    if len(data) > MAX_FILE_SIZE:
        raise HTTPException(status_code=413, detail="File too large (max 25 MB)")

    ext = Path(file.filename or "file").suffix or _mime_ext(content_type)
    filename = f"{uuid.uuid4()}{ext}"
    filepath = UPLOAD_DIR / filename
    filepath.write_bytes(data)

    file_url = f"/uploads/{filename}"

    msg = await save_message(
        session_id=session_id,
        participant_id=participant_id,
        participant_name=participant_name,
        message_type=message_type,
        file_url=file_url,
        file_name=file.filename,
        mime_type=content_type,
        duration_ms=duration_ms,
    )
    if not msg:
        msg = {
            "id": str(uuid.uuid4()),
            "session_id": session_id,
            "participant_id": participant_id,
            "participant_name": participant_name,
            "message_type": message_type,
            "content": None,
            "file_url": file_url,
            "file_name": file.filename,
            "mime_type": content_type,
            "duration_ms": duration_ms,
        }

    # Broadcast via WebSocket
    sm = _session_manager
    if sm:
        await sm.broadcast_to_session(
            session_id,
            {"type": "chat_message", "data": msg},
        )

    return msg


# In-memory cache: "{msg_id}:{language}" -> translated_file_url
_voice_translation_cache: dict[str, str] = {}


@router.get("/{session_id}/messages/{msg_id}/audio")
async def get_translated_voice(session_id: str, msg_id: str, language: str):
    cache_key = f"{msg_id}:{language}"
    if cache_key in _voice_translation_cache:
        return {"audio_url": _voice_translation_cache[cache_key]}

    messages = await get_messages(session_id)
    msg = next((m for m in messages if m["id"] == msg_id), None)
    if not msg or msg["message_type"] != "voice":
        raise HTTPException(status_code=404, detail="Voice message not found")

    file_path = UPLOAD_DIR / Path(msg["file_url"]).name
    if not file_path.exists():
        raise HTTPException(status_code=404, detail="Audio file not found")
    audio_bytes = file_path.read_bytes()

    stt = STTService()
    transcript = await stt.transcribe(audio_bytes, is_pcm=False)
    source_lang = (getattr(transcript, "language", None) or "en").split("-")[0]

    if source_lang == language:
        return {"audio_url": msg["file_url"]}

    context = TranslationContext(
        source_language=source_lang,
        target_language=language,
        domain="general",
    )
    result = await TranslationService().translate(
        transcript.text, context, speaker_name=msg.get("participant_name", "")
    )

    tts_result = await TTSService().synthesize(result.translated_text, language=language)

    out_filename = f"translated_{msg_id}_{language}.mp3"
    (UPLOAD_DIR / out_filename).write_bytes(tts_result.audio_bytes)
    translated_url = f"/uploads/{out_filename}"
    _voice_translation_cache[cache_key] = translated_url

    return {"audio_url": translated_url}


def _mime_ext(mime: str) -> str:
    return {
        "image/jpeg": ".jpg",
        "image/png": ".png",
        "image/gif": ".gif",
        "image/webp": ".webp",
        "audio/mpeg": ".mp3",
        "audio/mp4": ".m4a",
        "audio/wav": ".wav",
        "audio/ogg": ".ogg",
        "audio/webm": ".webm",
        "audio/aac": ".aac",
        "audio/x-m4a": ".m4a",
        "video/mp4": ".mp4",
        "application/pdf": ".pdf",
    }.get(mime, ".bin")
