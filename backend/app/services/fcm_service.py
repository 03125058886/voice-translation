import asyncio
import json
import logging
import os

logger = logging.getLogger(__name__)

_initialized = False


def _init():
    global _initialized
    if _initialized:
        return True
    sa = os.environ.get("FIREBASE_SERVICE_ACCOUNT", "")
    if not sa:
        logger.warning("FIREBASE_SERVICE_ACCOUNT not set — FCM disabled")
        return False
    try:
        import firebase_admin
        from firebase_admin import credentials
        cred = credentials.Certificate(json.loads(sa))
        firebase_admin.initialize_app(cred)
        _initialized = True
        logger.info("Firebase Admin SDK initialized")
        return True
    except Exception as e:
        logger.error(f"Firebase Admin init failed: {e}")
        return False


async def send_incoming_call(
    fcm_token: str,
    caller_name: str,
    caller_language: str,
    caller_id: str,
    session_id: str,
) -> bool:
    if not fcm_token:
        return False
    if not _init():
        return False
    try:
        from firebase_admin import messaging
        # Data-only message so Flutter background handler shows custom ring notification
        message = messaging.Message(
            data={
                "type": "incoming_call",
                "caller_name": caller_name,
                "caller_language": caller_language,
                "caller_id": caller_id,
                "session_id": session_id,
            },
            android=messaging.AndroidConfig(
                priority="high",
                ttl=30,
            ),
            token=fcm_token,
        )
        loop = asyncio.get_event_loop()
        await loop.run_in_executor(None, messaging.send, message)
        logger.info(f"FCM call notification sent to {fcm_token[:10]}…")
        return True
    except Exception as e:
        logger.error(f"FCM send failed: {e}")
        return False
