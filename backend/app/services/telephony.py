import logging
from typing import Optional
from app.config import settings

logger = logging.getLogger(__name__)


class TelephonyService:
    def __init__(self):
        self._client = None
        self._initialized = False

    def _get_client(self):
        if not self._initialized:
            if not settings.TWILIO_ACCOUNT_SID or not settings.TWILIO_AUTH_TOKEN:
                raise RuntimeError("Twilio credentials not configured")
            try:
                from twilio.rest import Client
                self._client = Client(settings.TWILIO_ACCOUNT_SID, settings.TWILIO_AUTH_TOKEN)
                self._initialized = True
            except ImportError:
                raise RuntimeError("twilio package not installed")
        return self._client

    async def initiate_call(
        self,
        to_number: str,
        session_id: str,
        participant_id: str,
        language: str,
    ) -> dict:
        client = self._get_client()
        webhook_url = (
            f"{settings.TWILIO_WEBHOOK_BASE_URL}/api/telephony/voice"
            f"?session_id={session_id}&participant_id={participant_id}&language={language}"
        )

        call = client.calls.create(
            to=to_number,
            from_=settings.TWILIO_PHONE_NUMBER,
            url=webhook_url,
            method="POST",
        )

        logger.info(f"Call initiated: {call.sid} → {to_number}")
        return {"call_sid": call.sid, "status": call.status}

    def generate_twiml_connect(self, session_id: str, participant_id: str) -> str:
        ws_url = (
            f"{settings.TWILIO_WEBHOOK_BASE_URL.replace('https', 'wss').replace('http', 'ws')}"
            f"/ws/telephony/{session_id}/{participant_id}"
        )
        return f"""<?xml version="1.0" encoding="UTF-8"?>
<Response>
    <Connect>
        <Stream url="{ws_url}">
            <Parameter name="session_id" value="{session_id}"/>
            <Parameter name="participant_id" value="{participant_id}"/>
        </Stream>
    </Connect>
</Response>"""

    async def end_call(self, call_sid: str) -> bool:
        try:
            client = self._get_client()
            client.calls(call_sid).update(status="completed")
            return True
        except Exception as e:
            logger.error(f"Failed to end call {call_sid}: {e}")
            return False
