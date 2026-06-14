'use client';

import { useState, useRef, useCallback, useEffect } from 'react';
import { TranslationWebSocket } from '@/lib/websocket';
import { useAudioCapture } from './useAudioCapture';
import { useAudioPlayer } from './useAudioPlayer';
import {
  CallSessionState, TranscriptDisplayEntry, WSMessage,
  PipelineStage,
} from '@/types';
import toast from 'react-hot-toast';

interface UseTranslationSessionOptions {
  sessionId: string;
  participantId: string;
  myName: string;
  myLanguage: string;
}

export function useTranslationSession({
  sessionId,
  participantId,
  myName,
  myLanguage,
}: UseTranslationSessionOptions) {
  const wsRef = useRef<TranslationWebSocket | null>(null);
  const connectingRef = useRef(false);
  const { playAudio, initContext } = useAudioPlayer();

  const [state, setState] = useState<CallSessionState>({
    sessionId,
    participantId,
    myLanguage,
    otherLanguage: null,
    myName,
    otherName: null,
    status: 'waiting',
    participants: [],
    pipelineStage: 'idle',
    otherPipelineStage: 'idle' as PipelineStage,
    isConnected: false,
    isMuted: false,
    transcript: [],
    partialText: '',
  });

  const addTranscript = useCallback((entry: TranscriptDisplayEntry) => {
    setState(prev => ({
      ...prev,
      transcript: [...prev.transcript, entry],
    }));
  }, []);

  const { start: startCapture, stop: stopCapture, isCapturing, volume } = useAudioCapture({
    sampleRate: 16000,
    chunkMs: 100,
    onChunk: useCallback((buffer: ArrayBuffer) => {
      wsRef.current?.sendAudio(buffer);
    }, []),
  });

  const connect = useCallback(async (showErrorToast = false) => {
    if (connectingRef.current || wsRef.current?.isConnected) return;
    connectingRef.current = true;

    const ws = new TranslationWebSocket(sessionId, participantId);
    wsRef.current = ws;

    ws.on('session_info', (msg: WSMessage) => {
      const d = msg.data as Record<string, unknown>;
      const participants = (d.participants as Array<{ id: string; name: string; language: string; status: string }>) || [];
      const other = participants.find(p => p.id !== participantId);
      setState(prev => ({
        ...prev,
        isConnected: true,
        status: other ? 'active' : 'waiting',
        participants: participants as CallSessionState['participants'],
        otherLanguage: other?.language ?? null,
        otherName: other?.name ?? null,
      }));
    });

    ws.on('participant_joined', (msg: WSMessage) => {
      const d = msg.data as { name: string; language: string };
      setState(prev => ({
        ...prev,
        otherName: d.name,
        otherLanguage: d.language,
        status: 'active',
      }));
      toast.success(`${d.name} joined the call`);
    });

    ws.on('participant_left', (msg: WSMessage) => {
      const d = msg.data as { name: string };
      setState(prev => ({ ...prev, otherName: null, otherLanguage: null, status: 'waiting' }));
      toast(`${d.name} left the call`, { icon: '👋' });
    });

    ws.on('transcript_partial', (msg: WSMessage) => {
      const d = msg.data as { text: string; participant_id: string };
      if (d.participant_id !== participantId) {
        // Other person is speaking — show their partial text live
        setState(prev => ({ ...prev, partialText: d.text }));
      }
    });

    ws.on('transcript_final', (msg: WSMessage) => {
      const d = msg.data as { text: string; participant_id: string };
      if (d.participant_id === participantId) {
        setState(prev => ({ ...prev, pipelineStage: 'translating' }));
      } else {
        setState(prev => ({ ...prev, partialText: '' }));
      }
    });

    ws.on('translation', (msg: WSMessage) => {
      const d = msg.data as {
        original_text: string;
        translated_text: string;
        source_language: string;
        target_language: string;
        speaker_id: string;
        speaker_name: string;
      };
      const isLocal = d.speaker_id === participantId;
      // Clear partial text when translation arrives
      setState(prev => ({ ...prev, partialText: '' }));
      addTranscript({
        id: `${Date.now()}-${Math.random()}`,
        speakerId: d.speaker_id,
        speakerName: d.speaker_name,
        originalText: d.original_text,
        translatedText: d.translated_text,
        sourceLang: d.source_language,
        targetLang: d.target_language,
        timestamp: new Date(),
        isLocal,
      });
    });

    ws.on('audio_response', (msg: WSMessage) => {
      const d = msg.data as { audio: string; format: string };
      if (d.audio) {
        playAudio(d.audio, d.format);
        setState(prev => ({ ...prev, pipelineStage: 'idle' }));
      }
    });

    ws.on('pipeline_status', (msg: WSMessage) => {
      const d = msg.data as { stage: PipelineStage; participant_id: string };
      if (d.participant_id === participantId) {
        setState(prev => ({ ...prev, pipelineStage: d.stage }));
      } else {
        setState(prev => ({ ...prev, otherPipelineStage: d.stage }));
      }
    });

    ws.on('error', (msg: WSMessage) => {
      const d = msg.data as { message?: string };
      toast.error(d.message || 'Connection error');
    });

    try {
      await ws.connect();
      setState(prev => ({ ...prev, isConnected: true }));
    } catch (err) {
      if (showErrorToast) {
        toast.error('Failed to connect to translation server');
      }
      throw err;
    } finally {
      connectingRef.current = false;
    }
  }, [sessionId, participantId, addTranscript, playAudio]);

  // Auto-connect WebSocket on mount so we can receive translations
  // without requiring the user to click Start Mic first.
  // Failures are silent here — the TranslationWebSocket retries automatically,
  // and the user sees an error only if they explicitly click Start Mic.
  useEffect(() => {
    connect().catch(() => {
      // Silently swallow — TranslationWebSocket has built-in reconnect logic.
    });
    return () => {
      wsRef.current?.disconnect();
      wsRef.current = null;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // startCall = unlock audio + connect WS if needed + start mic
  const startCall = useCallback(async () => {
    initContext();
    if (!wsRef.current?.isConnected) {
      await connect(true); // show error toast if WS fails on explicit user action
    }
    await startCapture();
  }, [connect, startCapture, initContext]);

  const endCall = useCallback(() => {
    wsRef.current?.flush();
    stopCapture();
    wsRef.current?.disconnect();
    wsRef.current = null;
    setState(prev => ({ ...prev, isConnected: false, status: 'ended', pipelineStage: 'idle' }));
  }, [stopCapture]);

  const toggleMute = useCallback(() => {
    setState(prev => {
      const next = !prev.isMuted;
      if (next) wsRef.current?.mute();
      else wsRef.current?.unmute();
      return { ...prev, isMuted: next };
    });
  }, []);

  return {
    state,
    volume,
    isCapturing,
    startCall,
    endCall,
    toggleMute,
  };
}
