from pydantic import BaseModel
from typing import Optional, List
from enum import Enum


class MessageType(str, Enum):
    # Client → Server
    AUDIO_CHUNK = "audio_chunk"
    PING = "ping"
    SET_LANGUAGE = "set_language"
    MUTE = "mute"
    UNMUTE = "unmute"

    # Server → Client
    TRANSCRIPT_PARTIAL = "transcript_partial"
    TRANSCRIPT_FINAL = "transcript_final"
    TRANSLATION = "translation"
    AUDIO_RESPONSE = "audio_response"
    PARTICIPANT_JOINED = "participant_joined"
    PARTICIPANT_LEFT = "participant_left"
    SESSION_INFO = "session_info"
    PONG = "pong"
    ERROR = "error"
    PIPELINE_STATUS = "pipeline_status"


class PipelineStage(str, Enum):
    IDLE = "idle"
    RECORDING = "recording"
    TRANSCRIBING = "transcribing"
    TRANSLATING = "translating"
    SYNTHESIZING = "synthesizing"
    PLAYING = "playing"


class WSMessage(BaseModel):
    type: MessageType
    data: dict = {}
    session_id: Optional[str] = None
    participant_id: Optional[str] = None


class TranslationContext(BaseModel):
    source_language: str
    target_language: str
    domain: str = "general"
    history: List[dict] = []

    def add_turn(self, speaker: str, original: str, translated: str):
        self.history.append({
            "speaker": speaker,
            "original": original,
            "translated": translated,
        })
        if len(self.history) > 16:
            self.history = self.history[-16:]


class STTResult(BaseModel):
    text: str
    language: Optional[str] = None
    confidence: Optional[float] = None
    is_final: bool = True
    duration_ms: Optional[int] = None


class TranslationResult(BaseModel):
    original_text: str
    translated_text: str
    source_language: str
    target_language: str
    latency_ms: Optional[int] = None


class TTSResult(BaseModel):
    audio_bytes: bytes
    format: str = "mp3"
    sample_rate: int = 24000
    latency_ms: Optional[int] = None
