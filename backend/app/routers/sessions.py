import logging
from fastapi import APIRouter, HTTPException, Depends
from app.core.session_manager import SessionManager
from app.models.session import (
    Session, Participant, SessionStatus, ParticipantStatus,
    CreateSessionRequest, JoinSessionRequest, SessionResponse,
)

logger = logging.getLogger(__name__)
router = APIRouter()

_session_manager: SessionManager | None = None


def set_session_manager(sm: SessionManager):
    global _session_manager
    _session_manager = sm


def get_sm() -> SessionManager:
    if not _session_manager:
        raise HTTPException(status_code=500, detail="Server not initialized")
    return _session_manager


@router.post("", response_model=SessionResponse)
async def create_session(
    req: CreateSessionRequest,
    sm: SessionManager = Depends(get_sm),
):
    participant = Participant(
        name=req.participant_name,
        language=req.participant_language,
        phone_number=req.caller_phone,
    )
    allowed = []
    if req.caller_phone and req.target_phone:
        allowed = [req.caller_phone, req.target_phone]

    session = Session(
        name=req.name or f"Session {req.participant_name}",
        domain=req.domain,
        allowed_phones=allowed,
    )
    session = await sm.create_session(session)
    session = await sm.add_participant(session.id, participant)

    logger.info(f"Session created: {session.id} by {participant.name}")
    return SessionResponse(
        session_id=session.id,
        participant_id=participant.id,
        session=session,
    )


@router.post("/{session_id}/join", response_model=SessionResponse)
async def join_session(
    session_id: str,
    req: JoinSessionRequest,
    sm: SessionManager = Depends(get_sm),
):
    session = await sm.get_session(session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    if session.status == SessionStatus.ENDED:
        raise HTTPException(status_code=400, detail="Session has ended")

    # Private session — verify phone is allowed
    if session.allowed_phones and req.phone:
        if req.phone not in session.allowed_phones:
            raise HTTPException(status_code=403, detail="Not authorized to join this session")

    # Count only non-disconnected participants so a dropped host doesn't block the slot
    active_count = sum(
        1 for p in session.participants
        if p.status != ParticipantStatus.DISCONNECTED
    )
    if active_count >= 2:
        raise HTTPException(status_code=400, detail="Session is full")

    participant = Participant(
        name=req.participant_name,
        language=req.participant_language,
        phone_number=req.phone,
    )
    session = await sm.add_participant(session_id, participant)

    logger.info(f"Participant {participant.name} joined session {session_id}")
    return SessionResponse(
        session_id=session_id,
        participant_id=participant.id,
        session=session,
    )


@router.get("/{session_id}", response_model=Session)
async def get_session(
    session_id: str,
    sm: SessionManager = Depends(get_sm),
):
    session = await sm.get_session(session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    return session


@router.get("", response_model=list[Session])
async def list_sessions(sm: SessionManager = Depends(get_sm)):
    return await sm.list_active_sessions()


@router.delete("/{session_id}")
async def end_session(
    session_id: str,
    sm: SessionManager = Depends(get_sm),
):
    session = await sm.get_session(session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")

    session.status = SessionStatus.ENDED
    await sm.update_session(session)
    return {"message": "Session ended"}


@router.get("/{session_id}/transcript")
async def get_transcript(
    session_id: str,
    sm: SessionManager = Depends(get_sm),
):
    session = await sm.get_session(session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    return {"transcript": session.transcript}
