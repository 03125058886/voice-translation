import asyncio
import json
import logging
import uuid as uuid_lib
from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Query
from app.core.lobby_manager import lobby_manager, OnlineUser
from app.core.session_manager import SessionManager
from app.models.session import Session, Participant, SessionStatus

logger = logging.getLogger(__name__)
router = APIRouter()

_session_manager: SessionManager | None = None


def set_session_manager(sm: SessionManager):
    global _session_manager
    _session_manager = sm


@router.get("/users/online")
async def get_online_users():
    return {"users": lobby_manager.online_users()}


@router.websocket("/ws/lobby")
async def lobby_websocket(
    websocket: WebSocket,
    name: str = Query(...),
    language: str = Query("en"),
    user_id: str = Query(None),
):
    await websocket.accept()

    if not user_id:
        user_id = str(uuid_lib.uuid4())

    user = OnlineUser(
        user_id=user_id,
        name=name,
        language=language,
        websocket=websocket,
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

                # Create a session for this direct call
                sm = _session_manager
                if not sm:
                    continue

                participant = Participant(
                    name=user.name,
                    language=user.language,
                )
                session = Session(
                    name=f"Call: {user.name}",
                    domain="general",
                )
                session = await sm.create_session(session)
                session = await sm.add_participant(session.id, participant)

                # Notify target user
                sent = await lobby_manager.send_to(target_id, {
                    "type": "incoming_call",
                    "data": {
                        "caller_id": user_id,
                        "caller_name": user.name,
                        "caller_language": user.language,
                        "session_id": session.id,
                    },
                })

                # Tell caller the session was created
                await websocket.send_json({
                    "type": "call_initiated",
                    "data": {
                        "session_id": session.id,
                        "participant_id": participant.id,
                        "target_user_id": target_id,
                        "target_found": sent,
                    },
                })

            elif msg_type == "call_rejected":
                # Notify caller their call was rejected
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
