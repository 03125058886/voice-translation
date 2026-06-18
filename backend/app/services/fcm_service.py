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


async def _send_data_message(fcm_token: str, data: dict) -> bool:
    if not fcm_token:
        return False
    if not _init():
        return False
    try:
        from firebase_admin import messaging
        # Data-only — Flutter background handler shows custom notification with sound
        message = messaging.Message(
            data={k: str(v) for k, v in data.items()},
            android=messaging.AndroidConfig(priority="high", ttl=60),
            token=fcm_token,
        )
        loop = asyncio.get_event_loop()
        await loop.run_in_executor(None, messaging.send, message)
        return True
    except Exception as e:
        logger.error(f"FCM send failed: {e}")
        return False


async def send_incoming_call(
    fcm_token: str,
    caller_name: str,
    caller_language: str,
    caller_id: str,
    session_id: str,
) -> bool:
    ok = await _send_data_message(
        fcm_token,
        {
            "type": "incoming_call",
            "caller_name": caller_name,
            "caller_language": caller_language,
            "caller_id": caller_id,
            "session_id": session_id,
        },
    )
    if ok:
        logger.info(f"FCM call notification sent to {fcm_token[:10]}…")
    return ok


async def send_dm_notification(
    fcm_token: str,
    sender_name: str,
    sender_phone: str,
    preview: str,
) -> bool:
    ok = await _send_data_message(
        fcm_token,
        {
            "type": "new_message",
            "sender_name": sender_name,
            "sender_phone": sender_phone,
            "preview": preview[:120],
        },
    )
    if ok:
        logger.info(f"FCM DM notification sent to {fcm_token[:10]}…")
    return ok
