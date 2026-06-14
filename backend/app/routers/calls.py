import logging
from fastapi import APIRouter, HTTPException, Request, Response
from pydantic import BaseModel
from app.core.session_manager import SessionManager
from app.services.telephony import TelephonyService

logger = logging.getLogger(__name__)
router = APIRouter()

_session_manager: SessionManager | None = None
_telephony = TelephonyService()


def set_session_manager(sm: SessionManager):
    global _session_manager
    _session_manager = sm


class InitiateCallRequest(BaseModel):
    session_id: str
    participant_id: str
    phone_number: str
    language: str


@router.post("/initiate")
async def initiate_call(req: InitiateCallRequest):
    if not _session_manager:
        raise HTTPException(status_code=500, detail="Server not initialized")

    session = await _session_manager.get_session(req.session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")

    try:
        result = await _telephony.initiate_call(
            to_number=req.phone_number,
            session_id=req.session_id,
            participant_id=req.participant_id,
            language=req.language,
        )
        return result
    except RuntimeError as e:
        raise HTTPException(status_code=503, detail=str(e))


@router.post("/voice")
async def twilio_voice_webhook(request: Request):
    """Twilio voice webhook — returns TwiML to connect caller to stream."""
    params = dict(request.query_params)
    session_id = params.get("session_id", "")
    participant_id = params.get("participant_id", "")

    twiml = _telephony.generate_twiml_connect(session_id, participant_id)
    return Response(content=twiml, media_type="application/xml")
