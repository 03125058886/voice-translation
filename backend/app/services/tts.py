import time
import logging
import io
import httpx
import edge_tts
from gtts import gTTS
from openai import AsyncOpenAI

from app.config import settings
from app.models.translation import TTSResult

logger = logging.getLogger(__name__)

EDGE_TTS_VOICE_MAP = {
    "en": "en-US-AriaNeural",
    "es": "es-ES-ElviraNeural",
    "fr": "fr-FR-DeniseNeural",
    "de": "de-DE-KatjaNeural",
    "it": "it-IT-ElsaNeural",
    "pt": "pt-BR-FranciscaNeural",
    "ru": "ru-RU-SvetlanaNeural",
    "zh": "zh-CN-XiaoxiaoNeural",
    "ja": "ja-JP-NanamiNeural",
    "ko": "ko-KR-SunHiNeural",
    "ar": "ar-SA-ZariyahNeural",
    "hi": "hi-IN-SwaraNeural",
    "ur": "ur-PK-UzmaNeural",
    "tr": "tr-TR-EmelNeural",
    "nl": "nl-NL-ColetteNeural",
    "pl": "pl-PL-ZofiaNeural",
    "sv": "sv-SE-SofieNeural",
    "no": "nb-NO-PernilleNeural",
    "da": "da-DK-ChristelNeural",
    "fi": "fi-FI-NooraNeural",
}

# gTTS uses Google Translate lang codes; most match ours except a few
GTTS_LANG_MAP = {
    "zh": "zh-CN",
    "no": "no",
}


class TTSService:
    def __init__(self):
        self.provider = settings.TTS_PROVIDER
        self.openai_client = AsyncOpenAI(api_key=settings.OPENAI_API_KEY) if settings.OPENAI_API_KEY else None

    async def synthesize(
        self,
        text: str,
        language: str = "en",
        voice_override: str | None = None,
    ) -> TTSResult:
        if not text.strip():
            return TTSResult(audio_bytes=b"", format="mp3", sample_rate=24000)

        try:
            if self.provider == "elevenlabs" and settings.ELEVENLABS_API_KEY:
                return await self._elevenlabs_tts(text, language, voice_override)
            if self.provider == "openai" and self.openai_client:
                return await self._openai_tts(text, language, voice_override)
        except Exception as e:
            logger.warning(f"{self.provider} TTS failed ({e}), falling back to Edge/gTTS")
        return await self._edge_tts_with_fallback(text, language, voice_override)

    async def _edge_tts_with_fallback(
        self,
        text: str,
        language: str,
        voice_override: str | None,
    ) -> TTSResult:
        try:
            return await self._edge_tts(text, language, voice_override)
        except Exception as e:
            logger.warning(f"Edge TTS failed ({e}), falling back to gTTS")
            return await self._gtts(text, language)

    async def _edge_tts(
        self,
        text: str,
        language: str,
        voice_override: str | None,
    ) -> TTSResult:
        start = time.monotonic()
        voice = voice_override or EDGE_TTS_VOICE_MAP.get(language, "en-US-AriaNeural")
        communicate = edge_tts.Communicate(text, voice)

        audio_data = io.BytesIO()
        async for chunk in communicate.stream():
            if chunk["type"] == "audio":
                audio_data.write(chunk["data"])

        audio_bytes = audio_data.getvalue()
        if not audio_bytes:
            raise RuntimeError("Edge TTS returned empty audio")

        latency_ms = int((time.monotonic() - start) * 1000)
        logger.info(f"TTS (Edge): {len(text)} chars | voice={voice} | {latency_ms}ms | {len(audio_bytes)} bytes")
        return TTSResult(audio_bytes=audio_bytes, format="mp3", sample_rate=24000, latency_ms=latency_ms)

    async def _gtts(self, text: str, language: str) -> TTSResult:
        """Google TTS — free fallback, no API key required."""
        import asyncio
        start = time.monotonic()
        lang = GTTS_LANG_MAP.get(language, language)
        try:
            loop = asyncio.get_event_loop()
            audio_bytes = await loop.run_in_executor(None, self._gtts_sync, text, lang)
            latency_ms = int((time.monotonic() - start) * 1000)
            logger.info(f"TTS (gTTS): {len(text)} chars | lang={lang} | {latency_ms}ms | {len(audio_bytes)} bytes")
            return TTSResult(audio_bytes=audio_bytes, format="mp3", sample_rate=24000, latency_ms=latency_ms)
        except Exception as e:
            logger.error(f"gTTS error: {e}")
            raise

    def _gtts_sync(self, text: str, lang: str) -> bytes:
        buf = io.BytesIO()
        gTTS(text=text, lang=lang, slow=False).write_to_fp(buf)
        return buf.getvalue()

    async def _openai_tts(
        self,
        text: str,
        language: str,
        voice_override: str | None,
    ) -> TTSResult:
        start = time.monotonic()
        try:
            voice = voice_override or "nova"
            response = await self.openai_client.audio.speech.create(
                model=settings.OPENAI_TTS_MODEL,
                voice=voice,
                input=text,
                response_format="mp3",
                speed=1.0,
            )
            audio_bytes = response.content
            latency_ms = int((time.monotonic() - start) * 1000)
            logger.info(f"TTS (OpenAI): {len(text)} chars | {latency_ms}ms | {len(audio_bytes)} bytes")
            return TTSResult(audio_bytes=audio_bytes, format="mp3", sample_rate=24000, latency_ms=latency_ms)
        except Exception as e:
            logger.error(f"OpenAI TTS error: {e}")
            raise

    async def _elevenlabs_tts(
        self,
        text: str,
        language: str,
        voice_override: str | None,
    ) -> TTSResult:
        start = time.monotonic()
        voice_id = voice_override or settings.ELEVENLABS_VOICE_ID
        url = f"https://api.elevenlabs.io/v1/text-to-speech/{voice_id}"
        headers = {"xi-api-key": settings.ELEVENLABS_API_KEY, "Content-Type": "application/json"}
        payload = {
            "text": text,
            "model_id": "eleven_turbo_v2_5",
            "voice_settings": {"stability": 0.5, "similarity_boost": 0.75, "style": 0.0, "use_speaker_boost": True},
            "output_format": "mp3_44100_128",
        }
        try:
            async with httpx.AsyncClient(timeout=30.0) as client:
                response = await client.post(url, headers=headers, json=payload)
                response.raise_for_status()
                audio_bytes = response.content
            latency_ms = int((time.monotonic() - start) * 1000)
            logger.info(f"TTS (ElevenLabs): {len(text)} chars | {latency_ms}ms | {len(audio_bytes)} bytes")
            return TTSResult(audio_bytes=audio_bytes, format="mp3", sample_rate=44100, latency_ms=latency_ms)
        except Exception as e:
            logger.error(f"ElevenLabs TTS error: {e}")
            return await self._edge_tts_with_fallback(text, language, voice_override)
