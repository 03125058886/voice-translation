import time
import logging
from groq import AsyncGroq
from openai import AsyncOpenAI

from app.config import settings
from app.models.translation import TranslationResult, TranslationContext
from app.models.session import LANGUAGE_NAMES

logger = logging.getLogger(__name__)

DOMAIN_PROMPTS = {
    "general": "You are a professional interpreter providing natural, fluent translations.",
    "medical": (
        "You are a certified medical interpreter. Translate with clinical precision, "
        "preserving medical terminology. Ensure patient safety through accurate translation."
    ),
    "legal": (
        "You are a certified legal interpreter. Translate with legal precision, "
        "preserving all legal terminology and nuance exactly."
    ),
    "business": (
        "You are a professional business interpreter. Maintain formal register and "
        "preserve business terminology and cultural business norms."
    ),
    "travel": (
        "You are a friendly travel interpreter. Keep translations natural and helpful "
        "for travel situations."
    ),
    "customer_support": (
        "You are a customer service interpreter. Translate empathetically and clearly, "
        "preserving the service context and any urgency."
    ),
}


class TranslationService:
    def __init__(self):
        self.client = AsyncGroq(api_key=settings.GROQ_API_KEY)
        self.model = settings.GROQ_TRANSLATION_MODEL
        self.fallback_client = (
            AsyncOpenAI(api_key=settings.OPENAI_API_KEY) if settings.OPENAI_API_KEY else None
        )

    def _build_messages(
        self,
        text: str,
        context: TranslationContext,
        speaker_name: str,
    ) -> list:
        source_name = LANGUAGE_NAMES.get(context.source_language, context.source_language)
        target_name = LANGUAGE_NAMES.get(context.target_language, context.target_language)
        domain_prompt = DOMAIN_PROMPTS.get(context.domain, DOMAIN_PROMPTS["general"])

        system = (
            f"{domain_prompt}\n\n"
            f"Translate from {source_name} to {target_name}.\n"
            "Rules:\n"
            "- Output ONLY the translated text, nothing else\n"
            "- Preserve the speaker's tone, emotion, and register\n"
            "- Keep cultural expressions natural in the target language\n"
            "- Preserve names, numbers, and proper nouns as-is\n"
            "- If text is already in the target language, translate it back to source, "
            "then to target"
        )

        messages = [{"role": "system", "content": system}]

        for turn in context.history[-settings.TRANSLATION_CONTEXT_TURNS:]:
            messages.append({
                "role": "user",
                "content": f"[{turn['speaker']}]: {turn['original']}",
            })
            messages.append({
                "role": "assistant",
                "content": turn["translated"],
            })

        messages.append({
            "role": "user",
            "content": f"[{speaker_name}]: {text}",
        })

        return messages

    async def translate(
        self,
        text: str,
        context: TranslationContext,
        speaker_name: str = "Speaker",
    ) -> TranslationResult:
        if not text.strip():
            return TranslationResult(
                original_text=text,
                translated_text=text,
                source_language=context.source_language,
                target_language=context.target_language,
            )

        start = time.monotonic()
        messages = self._build_messages(text, context, speaker_name)

        try:
            translated = await self._complete_with(self.client, self.model, messages)
            label = "Groq"
        except Exception as e:
            logger.warning(f"Groq translation failed ({e}), falling back to OpenAI")
            if not self.fallback_client:
                raise
            translated = await self._complete_with(
                self.fallback_client, settings.OPENAI_TRANSLATION_MODEL, messages
            )
            label = "OpenAI"

        latency_ms = int((time.monotonic() - start) * 1000)
        logger.info(
            f"Translation ({label}): '{text[:60]}' → '{translated[:60]}' "
            f"({context.source_language}→{context.target_language}) | {latency_ms}ms"
        )

        return TranslationResult(
            original_text=text,
            translated_text=translated,
            source_language=context.source_language,
            target_language=context.target_language,
            latency_ms=latency_ms,
        )

    async def _complete_with(self, client, model, messages) -> str:
        response = await client.chat.completions.create(
            model=model,
            messages=messages,
            temperature=0.1,
            max_tokens=1024,
        )
        return response.choices[0].message.content.strip()
