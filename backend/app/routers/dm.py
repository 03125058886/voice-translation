from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from app.core.database import save_direct_message, get_direct_messages, get_conversations

router = APIRouter()


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
    return msg


@router.get("/conversation")
async def get_conversation(me: str, other: str):
    if not me or not other:
        raise HTTPException(status_code=400, detail="me and other are required")
    return {"messages": await get_direct_messages(me, other)}


@router.get("/conversations/{phone}")
async def list_conversations(phone: str):
    return {"conversations": await get_conversations(phone)}
