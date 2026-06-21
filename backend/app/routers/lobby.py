import asyncio
import json
import logging
import uuid as uuid_lib
from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Query
from app.core.lobby_manager import lobby_manager, OnlineUser
from app.core.session_manager import SessionManager
from app.models.session import Session, Participant, SessionStatus
from app.core.database import get_user
from app.services.fcm_service import send_incoming_call
from app.utils.phone import normalize_phone

logger = logging.getLogger(__name__)
router = APIRouter()

_session_manager: SessionManager | None = None


def set_session_manager(sm: SessionManager):
    global _session_manager
    _session_manager = sm


async def _push_incoming_call(
    phone: str,
    *,
    caller_name: str,
    caller_language: str,
    caller_id: str,
    session_id: str,
) -> bool:
    """Send FCM push for an incoming call when the callee may be offline."""
    if not phone:
        return False
    db_user = await get_user(normalize_phone(phone))
    if not db_user or not db_user.get("fcm_token"):
        return False
    return await send_incoming_call(
        fcm_token=db_user["fcm_token"],
        caller_name=caller_name,
        caller_language=caller_language,
        caller_id=caller_id,
        session_id=session_id,
    )


@router.get("/users/online")
async def get_online_users():
    return {"users": lobby_manager.online_users()}


@router.websocket("/ws/lobby")
async def lobby_websocket(
    websocket: WebSocket,
    name: str = Query(...),
    language: str = Query("en"),
    user_id: str = Query(None),
    phone: str = Query(""),
):
    await websocket.accept()

    if not user_id:
        user_id = str(uuid_lib.uuid4())

    user = OnlineUser(
        user_id=user_id,
        name=name,
        language=language,
        websocket=websocket,
        phone=phone,
    )
    lobby_manager.register(user)

    # Announce arrival to everyone else
    await lobby_manager.broadcast(
        {"type": "user_online", "data": user.to_dict()},
        exclude=user_id,
    )

    # Send current online list to the new user
    await websocket.send_json({
        "type": "online_list",
        "data": {
            "users": lobby_manager.online_users(),
            "your_id": user_id,
        },
    })

    try:
        while True:
            raw = await websocket.receive_text()
            try:
                msg = json.loads(raw)
            except json.JSONDecodeError:
                continue

            msg_type = msg.get("type")
            data = msg.get("data", {})

            if msg_type == "ping":
                await websocket.send_json({"type": "pong"})

            elif msg_type == "call_user":
                target_id = data.get("target_user_id")
                if not target_id or target_id == user_id:
                    continue

                caller_language = data.get("caller_language") or user.language
                user.language = caller_language

                # Create a session for this direct call
                sm = _session_manager
                if not sm:
                    continue

                participant = Participant(
                    name=user.name,
                    language=caller_language,
                )
                session = Session(
                    name=f"Call: {user.name}",
                    domain="general",
                )
                session = await sm.create_session(session)
                session = await sm.add_participant(session.id, participant)

                # Notify target user via WebSocket (+ FCM when app is backgrounded/killed)
                sent = await lobby_manager.send_to(target_id, {
                    "type": "incoming_call",
                    "data": {
                        "caller_id": user_id,
                        "caller_name": user.name,
                        "caller_language": user.language,
                        "session_id": session.id,
                    },
                })
                target = lobby_manager.get_user(target_id)
                fcm_sent = False
                if target and target.phone:
                    fcm_sent = await _push_incoming_call(
                        target.phone,
                        caller_name=user.name,
                        caller_language=user.language,
                        caller_id=user_id,
                        session_id=session.id,
                    )

                # Tell caller the session was created
                await websocket.send_json({
                    "type": "call_initiated",
                    "data": {
                        "session_id": session.id,
                        "participant_id": participant.id,
                        "target_user_id": target_id,
                        "target_found": sent or fcm_sent,
                    },
                })

            elif msg_type == "call_by_phone":
                target_phone = normalize_phone(data.get("target_phone", ""))
                sm = _session_manager
                if not target_phone or not sm:
                    await websocket.send_json({
                        "type": "call_initiated",
                        "data": {"target_found": False, "session_id": "", "participant_id": "", "target_user_id": ""},
                    })
                    continue

                caller_language = data.get("caller_language") or user.language
                user.language = caller_language

                # Create session first
                participant = Participant(name=user.name, language=caller_language)
                session = Session(name=f"Call: {user.name}", domain="general")
                session = await sm.create_session(session)
                session = await sm.add_participant(session.id, participant)

                target = lobby_manager.get_user_by_phone(target_phone)
                target_found = False

                if target:
                    # User is online in lobby — WebSocket + FCM backup (app backgrounded)
                    sent = await lobby_manager.send_to(target.user_id, {
                        "type": "incoming_call",
                        "data": {
                            "caller_id": user_id,
                            "caller_name": user.name,
                            "caller_language": user.language,
                            "session_id": session.id,
                        },
                    })
                    fcm_sent = await _push_incoming_call(
                        target_phone,
                        caller_name=user.name,
                        caller_language=user.language,
                        caller_id=user_id,
                        session_id=session.id,
                    )
                    target_found = sent or fcm_sent
                else:
                    # User offline — FCM push notification
                    target_found = await _push_incoming_call(
                        target_phone,
                        caller_name=user.name,
                        caller_language=user.language,
                        caller_id=user_id,
                        session_id=session.id,
                    )

                await websocket.send_json({
                    "type": "call_initiated",
                    "data": {
                        "session_id": session.id,
                        "participant_id": participant.id,
                        "target_user_id": target.user_id if target else "",
                        "target_found": target_found,
                    },
                })

            elif msg_type == "call_rejected":
                caller_id = data.get("caller_id")
                if caller_id:
                    await lobby_manager.send_to(caller_id, {
                        "type": "call_rejected",
                        "data": {"by_name": user.name},
                    })

    except WebSocketDisconnect:
        pass
    except Exception as e:
        logger.error(f"Lobby WS error for {user_id}: {e}")
    finally:
        lobby_manager.unregister(user_id)
        await lobby_manager.broadcast(
            {"type": "user_offline", "data": {"user_id": user_id}},
        )
