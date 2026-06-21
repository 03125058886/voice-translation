import asyncio
import base64
import logging
import json
from typing import Dict
from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Depends

from app.core.session_manager import SessionManager
from app.core.pipeline import TranslationPipeline
from app.services.stt import STTService
from app.services.translation import TranslationService
from app.services.tts import TTSService
from app.models.translation import (
    TranslationContext, STTResult, TranslationResult, TTSResult, PipelineStage,
)
from app.models.session import (
    ParticipantStatus, TranscriptEntry, SessionStatus,
)

logger = logging.getLogger(__name__)
router = APIRouter()

_session_manager: SessionManager | None = None
_stt_service = STTService()
_translation_service = TranslationService()
_tts_service = TTSService()

_active_pipelines: Dict[str, TranslationPipeline] = {}


def set_session_manager(sm: SessionManager):
    global _session_manager
    _session_manager = sm


@router.websocket("/ws/{session_id}/{participant_id}")
async def websocket_endpoint(
    websocket: WebSocket,
    session_id: str,
    participant_id: str,
):
    sm = _session_manager
    if not sm:
        await websocket.close(code=1011, reason="Server not initialized")
        return

    session = await sm.get_session(session_id)
    if not session:
        await websocket.close(code=1008, reason="Session not found")
        return

    participant = session.get_participant(participant_id)
    if not participant:
        await websocket.close(code=1008, reason="Participant not found")
        return

    ws_id = f"{session_id}:{participant_id}"
    await sm.connections.connect(ws_id, websocket)

    participant.websocket_id = ws_id
    await sm.update_session(session)
    await sm.update_participant_status(session_id, participant_id, ParticipantStatus.CONNECTED)

    others = session.get_other_participants(participant_id)
    for other in others:
        if other.websocket_id and sm.connections.is_connected(other.websocket_id):
            await sm.connections.send_json(other.websocket_id, {
                "type": "participant_joined",
                "data": {
                    "participant_id": participant_id,
                    "name": participant.name,
                    "language": participant.language,
                },
            })

    await sm.connections.send_json(ws_id, {
        "type": "session_info",
        "data": {
            "session_id": session_id,
            "participant_id": participant_id,
            "language": participant.language,
            "participants": [
                {
                    "id": p.id,
                    "name": p.name,
                    "language": p.language,
                    "status": p.status.value,
                }
                for p in session.participants
            ],
        },
    })

    pipeline_key = f"{session_id}:{participant_id}"
    context = TranslationContext(
        source_language=participant.language,
        target_language="",
        domain=session.domain,
    )

    async def on_transcript_partial(text: str):
        payload = {"type": "transcript_partial", "data": {"text": text, "participant_id": participant_id}}
        await sm.connections.send_json(ws_id, payload)
        # Also send to the other participant so they see typing in real time
        cur = await sm.get_session(session_id)
        if cur:
            for other in cur.get_other_participants(participant_id):
                if other.websocket_id and sm.connections.is_connected(other.websocket_id):
                    await sm.connections.send_json(other.websocket_id, payload)

    async def on_transcript_final(result: STTResult):
        await sm.connections.send_json(ws_id, {
            "type": "transcript_final",
            "data": {
                "text": result.text,
                "language": result.language,
                "participant_id": participant_id,
            },
        })

    async def on_translation(result: TranslationResult):
        cur_session = await sm.get_session(session_id)
        if not cur_session:
            return

        others = cur_session.get_other_participants(participant_id)
        for other in others:
            if other.websocket_id and sm.connections.is_connected(other.websocket_id):
                await sm.connections.send_json(other.websocket_id, {
                    "type": "translation",
                    "data": {
                        "original_text": result.original_text,
                        "translated_text": result.translated_text,
                        "source_language": result.source_language,
                        "target_language": result.target_language,
                        "speaker_id": participant_id,
                        "speaker_name": participant.name,
                    },
                })

        await sm.connections.send_json(ws_id, {
            "type": "translation",
            "data": {
                "original_text": result.original_text,
                "translated_text": result.translated_text,
                "source_language": result.source_language,
                "target_language": result.target_language,
                "speaker_id": participant_id,
                "speaker_name": participant.name,
            },
        })

        entry = TranscriptEntry(
            participant_id=participant_id,
            participant_name=participant.name,
            original_text=result.original_text,
            translated_text=result.translated_text,
            source_language=result.source_language,
            target_language=result.target_language,
        )
        await sm.add_transcript_entry(session_id, entry)

    async def on_audio_ready(result: TTSResult):
        cur_session = await sm.get_session(session_id)
        if not cur_session:
            return

        audio_b64 = base64.b64encode(result.audio_bytes).decode()
        others = cur_session.get_other_participants(participant_id)
        for other in others:
            if other.websocket_id and sm.connections.is_connected(other.websocket_id):
                await sm.connections.send_json(other.websocket_id, {
                    "type": "audio_response",
                    "data": {
                        "audio": audio_b64,
                        "format": result.format,
                        "sample_rate": result.sample_rate,
                        "speaker_id": participant_id,
                        "speaker_name": participant.name,
                    },
                })

    async def on_stage_change(stage: PipelineStage):
        payload = {"type": "pipeline_status", "data": {"stage": stage.value, "participant_id": participant_id}}
        await sm.connections.send_json(ws_id, payload)
        # Forward to the listener so they can show speaking/translating indicators
        cur = await sm.get_session(session_id)
        if cur:
            for other in cur.get_other_participants(participant_id):
                if other.websocket_id and sm.connections.is_connected(other.websocket_id):
                    await sm.connections.send_json(other.websocket_id, payload)

    async def on_pipeline_error(error: str):
        await sm.connections.send_json(ws_id, {
            "type": "error",
            "data": {"message": f"Translation error: {error[:120]}"},
        })

    pipeline = TranslationPipeline(
        stt=_stt_service,
        translation=_translation_service,
        tts=_tts_service,
        context=context,
        speaker_name=participant.name,
        on_transcript_partial=on_transcript_partial,
        on_transcript_final=on_transcript_final,
        on_translation=on_translation,
        on_audio_ready=on_audio_ready,
        on_stage_change=on_stage_change,
    )
    pipeline.on_error = on_pipeline_error
    _active_pipelines[pipeline_key] = pipeline

    async def broadcast_session_info(cur: Session):
        payload = {
            "type": "session_info",
            "data": {
                "session_id": session_id,
                "participant_id": participant_id,
                "language": participant.language,
                "participants": [
                    {
                        "id": p.id,
                        "name": p.name,
                        "language": p.language,
                        "status": p.status.value,
                    }
                    for p in cur.participants
                ],
            },
        }
        for p in cur.participants:
            if p.websocket_id and sm.connections.is_connected(p.websocket_id):
                await sm.connections.send_json(p.websocket_id, payload)

    # Keep every connected client in sync (fixes caller stuck on "waiting").
    fresh = await sm.get_session(session_id)
    if fresh:
        await broadcast_session_info(fresh)

    try:
        while True:
            msg = await websocket.receive()

            if "bytes" in msg and msg["bytes"]:
                cur_session = await sm.get_session(session_id)
                if not cur_session or cur_session.status == SessionStatus.ENDED:
                    break

                others = cur_session.get_other_participants(participant_id)
                if not others:
                    continue

                pipeline.context.target_language = others[0].language
                await pipeline.feed_audio(msg["bytes"])

            elif "text" in msg and msg["text"]:
                try:
                    data = json.loads(msg["text"])
                    msg_type = data.get("type")

                    if msg_type == "ping":
                        await sm.connections.send_json(ws_id, {"type": "pong"})

                    elif msg_type == "mute":
                        pipeline.mute()
                        await sm.update_participant_status(
                            session_id, participant_id, ParticipantStatus.CONNECTED
                        )

                    elif msg_type == "unmute":
                        pipeline.unmute()

                    elif msg_type == "flush":
                        await pipeline.flush()

                    elif msg_type == "set_language":
                        new_lang = data.get("data", {}).get("language")
                        if new_lang:
                            pipeline.context.source_language = new_lang
                            participant.language = new_lang
                            cur = await sm.get_session(session_id)
                            if cur:
                                p = cur.get_participant(participant_id)
                                if p:
                                    p.language = new_lang
                                    await sm.update_session(cur)

                except json.JSONDecodeError:
                    pass

    except WebSocketDisconnect:
        logger.info(f"WebSocket disconnected: {ws_id}")
    except Exception as e:
        logger.error(f"WebSocket error {ws_id}: {e}", exc_info=True)
    finally:
        await pipeline.flush()
        sm.connections.disconnect(ws_id)
        _active_pipelines.pop(pipeline_key, None)
        await sm.remove_participant(session_id, participant_id)

        updated = await sm.get_session(session_id)
        if updated:
            others = updated.get_other_participants(participant_id)
            for other in others:
                if other.websocket_id and sm.connections.is_connected(other.websocket_id):
                    await sm.connections.send_json(other.websocket_id, {
                        "type": "participant_left",
                        "data": {
                            "participant_id": participant_id,
                            "name": participant.name,
                        },
                    })
