import { Session, Language } from '@/types';

const BASE_URL = process.env.NEXT_PUBLIC_API_URL || '';

async function request<T>(path: string, options?: RequestInit): Promise<T> {
  const res = await fetch(`${BASE_URL}/api${path}`, {
    headers: { 'Content-Type': 'application/json', ...options?.headers },
    ...options,
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({ detail: 'Request failed' }));
    throw new Error(err.detail || `HTTP ${res.status}`);
  }
  return res.json();
}

export interface CreateSessionPayload {
  name?: string;
  domain?: string;
  participant_name: string;
  participant_language: string;
}

export interface JoinSessionPayload {
  participant_name: string;
  participant_language: string;
}

export interface SessionResponse {
  session_id: string;
  participant_id: string;
  session: Session;
}

export const api = {
  createSession: (payload: CreateSessionPayload) =>
    request<SessionResponse>('/sessions', {
      method: 'POST',
      body: JSON.stringify(payload),
    }),

  joinSession: (sessionId: string, payload: JoinSessionPayload) =>
    request<SessionResponse>(`/sessions/${sessionId}/join`, {
      method: 'POST',
      body: JSON.stringify(payload),
    }),

  getSession: (sessionId: string) =>
    request<Session>(`/sessions/${sessionId}`),

  listSessions: () => request<Session[]>('/sessions'),

  getTranscript: (sessionId: string) =>
    request<{ transcript: Session['transcript'] }>(`/sessions/${sessionId}/transcript`),

  endSession: (sessionId: string) =>
    request<{ message: string }>(`/sessions/${sessionId}`, { method: 'DELETE' }),

  getLanguages: () => request<{ languages: Language[] }>('/languages'),

  health: () => request<{ status: string; version: string }>('/health'.replace('/api', '')),
};
