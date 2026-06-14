'use client';

import { useState, useEffect, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { LanguageSelector } from '@/components/LanguageSelector';
import { api } from '@/lib/api';
import { Session } from '@/types';
import { getLanguageFlag, getLanguageName } from '@/lib/utils';
import toast from 'react-hot-toast';

const DOMAINS = [
  { value: 'general', label: 'General', icon: '💬' },
  { value: 'medical', label: 'Medical', icon: '🏥' },
  { value: 'legal', label: 'Legal', icon: '⚖️' },
  { value: 'business', label: 'Business', icon: '💼' },
  { value: 'travel', label: 'Travel', icon: '✈️' },
  { value: 'customer_support', label: 'Customer Support', icon: '🎧' },
];

function SessionCard({
  session,
  onJoin,
  disabled,
}: {
  session: Session;
  onJoin: (id: string) => void;
  disabled: boolean;
}) {
  const host = session.participants[0];
  if (!host) return null;
  return (
    <div className="flex items-center gap-3 bg-surface-800 border border-brand-600/30 rounded-xl px-4 py-3 hover:border-brand-500/60 transition-colors">
      <div className="w-10 h-10 rounded-full bg-brand-600/20 flex items-center justify-center font-bold text-brand-300 text-base shrink-0">
        {host.name[0]?.toUpperCase()}
      </div>
      <div className="flex-1 min-w-0">
        <p className="text-sm font-semibold truncate">{host.name}</p>
        <p className="text-xs text-surface-400">
          {getLanguageFlag(host.language)} {getLanguageName(host.language)}
          {session.domain !== 'general' && ` · ${session.domain}`}
        </p>
      </div>
      <button
        onClick={() => onJoin(session.id)}
        disabled={disabled}
        className="shrink-0 px-4 py-2 bg-brand-600 hover:bg-brand-500 text-white text-xs font-semibold rounded-lg transition-all disabled:opacity-50 disabled:cursor-not-allowed"
      >
        Join
      </button>
    </div>
  );
}

export default function HomePage() {
  const router = useRouter();
  const [name, setName] = useState('');
  const [language, setLanguage] = useState('en');
  const [domain, setDomain] = useState('general');
  const [joinCode, setJoinCode] = useState('');
  const [mode, setMode] = useState<'create' | 'join'>('create');
  const [loading, setLoading] = useState(false);
  const [waitingSessions, setWaitingSessions] = useState<Session[]>([]);
  const [sessionsLoading, setSessionsLoading] = useState(false);

  const fetchSessions = useCallback(async () => {
    setSessionsLoading(true);
    try {
      const all = await api.listSessions();
      setWaitingSessions(
        all.filter(s => s.status === 'waiting' && s.participants.length === 1)
      );
    } catch {
      // silently ignore
    } finally {
      setSessionsLoading(false);
    }
  }, []);

  useEffect(() => {
    if (mode !== 'join') return;
    fetchSessions();
    const id = setInterval(fetchSessions, 5000);
    return () => clearInterval(id);
  }, [mode, fetchSessions]);

  const handleCreate = async () => {
    if (!name.trim()) { toast.error('Please enter your name'); return; }
    setLoading(true);
    try {
      const res = await api.createSession({
        participant_name: name.trim(),
        participant_language: language,
        domain,
      });
      router.push(
        `/call/${res.session_id}?pid=${res.participant_id}&name=${encodeURIComponent(name)}&lang=${language}`
      );
    } catch (e: unknown) {
      toast.error(e instanceof Error ? e.message : 'Failed to create session');
    } finally {
      setLoading(false);
    }
  };

  const handleJoinCode = async () => {
    if (!name.trim()) { toast.error('Please enter your name'); return; }
    if (!joinCode.trim()) { toast.error('Please enter a session code'); return; }
    await doJoin(joinCode.trim());
  };

  const doJoin = async (sessionId: string) => {
    if (!name.trim()) { toast.error('Please enter your name first'); return; }
    setLoading(true);
    try {
      const res = await api.joinSession(sessionId, {
        participant_name: name.trim(),
        participant_language: language,
      });
      router.push(
        `/call/${res.session_id}?pid=${res.participant_id}&name=${encodeURIComponent(name)}&lang=${language}&autostart=true`
      );
    } catch (e: unknown) {
      toast.error(e instanceof Error ? e.message : 'Failed to join session');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen bg-surface-950 flex flex-col">
      {/* Hero */}
      <div className="flex-1 flex flex-col items-center justify-center px-4 py-16">
        <div className="text-center mb-12">
          <div className="flex items-center justify-center gap-3 mb-6">
            <div className="w-14 h-14 bg-brand-600 rounded-2xl flex items-center justify-center text-2xl font-bold shadow-lg shadow-brand-900/50">
              VT
            </div>
          </div>
          <h1 className="text-5xl font-bold tracking-tight mb-4">
            Speak in any language.
            <br />
            <span className="text-brand-400">Heard in every language.</span>
          </h1>
          <p className="text-lg text-surface-400 max-w-xl mx-auto">
            Real-time AI voice translation for natural multilingual conversations.
            No delays, no missed nuance — just clear communication.
          </p>
        </div>

        {/* Feature chips */}
        <div className="flex flex-wrap justify-center gap-2 mb-12">
          {['20 Languages', 'Sub-2s Latency', 'Context-Aware', 'Healthcare Ready', 'Legal Ready'].map(f => (
            <span key={f} className="px-3 py-1 bg-surface-800 border border-surface-700 rounded-full text-xs text-surface-400">
              {f}
            </span>
          ))}
        </div>

        {/* Card */}
        <div className="w-full max-w-md bg-surface-900 border border-surface-700 rounded-2xl p-6 shadow-2xl">
          {/* Mode tabs */}
          <div className="flex bg-surface-800 rounded-xl p-1 mb-6">
            {(['create', 'join'] as const).map(m => (
              <button
                key={m}
                onClick={() => setMode(m)}
                className={`flex-1 py-2 text-sm font-medium rounded-lg transition-all ${
                  mode === m
                    ? 'bg-brand-600 text-white shadow'
                    : 'text-surface-400 hover:text-white'
                }`}
              >
                {m === 'create' ? 'New Call' : 'Join Call'}
              </button>
            ))}
          </div>

          <div className="space-y-4">
            <div>
              <label className="text-xs font-medium text-surface-400 uppercase tracking-wider block mb-1.5">
                Your Name
              </label>
              <input
                value={name}
                onChange={e => setName(e.target.value)}
                placeholder="Enter your name"
                className="
                  w-full bg-surface-800 border border-surface-600 text-white
                  rounded-xl px-4 py-3 text-sm placeholder:text-surface-500
                  focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-transparent
                  transition-colors
                "
                onKeyDown={e => e.key === 'Enter' && (mode === 'create' ? handleCreate() : handleJoinCode())}
              />
            </div>

            <LanguageSelector
              value={language}
              onChange={setLanguage}
              label="Your Language"
            />

            {mode === 'create' && (
              <div>
                <label className="text-xs font-medium text-surface-400 uppercase tracking-wider block mb-1.5">
                  Conversation Domain
                </label>
                <div className="grid grid-cols-3 gap-2">
                  {DOMAINS.map(d => (
                    <button
                      key={d.value}
                      onClick={() => setDomain(d.value)}
                      className={`
                        flex flex-col items-center gap-1 p-2 rounded-xl border text-xs transition-all
                        ${domain === d.value
                          ? 'bg-brand-600/20 border-brand-500 text-brand-300'
                          : 'bg-surface-800 border-surface-600 text-surface-400 hover:border-surface-500'
                        }
                      `}
                    >
                      <span>{d.icon}</span>
                      <span>{d.label}</span>
                    </button>
                  ))}
                </div>
              </div>
            )}

            {mode === 'join' && (
              <div className="space-y-3">
                {/* Live sessions */}
                <div>
                  <div className="flex items-center justify-between mb-2">
                    <label className="text-xs font-medium text-surface-400 uppercase tracking-wider">
                      Waiting to Connect
                    </label>
                    <button
                      onClick={fetchSessions}
                      className="text-surface-500 hover:text-surface-300 transition-colors"
                      title="Refresh"
                    >
                      <svg className={`w-3.5 h-3.5 ${sessionsLoading ? 'animate-spin' : ''}`} fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
                      </svg>
                    </button>
                  </div>
                  {waitingSessions.length === 0 ? (
                    <div className="bg-surface-800 border border-surface-700 rounded-xl px-4 py-5 text-center">
                      <p className="text-surface-500 text-sm">No one waiting right now</p>
                      <p className="text-surface-600 text-xs mt-0.5">Refreshes every 5 seconds</p>
                    </div>
                  ) : (
                    <div className="space-y-2">
                      {waitingSessions.map(s => (
                        <SessionCard
                          key={s.id}
                          session={s}
                          onJoin={doJoin}
                          disabled={loading}
                        />
                      ))}
                    </div>
                  )}
                </div>

                {/* Manual entry */}
                <div>
                  <label className="text-xs font-medium text-surface-400 uppercase tracking-wider block mb-1.5">
                    Or Enter Session Code
                  </label>
                  <input
                    value={joinCode}
                    onChange={e => setJoinCode(e.target.value)}
                    placeholder="Paste session ID or invite link"
                    className="
                      w-full bg-surface-800 border border-surface-600 text-white font-mono
                      rounded-xl px-4 py-3 text-sm placeholder:text-surface-500
                      focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-transparent
                      transition-colors
                    "
                    onKeyDown={e => e.key === 'Enter' && handleJoinCode()}
                  />
                </div>
              </div>
            )}

            <button
              onClick={mode === 'create' ? handleCreate : handleJoinCode}
              disabled={loading}
              className="
                w-full py-3.5 bg-brand-600 hover:bg-brand-500 text-white font-semibold
                rounded-xl transition-all disabled:opacity-50 disabled:cursor-not-allowed
                shadow-lg shadow-brand-900/50 hover:shadow-brand-900/70
                hover:scale-[1.02] active:scale-[0.98]
              "
            >
              {loading ? 'Connecting...' : mode === 'create' ? 'Start Call' : 'Join with Code'}
            </button>
          </div>
        </div>

        {/* Stats */}
        <div className="flex items-center gap-8 mt-12 text-center">
          {[
            { label: 'Languages', value: '20+' },
            { label: 'Avg Latency', value: '< 2s' },
            { label: 'Accuracy', value: '98%+' },
          ].map(s => (
            <div key={s.label}>
              <div className="text-2xl font-bold text-brand-400">{s.value}</div>
              <div className="text-xs text-surface-500 mt-0.5">{s.label}</div>
            </div>
          ))}
        </div>
      </div>

      <footer className="text-center py-4 text-xs text-surface-600 border-t border-surface-800">
        Voice Translation Platform · Powered by OpenAI · Built for real conversations
      </footer>
    </div>
  );
}
