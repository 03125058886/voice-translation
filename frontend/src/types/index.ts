export type Language = {
  code: string;
  name: string;
};

export type ParticipantStatus = 'waiting' | 'connected' | 'speaking' | 'disconnected';
export type SessionStatus = 'waiting' | 'active' | 'ended' | 'error';
export type PipelineStage = 'idle' | 'recording' | 'transcribing' | 'translating' | 'synthesizing' | 'playing';

export type MessageType =
  | 'audio_chunk'
  | 'ping'
  | 'pong'
  | 'mute'
  | 'unmute'
  | 'flush'
  | 'set_language'
  | 'transcript_partial'
  | 'transcript_final'
  | 'translation'
  | 'audio_response'
  | 'participant_joined'
  | 'participant_left'
  | 'session_info'
  | 'error'
  | 'pipeline_status';

export interface Participant {
  id: string;
  name: string;
  language: string;
  status: ParticipantStatus;
}

export interface TranscriptEntry {
  id: string;
  participant_id: string;
  participant_name: string;
  original_text: string;
  translated_text: string;
  source_language: string;
  target_language: string;
  timestamp: string;
}

export interface Session {
  id: string;
  name: string;
  status: SessionStatus;
  participants: Participant[];
  transcript: TranscriptEntry[];
  created_at: string;
  domain: string;
}

export interface WSMessage {
  type: MessageType;
  data: Record<string, unknown>;
}

export interface TranscriptDisplayEntry {
  id: string;
  speakerId: string;
  speakerName: string;
  originalText: string;
  translatedText: string;
  sourceLang: string;
  targetLang: string;
  timestamp: Date;
  isLocal: boolean;
}

export interface AudioResponseData {
  audio: string;
  format: string;
  sample_rate: number;
  speaker_id: string;
  speaker_name: string;
}

export interface CallSessionState {
  sessionId: string | null;
  participantId: string | null;
  myLanguage: string;
  otherLanguage: string | null;
  myName: string;
  otherName: string | null;
  status: SessionStatus;
  participants: Participant[];
  pipelineStage: PipelineStage;
  otherPipelineStage: PipelineStage;
  isConnected: boolean;
  isMuted: boolean;
  transcript: TranscriptDisplayEntry[];
  partialText: string;
}
