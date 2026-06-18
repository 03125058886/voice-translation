import uuid
from pathlib import Path

from fastapi import APIRouter, HTTPException, UploadFile, File, Form
from pydantic import BaseModel
from app.core.database import save_direct_message, get_direct_messages, get_conversations, get_user
from app.services.fcm_service import send_dm_notification
from app.utils.phone import normalize_phone
from app.routers.chat import UPLOAD_DIR, ALLOWED_MIME, MAX_FILE_SIZE, _mime_ext

router = APIRouter()


async def _push_dm_notification(receiver_phone: str, sender_phone: str, preview: str) -> None:
    receiver = await get_user(normalize_phone(receiver_phone))
    if not receiver or not receiver.get("fcm_token"):
        return
    sender = await get_user(normalize_phone(sender_phone))
    sender_name = (sender or {}).get("name") or sender_phone
    await send_dm_notification(
        fcm_token=receiver["fcm_token"],
        sender_name=sender_name,
        sender_phone=normalize_phone(sender_phone),
        preview=preview,
    )



class SendMessageRequest(BaseModel):
    sender_phone: str
    receiver_phone: str
    content: str


@router.post("/send")
async def send_message(req: SendMessageRequest):
    if not req.content.strip():
        raise HTTPException(status_code=400, detail="Message cannot be empty")
    msg = await save_direct_message(req.sender_phone, req.receiver_phone, req.content.strip())
    if not msg:
        raise HTTPException(status_code=503, detail="Database unavailable")
    await _push_dm_notification(req.receiver_phone, req.sender_phone, req.content.strip())
    return msg


@router.post("/upload")
async def upload_dm_file(
    sender_phone: str = Form(...),
    receiver_phone: str = Form(...),
    message_type: str = Form("voice"),  # voice | image | file
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
    (UPLOAD_DIR / filename).write_bytes(data)

    msg = await save_direct_message(
        sender_phone,
        receiver_phone,
        message_type=message_type,
        file_url=f"/uploads/{filename}",
        file_name=file.filename,
        mime_type=content_type,
        duration_ms=duration_ms,
    )
    if not msg:
        raise HTTPException(status_code=503, detail="Database unavailable")
    preview = "📷 Photo" if message_type == "image" else "🎤 Voice message" if message_type == "voice" else "📎 File"
    await _push_dm_notification(receiver_phone, sender_phone, preview)
    return msg


@router.get("/conversation")
async def get_conversation(me: str, other: str):
    if not me or not other:
        raise HTTPException(status_code=400, detail="me and other are required")
    return {"messages": await get_direct_messages(me, other)}


@router.get("/conversations/{phone}")
async def list_conversations(phone: str):
    return {"conversations": await get_conversations(phone)}
