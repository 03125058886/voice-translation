from pydantic import BaseModel, Field
from typing import Optional, List, Dict, Any
from enum import Enum
from datetime import datetime
import uuid


class Language(str, Enum):
    ENGLISH = "en"
    SPANISH = "es"
    FRENCH = "fr"
    GERMAN = "de"
    ITALIAN = "it"
    PORTUGUESE = "pt"
    RUSSIAN = "ru"
    CHINESE = "zh"
    JAPANESE = "ja"
    KOREAN = "ko"
    ARABIC = "ar"
    HINDI = "hi"
    URDU = "ur"
    TURKISH = "tr"
    DUTCH = "nl"
    POLISH = "pl"
    SWEDISH = "sv"
    NORWEGIAN = "no"
    DANISH = "da"
    FINNISH = "fi"


LANGUAGE_NAMES = {
    "en": "English", "es": "Spanish", "fr": "French", "de": "German",
    "it": "Italian", "pt": "Portuguese", "ru": "Russian", "zh": "Chinese",
    "ja": "Japanese", "ko": "Korean", "ar": "Arabic", "hi": "Hindi",
    "ur": "Urdu", "tr": "Turkish", "nl": "Dutch", "pl": "Polish",
    "sv": "Swedish", "no": "Norwegian", "da": "Danish", "fi": "Finnish",
}

TTS_VOICE_MAP = {
    "en": "nova", "es": "nova", "fr": "nova", "de": "nova",
    "it": "nova", "pt": "nova", "ru": "nova", "zh": "nova",
    "ja": "nova", "ko": "nova", "ar": "nova", "hi": "nova",
    "ur": "nova", "tr": "nova", "nl": "nova", "pl": "nova",
}


class ParticipantStatus(str, Enum):
    WAITING = "waiting"
    CONNECTED = "connected"
    SPEAKING = "speaking"
    DISCONNECTED = "disconnected"


class SessionStatus(str, Enum):
    WAITING = "waiting"
    ACTIVE = "active"
    ENDED = "ended"
    ERROR = "error"


class Participant(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    name: str
    language: str
    status: ParticipantStatus = ParticipantStatus.WAITING
    joined_at: Optional[datetime] = None
    websocket_id: Optional[str] = None
    phone_number: Optional[str] = None
    is_phone_participant: bool = False


class TranscriptEntry(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    participant_id: str
    participant_name: str
    original_text: str
    translated_text: str
    source_language: str
    target_language: str
    timestamp: datetime = Field(default_factory=datetime.utcnow)
    duration_ms: Optional[int] = None
    confidence: Optional[float] = None


class Session(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    name: Optional[str] = None
    status: SessionStatus = SessionStatus.WAITING
    participants: List[Participant] = []
    transcript: List[TranscriptEntry] = []
    created_at: datetime = Field(default_factory=datetime.utcnow)
    started_at: Optional[datetime] = None
    ended_at: Optional[datetime] = None
    domain: str = "general"
    metadata: Dict[str, Any] = {}
    allowed_phones: List[str] = []  # if empty = open session (backward compat)

    def get_participant(self, participant_id: str) -> Optional[Participant]:
        return next((p for p in self.participants if p.id == participant_id), None)

    def get_other_participants(self, participant_id: str) -> List[Participant]:
        return [p for p in self.participants if p.id != participant_id]


class CreateSessionRequest(BaseModel):
    name: Optional[str] = None
    domain: str = "general"
    participant_name: str
    participant_language: str
    caller_phone: Optional[str] = None
    target_phone: Optional[str] = None


class JoinSessionRequest(BaseModel):
    participant_name: str
    participant_language: str
    phone: Optional[str] = None  # for private session verification


class SessionResponse(BaseModel):
    session_id: str
    participant_id: str
    session: Session
