'use client';

import { use } from 'react';
import { useSearchParams } from 'next/navigation';
import { CallInterface } from '@/components/CallInterface';

interface PageProps {
  params: Promise<{ id: string }>;
}

export default function CallPage({ params }: PageProps) {
  const { id: sessionId } = use(params);
  const searchParams = useSearchParams();

  const participantId = searchParams.get('pid') || '';
  const name = searchParams.get('name') || 'Participant';
  const lang = searchParams.get('lang') || 'en';
  const autostart = searchParams.get('autostart') === 'true';

  if (!participantId) {
    return (
      <div className="min-h-screen bg-surface-950 flex items-center justify-center">
        <div className="text-center">
          <p className="text-white text-lg mb-2">Invalid session link</p>
          <a href="/" className="text-brand-400 hover:text-brand-300 text-sm">
            ← Back to home
          </a>
        </div>
      </div>
    );
  }

  return (
    <CallInterface
      sessionId={sessionId}
      participantId={participantId}
      myName={name}
      myLanguage={lang}
      autostart={autostart}
    />
  );
}
