import asyncio
import time
import io
import wave
import logging
from typing import Optional
from groq import AsyncGroq

from app.config import settings
from app.models.translation import STTResult

logger = logging.getLogger(__name__)


class STTService:
    def __init__(self):
        self.client = AsyncGroq(api_key=settings.GROQ_API_KEY)
        self.model = settings.GROQ_STT_MODEL

    def _pcm_to_wav(self, pcm_bytes: bytes, sample_rate: int = 16000) -> bytes:
        buf = io.BytesIO()
        with wave.open(buf, "wb") as wf:
            wf.setnchannels(1)
            wf.setsampwidth(2)  # 16-bit
            wf.setframerate(sample_rate)
            wf.writeframes(pcm_bytes)
        return buf.getvalue()

    async def transcribe(
        self,
        audio_bytes: bytes,
        language: Optional[str] = None,
        prompt: Optional[str] = None,
        is_pcm: bool = True,
    ) -> STTResult:
        start = time.monotonic()
        try:
            if is_pcm:
                audio_bytes = self._pcm_to_wav(audio_bytes)

            params = {
                "file": ("audio.wav", audio_bytes, "audio/wav"),
                "model": self.model,
                "response_format": "verbose_json",
                "temperature": 0.0,
            }
            if language:
                params["language"] = language
            if prompt:
                params["prompt"] = prompt

            response = await self.client.audio.transcriptions.create(**params)

            duration_ms = int((time.monotonic() - start) * 1000)
            text = response.text.strip()
            detected_lang = getattr(response, "language", language)

            logger.info(f"STT (Groq): '{text[:80]}' | lang={detected_lang} | {duration_ms}ms")

            return STTResult(
                text=text,
                language=detected_lang or language,
                confidence=None,
                is_final=True,
                duration_ms=duration_ms,
            )

        except Exception as e:
            logger.error(f"STT error: {e}")
            raise

    async def transcribe_stream(
        self,
        audio_chunks: asyncio.Queue,
        language: Optional[str] = None,
    ):
        audio_parts = []
        while True:
            try:
                chunk = audio_chunks.get_nowait()
                if chunk is None:
                    break
                audio_parts.append(chunk)
            except asyncio.QueueEmpty:
                break

        if not audio_parts:
            return None

        combined = b"".join(audio_parts)
        return await self.transcribe(combined, language=language)
