import logging
from typing import Dict, Optional
from fastapi import WebSocket

logger = logging.getLogger(__name__)


class OnlineUser:
    def __init__(self, user_id: str, name: str, language: str, websocket: WebSocket):
        self.user_id = user_id
        self.name = name
        self.language = language
        self.websocket = websocket

    def to_dict(self) -> dict:
        return {
            "user_id": self.user_id,
            "name": self.name,
            "language": self.language,
        }


class LobbyManager:
    def __init__(self):
        self._users: Dict[str, OnlineUser] = {}

    def register(self, user: OnlineUser):
        self._users[user.user_id] = user
        logger.info(f"Lobby: {user.name} ({user.user_id}) joined")

    def unregister(self, user_id: str):
        user = self._users.pop(user_id, None)
        if user:
            logger.info(f"Lobby: {user.name} ({user_id}) left")

    def online_users(self) -> list[dict]:
        return [u.to_dict() for u in self._users.values()]

    def get_user(self, user_id: str) -> Optional[OnlineUser]:
        return self._users.get(user_id)

    async def send_to(self, user_id: str, data: dict) -> bool:
        user = self._users.get(user_id)
        if not user:
            return False
        try:
            await user.websocket.send_json(data)
            return True
        except Exception as e:
            logger.warning(f"Lobby send failed to {user_id}: {e}")
            self.unregister(user_id)
            return False

    async def broadcast(self, data: dict, exclude: str | None = None):
        dead = []
        for uid, user in self._users.items():
            if uid == exclude:
                continue
            try:
                await user.websocket.send_json(data)
            except Exception:
                dead.append(uid)
        for uid in dead:
            self.unregister(uid)


lobby_manager = LobbyManager()
