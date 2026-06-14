'use client';

import { use, useState } from 'react';
import { useRouter } from 'next/navigation';
import { LanguageSelector } from '@/components/LanguageSelector';
import { api } from '@/lib/api';
import toast from 'react-hot-toast';

interface PageProps {
  params: Promise<{ id: string }>;
}

export default function JoinPage({ params }: PageProps) {
  const { id: sessionId } = use(params);
  const router = useRouter();
  const [name, setName] = useState('');
  const [language, setLanguage] = useState('es');
  const [loading, setLoading] = useState(false);

  const handleJoin = async () => {
    if (!name.trim()) { toast.error('Please enter your name'); return; }
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
    <div className="min-h-screen bg-surface-950 flex items-center justify-center px-4">
      <div className="w-full max-w-sm bg-surface-900 border border-surface-700 rounded-2xl p-6 shadow-2xl">
        <div className="text-center mb-6">
          <div className="w-12 h-12 bg-brand-600 rounded-xl flex items-center justify-center text-xl font-bold mx-auto mb-3">
            VT
          </div>
          <h1 className="text-xl font-bold">You're invited to a call</h1>
          <p className="text-sm text-surface-400 mt-1">Enter your details to join</p>
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
              autoFocus
              className="
                w-full bg-surface-800 border border-surface-600 text-white
                rounded-xl px-4 py-3 text-sm placeholder:text-surface-500
                focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-transparent
              "
              onKeyDown={e => e.key === 'Enter' && handleJoin()}
            />
          </div>

          <LanguageSelector
            value={language}
            onChange={setLanguage}
            label="Your Language"
          />

          <button
            onClick={handleJoin}
            disabled={loading}
            className="
              w-full py-3.5 bg-brand-600 hover:bg-brand-500 text-white font-semibold
              rounded-xl transition-all disabled:opacity-50 disabled:cursor-not-allowed
              shadow-lg shadow-brand-900/50
            "
          >
            {loading ? 'Joining...' : 'Join Call'}
          </button>
        </div>
      </div>
    </div>
  );
}
