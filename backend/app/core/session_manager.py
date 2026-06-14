import asyncio
import json
import logging
from datetime import datetime
from typing import Dict, Optional
from fastapi import WebSocket

import redis.asyncio as aioredis

from app.config import settings
from app.models.session import (
    Session, Participant, SessionStatus, ParticipantStatus, TranscriptEntry,
)

logger = logging.getLogger(__name__)


class ConnectionManager:
    """Manages active WebSocket connections."""

    def __init__(self):
        self._connections: Dict[str, WebSocket] = {}

    async def connect(self, ws_id: str, websocket: WebSocket):
        await websocket.accept()
        self._connections[ws_id] = websocket
        logger.info(f"WS connected: {ws_id}")

    def disconnect(self, ws_id: str):
        self._connections.pop(ws_id, None)
        logger.info(f"WS disconnected: {ws_id}")

    async def send_json(self, ws_id: str, data: dict) -> bool:
        ws = self._connections.get(ws_id)
        if not ws:
            return False
        try:
            await ws.send_json(data)
            return True
        except Exception as e:
            logger.warning(f"Failed to send to {ws_id}: {e}")
            self.disconnect(ws_id)
            return False

    async def send_bytes(self, ws_id: str, data: bytes) -> bool:
        ws = self._connections.get(ws_id)
        if not ws:
            return False
        try:
            await ws.send_bytes(data)
            return True
        except Exception as e:
            logger.warning(f"Failed to send bytes to {ws_id}: {e}")
            self.disconnect(ws_id)
            return False

    def is_connected(self, ws_id: str) -> bool:
        return ws_id in self._connections


class SessionManager:
    def __init__(self):
        self._redis: Optional[aioredis.Redis] = None
        self._local_sessions: Dict[str, Session] = {}
        self.connections = ConnectionManager()

    async def initialize(self):
        try:
            self._redis = aioredis.from_url(
                settings.REDIS_URL,
                encoding="utf-8",
                decode_responses=True,
            )
            await self._redis.ping()
            logger.info("Redis connected")
        except Exception as e:
            logger.warning(f"Redis unavailable, using in-memory: {e}")
            self._redis = None

    async def cleanup(self):
        if self._redis:
            await self._redis.aclose()

    # --- Session CRUD ---

    async def create_session(self, session: Session) -> Session:
        await self._save_session(session)
        return session

    async def get_session(self, session_id: str) -> Optional[Session]:
        if self._redis:
            data = await self._redis.get(f"session:{session_id}")
            if data:
                return Session.model_validate_json(data)
        return self._local_sessions.get(session_id)

    async def update_session(self, session: Session):
        await self._save_session(session)

    async def delete_session(self, session_id: str):
        if self._redis:
            await self._redis.delete(f"session:{session_id}")
        self._local_sessions.pop(session_id, None)

    async def _save_session(self, session: Session):
        data = session.model_dump_json()
        if self._redis:
            await self._redis.setex(
                f"session:{session.id}",
                settings.REDIS_SESSION_TTL,
                data,
            )
        else:
            self._local_sessions[session.id] = session

    async def list_active_sessions(self) -> list[Session]:
        def _is_active(s: Session) -> bool:
            if s.status == SessionStatus.ENDED:
                return False
            # Only show sessions that have at least one connected participant
            return any(
                p.status != ParticipantStatus.DISCONNECTED for p in s.participants
            ) if s.participants else False

        if self._redis:
            keys = await self._redis.keys("session:*")
            sessions = []
            for key in keys:
                data = await self._redis.get(key)
                if data:
                    try:
                        s = Session.model_validate_json(data)
                        if _is_active(s):
                            sessions.append(s)
                    except Exception:
                        pass
            return sessions
        return [s for s in self._local_sessions.values() if _is_active(s)]

    # --- Participant helpers ---

    async def add_participant(self, session_id: str, participant: Participant) -> Session:
        session = await self.get_session(session_id)
        if not session:
            raise ValueError(f"Session {session_id} not found")

        participant.joined_at = datetime.utcnow()
        participant.status = ParticipantStatus.CONNECTED
        session.participants.append(participant)

        if len(session.participants) == 2 and session.status == SessionStatus.WAITING:
            session.status = SessionStatus.ACTIVE
            session.started_at = datetime.utcnow()

        await self.update_session(session)
        return session

    async def update_participant_status(
        self, session_id: str, participant_id: str, status: ParticipantStatus
    ):
        session = await self.get_session(session_id)
        if not session:
            return
        for p in session.participants:
            if p.id == participant_id:
                p.status = status
                break
        await self.update_session(session)

    async def remove_participant(self, session_id: str, participant_id: str):
        session = await self.get_session(session_id)
        if not session:
            return

        for p in session.participants:
            if p.id == participant_id:
                p.status = ParticipantStatus.DISCONNECTED
                break

        connected = [p for p in session.participants if p.status == ParticipantStatus.CONNECTED]

        # Only end the session if it was already ACTIVE (both participants connected).
        # A WAITING session (host alone) should stay open so others can still join.
        if not connected and session.status == SessionStatus.ACTIVE:
            session.status = SessionStatus.ENDED
            session.ended_at = datetime.utcnow()

        await self.update_session(session)

    async def add_transcript_entry(self, session_id: str, entry: TranscriptEntry):
        session = await self.get_session(session_id)
        if not session:
            return
        session.transcript.append(entry)
        await self.update_session(session)

    # --- Broadcast helpers ---

    async def broadcast_to_session(
        self, session_id: str, data: dict, exclude_participant: str | None = None
    ):
        session = await self.get_session(session_id)
        if not session:
            return
        for p in session.participants:
            if p.id == exclude_participant:
                continue
            if p.websocket_id and self.connections.is_connected(p.websocket_id):
                await self.connections.send_json(p.websocket_id, data)

    async def send_audio_to_participant(
        self, session_id: str, participant_id: str, audio_bytes: bytes, metadata: dict
    ):
        session = await self.get_session(session_id)
        if not session:
            return
        p = session.get_participant(participant_id)
        if p and p.websocket_id:
            await self.connections.send_json(p.websocket_id, {
                "type": "audio_response",
                "data": {
                    "audio": audio_bytes.hex(),
                    "format": metadata.get("format", "mp3"),
                    **metadata,
                },
            })
