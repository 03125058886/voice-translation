from pydantic_settings import BaseSettings
from typing import List
import os


class Settings(BaseSettings):
    APP_NAME: str = "Voice Translation Platform"
    APP_VERSION: str = "1.0.0"
    DEBUG: bool = False

    HOST: str = "0.0.0.0"
    PORT: int = 8000

    CORS_ORIGINS: List[str] = [
        "http://localhost:3000",
        "http://localhost:8080",
        "http://localhost:80",
        "http://localhost",
        "http://127.0.0.1:3000",
        "http://127.0.0.1:8080",
    ]

    # OpenAI (fallback only)
    OPENAI_API_KEY: str = ""
    OPENAI_STT_MODEL: str = "whisper-1"
    OPENAI_TRANSLATION_MODEL: str = "gpt-4o"
    OPENAI_TTS_MODEL: str = "tts-1-hd"
    OPENAI_TTS_VOICE: str = "nova"

    # Groq (free tier — STT + Translation)
    GROQ_API_KEY: str = ""
    GROQ_STT_MODEL: str = "whisper-large-v3-turbo"
    GROQ_TRANSLATION_MODEL: str = "llama-3.3-70b-versatile"

    # ElevenLabs (premium TTS)
    ELEVENLABS_API_KEY: str = ""
    ELEVENLABS_VOICE_ID: str = "21m00Tcm4TlvDq8ikWAM"

    # Twilio
    TWILIO_ACCOUNT_SID: str = ""
    TWILIO_AUTH_TOKEN: str = ""
    TWILIO_PHONE_NUMBER: str = ""
    TWILIO_WEBHOOK_BASE_URL: str = ""

    # Redis
    REDIS_URL: str = "redis://redis:6379"
    REDIS_SESSION_TTL: int = 3600  # 1 hour

    # PostgreSQL
    DATABASE_URL: str = "postgresql+asyncpg://postgres:postgres@postgres:5432/voice_translation"

    # Session
    SESSION_TIMEOUT_MINUTES: int = 60
    MAX_CONCURRENT_SESSIONS: int = 500

    # Audio pipeline
    AUDIO_SAMPLE_RATE: int = 16000
    AUDIO_CHANNELS: int = 1
    AUDIO_CHUNK_MS: int = 100
    MIN_SPEECH_MS: int = 300
    SILENCE_THRESHOLD_MS: int = 800
    MAX_SEGMENT_MS: int = 15000

    # Translation
    TRANSLATION_CONTEXT_TURNS: int = 8
    ENABLE_PROFANITY_FILTER: bool = False

    # TTS Provider: "edge" | "openai" | "elevenlabs"
    TTS_PROVIDER: str = "edge"

    # API Security
    API_SECRET_KEY: str = "change-me-in-production"
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 1440

    class Config:
        env_file = ".env"
        case_sensitive = True


settings = Settings()
