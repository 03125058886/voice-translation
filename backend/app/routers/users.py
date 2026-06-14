import logging
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from app.core.database import upsert_user, get_user, set_user_online, update_fcm_token

logger = logging.getLogger(__name__)
router = APIRouter()


class RegisterRequest(BaseModel):
    phone: str
    name: str
    language: str
    fcm_token: str | None = None


class FcmTokenRequest(BaseModel):
    fcm_token: str


@router.post("/register")
async def register_user(req: RegisterRequest):
    user = await upsert_user(
        phone=req.phone,
        name=req.name,
        language=req.language,
        fcm_token=req.fcm_token,
    )
    if not user:
        # DB unavailable — return optimistic response
        return {
            "phone": req.phone,
            "name": req.name,
            "language": req.language,
            "is_online": True,
        }
    return {
        "phone": str(user["phone"]),
        "name": str(user["name"]),
        "language": str(user["language"]),
        "is_online": bool(user["is_online"]),
    }


@router.get("/by-phone/{phone:path}")
async def find_user(phone: str):
    user = await get_user(phone)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return {
        "phone": str(user["phone"]),
        "name": str(user["name"]),
        "language": str(user["language"]),
        "is_online": bool(user["is_online"]),
    }


@router.post("/{phone:path}/online")
async def mark_online(phone: str):
    await set_user_online(phone, True)
    return {"status": "online"}


@router.post("/{phone:path}/offline")
async def mark_offline(phone: str):
    await set_user_online(phone, False)
    return {"status": "offline"}


@router.put("/{phone:path}/fcm")
async def update_token(phone: str, req: FcmTokenRequest):
    await update_fcm_token(phone, req.fcm_token)
    return {"status": "updated"}
