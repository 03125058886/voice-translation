import asyncio
import logging
import time
from typing import Callable, Awaitable, Optional

from app.services.stt import STTService
from app.services.translation import TranslationService
from app.services.tts import TTSService
from app.services.vad import VoiceActivityDetector
from app.models.translation import (
    STTResult, TranslationResult, TTSResult,
    TranslationContext, PipelineStage,
)
from app.config import settings

logger = logging.getLogger(__name__)

OnTranscriptPartial = Callable[[str], Awaitable[None]]
OnTranscriptFinal = Callable[[STTResult], Awaitable[None]]
OnTranslation = Callable[[TranslationResult], Awaitable[None]]
OnAudioReady = Callable[[TTSResult], Awaitable[None]]
OnStageChange = Callable[[PipelineStage], Awaitable[None]]


class TranslationPipeline:
    """
    Orchestrates the full STT → Translate → TTS pipeline for one direction
    of a bidirectional conversation.
    """

    def __init__(
        self,
        stt: STTService,
        translation: TranslationService,
        tts: TTSService,
        context: TranslationContext,
        speaker_name: str,
        on_transcript_partial: Optional[OnTranscriptPartial] = None,
        on_transcript_final: Optional[OnTranscriptFinal] = None,
        on_translation: Optional[OnTranslation] = None,
        on_audio_ready: Optional[OnAudioReady] = None,
        on_stage_change: Optional[OnStageChange] = None,
    ):
        self.stt = stt
        self.translation = translation
        self.tts = tts
        self.context = context
        self.speaker_name = speaker_name

        self.on_transcript_partial = on_transcript_partial
        self.on_transcript_final = on_transcript_final
        self.on_translation = on_translation
        self.on_audio_ready = on_audio_ready
        self.on_stage_change = on_stage_change
        self.on_error: Optional[Callable[[str], Awaitable[None]]] = None

        self.vad = VoiceActivityDetector(
            sample_rate=settings.AUDIO_SAMPLE_RATE,
            silence_threshold_ms=settings.SILENCE_THRESHOLD_MS,
            min_speech_ms=settings.MIN_SPEECH_MS,
        )

        self.stage = PipelineStage.IDLE
        self._processing_lock = asyncio.Lock()
        self._is_muted = False
        self._total_audio_ms = 0
        self._segment_start_ms = 0

    async def _set_stage(self, stage: PipelineStage):
        self.stage = stage
        if self.on_stage_change:
            await self.on_stage_change(stage)

    async def feed_audio(self, pcm_bytes: bytes):
        if self._is_muted:
            return

        await self._set_stage(PipelineStage.RECORDING)
        is_speaking, speech_ended, audio_segment = self.vad.process_frame(pcm_bytes)

        if speech_ended and audio_segment:
            asyncio.create_task(self._process_segment(audio_segment))

    async def flush(self):
        """Force-process any buffered audio (e.g., on disconnect)."""
        audio = self.vad.flush()
        if audio:
            await self._process_segment(audio)

    async def _process_segment(self, audio: bytes):
        async with self._processing_lock:
            segment_start = time.monotonic()
            try:
                await self._set_stage(PipelineStage.TRANSCRIBING)
                stt_result = await self.stt.transcribe(
                    audio,
                    language=self.context.source_language,
                    is_pcm=True,
                )

                if not stt_result.text.strip():
                    await self._set_stage(PipelineStage.IDLE)
                    return

                if self.on_transcript_final:
                    await self.on_transcript_final(stt_result)

                await self._set_stage(PipelineStage.TRANSLATING)
                translation_result = await self.translation.translate(
                    stt_result.text,
                    self.context,
                    self.speaker_name,
                )

                self.context.add_turn(
                    self.speaker_name,
                    stt_result.text,
                    translation_result.translated_text,
                )

                if self.on_translation:
                    await self.on_translation(translation_result)

                await self._set_stage(PipelineStage.SYNTHESIZING)
                tts_result = await self.tts.synthesize(
                    translation_result.translated_text,
                    language=self.context.target_language,
                )

                if self.on_audio_ready:
                    await self.on_audio_ready(tts_result)

                total_ms = int((time.monotonic() - segment_start) * 1000)
                logger.info(
                    f"Pipeline complete: STT={stt_result.duration_ms}ms "
                    f"| Trans={translation_result.latency_ms}ms "
                    f"| TTS={tts_result.latency_ms}ms "
                    f"| Total={total_ms}ms"
                )

            except Exception as e:
                logger.error(f"Pipeline error: {e}", exc_info=True)
                if self.on_error:
                    await self.on_error(str(e))
            finally:
                await self._set_stage(PipelineStage.IDLE)

    def mute(self):
        self._is_muted = True
        self.vad.reset()

    def unmute(self):
        self._is_muted = False

    def reset(self):
        self.vad.reset()
        self.stage = PipelineStage.IDLE
