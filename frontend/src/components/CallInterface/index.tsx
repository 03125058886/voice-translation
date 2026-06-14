'use client';

import { useRouter } from 'next/navigation';
import { useTranslationSession } from '@/hooks/useTranslationSession';
import { TranscriptPanel } from '@/components/TranscriptPanel';
import { getLanguageFlag, getLanguageName } from '@/lib/utils';
import { cn } from '@/lib/utils';
import { Mic, MicOff, PhoneOff, Copy, Check } from 'lucide-react';
import { useState, useCallback, useEffect, useRef } from 'react';
import { PipelineStage } from '@/types';
import toast from 'react-hot-toast';

interface Props {
  sessionId: string;
  participantId: string;
  myName: string;
  myLanguage: string;
  autostart?: boolean;
}

function SpeakingRings({ active }: { active: boolean }) {
  if (!active) return null;
  return (
    <div className="absolute inset-0 rounded-full">
      <span className="absolute inset-0 rounded-full animate-ping bg-green-400 opacity-20" />
      <span className="absolute inset-[-6px] rounded-full animate-ping bg-green-400 opacity-10 [animation-delay:150ms]" />
    </div>
  );
}

function StatusLabel({ stage, name }: { stage: PipelineStage; name: string }) {
  if (stage === 'idle') return null;
  const map: Record<string, { text: string; color: string }> = {
    recording:    { text: 'Speaking…',          color: 'text-green-400' },
    transcribing: { text: 'Listening…',         color: 'text-blue-400' },
    translating:  { text: 'Translating…',       color: 'text-yellow-400' },
    synthesizing: { text: 'Preparing audio…',   color: 'text-purple-400' },
    playing:      { text: 'Playing…',           color: 'text-brand-400' },
  };
  const entry = map[stage];
  if (!entry) return null;
  return (
    <span className={cn('text-xs font-medium animate-pulse', entry.color)}>
      {entry.text}
    </span>
  );
}

function Avatar({
  name,
  color,
  size = 'lg',
  speaking = false,
}: {
  name: string;
  color: string;
  size?: 'lg' | 'sm';
  speaking?: boolean;
}) {
  const dim = size === 'lg' ? 'w-20 h-20 text-2xl' : 'w-12 h-12 text-base';
  return (
    <div className={cn('relative flex items-center justify-center rounded-full shrink-0', dim, color)}>
      <SpeakingRings active={speaking} />
      <span className="relative z-10 font-bold">{name[0]?.toUpperCase()}</span>
    </div>
  );
}

export function CallInterface({ sessionId, participantId, myName, myLanguage, autostart }: Props) {
  const router = useRouter();
  const [copied, setCopied] = useState(false);
  const [micStarted, setMicStarted] = useState(false);
  const [showAutostart, setShowAutostart] = useState(!!autostart);
  const startBtnRef = useRef<HTMLButtonElement>(null);

  const { state, volume, isCapturing, startCall, endCall, toggleMute } =
    useTranslationSession({ sessionId, participantId, myName, myLanguage });

  const handleStartMic = useCallback(async () => {
    try {
      await startCall();
      setMicStarted(true);
      setShowAutostart(false);
      toast.success('Microphone active — start speaking!');
    } catch {
      toast.error('Could not access microphone. Please check permissions.');
    }
  }, [startCall]);

  const handleEnd = useCallback(() => {
    endCall();
    router.push('/');
  }, [endCall, router]);

  const copyInviteLink = useCallback(() => {
    const url = `${window.location.origin}/join/${sessionId}`;
    navigator.clipboard.writeText(url);
    setCopied(true);
    toast.success('Invite link copied!');
    setTimeout(() => setCopied(false), 2000);
  }, [sessionId]);

  useEffect(() => {
    if (showAutostart) startBtnRef.current?.focus();
  }, [showAutostart]);

  const myStage = state.pipelineStage;
  const otherStage = state.otherPipelineStage;
  const mySpeaking = isCapturing && !state.isMuted && myStage === 'recording';
  const otherSpeaking = otherStage === 'recording';

  return (
    <div className="flex flex-col h-screen bg-surface-950 text-white">

      {/* Autostart overlay */}
      {showAutostart && (
        <div className="fixed inset-0 z-50 bg-surface-950/95 flex items-center justify-center">
          <div className="text-center px-6">
            <div className="w-24 h-24 bg-green-600/20 border-2 border-green-500 rounded-full flex items-center justify-center mx-auto mb-6">
              <Mic className="w-12 h-12 text-green-400 animate-pulse" />
            </div>
            <h2 className="text-2xl font-bold mb-2">You're in the call!</h2>
            <p className="text-surface-400 mb-8 text-sm max-w-xs mx-auto">
              Tap below to allow microphone access and start speaking.
            </p>
            <button
              ref={startBtnRef}
              onClick={handleStartMic}
              className="px-10 py-4 bg-green-600 hover:bg-green-500 text-white font-bold text-lg rounded-2xl transition-all shadow-lg hover:scale-105 active:scale-95"
            >
              Start Speaking
            </button>
            <button
              onClick={() => setShowAutostart(false)}
              className="block mt-4 mx-auto text-sm text-surface-500 hover:text-surface-300 transition-colors"
            >
              Continue without mic
            </button>
          </div>
        </div>
      )}

      {/* Top bar */}
      <header className="flex items-center justify-between px-5 py-3 border-b border-surface-800 bg-surface-900/80 backdrop-blur shrink-0">
        <div className="flex items-center gap-2.5">
          <div className="w-7 h-7 bg-brand-600 rounded-lg flex items-center justify-center text-xs font-bold">VT</div>
          <div>
            <p className="text-xs font-semibold">Voice Translation</p>
            <p className="text-[10px] text-surface-500 font-mono">{sessionId.slice(0, 8)}…</p>
          </div>
        </div>
        <div className="flex items-center gap-3">
          <div className={cn(
            'flex items-center gap-1 text-xs font-medium',
            state.status === 'active' ? 'text-green-400' :
            state.status === 'waiting' ? 'text-yellow-400' : 'text-surface-500'
          )}>
            <span className={cn(
              'w-1.5 h-1.5 rounded-full',
              state.status === 'active' ? 'bg-green-400 animate-pulse' :
              state.status === 'waiting' ? 'bg-yellow-400' : 'bg-surface-500'
            )} />
            {state.status === 'active' ? 'Live' : state.status === 'waiting' ? 'Waiting' : 'Ended'}
          </div>
          <button
            onClick={copyInviteLink}
            className="flex items-center gap-1 text-xs text-surface-400 hover:text-white transition-colors"
          >
            {copied ? <Check className="w-3.5 h-3.5 text-green-400" /> : <Copy className="w-3.5 h-3.5" />}
            {copied ? 'Copied!' : 'Invite'}
          </button>
        </div>
      </header>

      {/* Main area */}
      <div className="flex flex-1 overflow-hidden">

        {/* Left — Call */}
        <div className="flex flex-col w-72 shrink-0 border-r border-surface-800 bg-surface-900">

          {/* Participants */}
          <div className="flex-1 flex flex-col items-center justify-center gap-8 p-6">

            {/* Other participant */}
            <div className="flex flex-col items-center gap-3">
              {state.otherName ? (
                <>
                  <Avatar
                    name={state.otherName}
                    color="bg-purple-700/40 border-2 border-purple-600/50 text-purple-200"
                    size="lg"
                    speaking={otherSpeaking}
                  />
                  <div className="text-center">
                    <p className="font-semibold text-sm">{state.otherName}</p>
                    <p className="text-xs text-surface-500 mt-0.5">
                      {state.otherLanguage && getLanguageFlag(state.otherLanguage)}{' '}
                      {state.otherLanguage && getLanguageName(state.otherLanguage)}
                    </p>
                    <div className="mt-1.5 h-4">
                      <StatusLabel stage={otherStage} name={state.otherName} />
                    </div>
                  </div>
                </>
              ) : (
                <div className="flex flex-col items-center gap-3">
                  <div className="w-20 h-20 rounded-full border-2 border-dashed border-surface-600 flex items-center justify-center">
                    <span className="text-surface-600 text-2xl">?</span>
                  </div>
                  <div className="text-center">
                    <p className="text-sm text-surface-500">Waiting for someone…</p>
                    <button
                      onClick={copyInviteLink}
                      className="mt-2 text-xs text-brand-400 hover:text-brand-300 transition-colors"
                    >
                      Copy invite link →
                    </button>
                  </div>
                </div>
              )}
            </div>

            {/* Divider */}
            <div className="w-full flex items-center gap-3">
              <div className="flex-1 h-px bg-surface-700" />
              <span className="text-xs text-surface-600">YOU</span>
              <div className="flex-1 h-px bg-surface-700" />
            </div>

            {/* Me */}
            <div className="flex flex-col items-center gap-3">
              <div className="relative">
                <Avatar
                  name={myName}
                  color="bg-brand-700/40 border-2 border-brand-600/50 text-brand-200"
                  size="lg"
                  speaking={mySpeaking}
                />
                {/* Volume ring */}
                {isCapturing && !state.isMuted && (
                  <div
                    className="absolute inset-0 rounded-full border-2 border-green-400 transition-all duration-75"
                    style={{ transform: `scale(${1 + volume * 0.3})`, opacity: volume * 0.8 + 0.2 }}
                  />
                )}
              </div>
              <div className="text-center">
                <p className="font-semibold text-sm">{myName} (You)</p>
                <p className="text-xs text-surface-500 mt-0.5">
                  {getLanguageFlag(myLanguage)} {getLanguageName(myLanguage)}
                </p>
                <div className="mt-1.5 h-4">
                  <StatusLabel stage={myStage} name={myName} />
                </div>
              </div>
            </div>
          </div>

          {/* Controls */}
          <div className="p-5 border-t border-surface-800">
            {!micStarted ? (
              <button
                onClick={handleStartMic}
                className="w-full py-3.5 bg-green-600 hover:bg-green-500 text-white font-semibold rounded-2xl transition-all hover:scale-105 active:scale-95 flex items-center justify-center gap-2 shadow-lg shadow-green-900/40"
              >
                <Mic className="w-5 h-5" />
                {state.isConnected ? 'Start Mic' : 'Connecting…'}
              </button>
            ) : (
              <div className="flex items-center justify-center gap-4">
                <button
                  onClick={toggleMute}
                  className={cn(
                    'w-14 h-14 rounded-full flex items-center justify-center transition-all hover:scale-105 active:scale-95',
                    state.isMuted
                      ? 'bg-red-600/20 border-2 border-red-500 text-red-400'
                      : 'bg-surface-700 hover:bg-surface-600 text-white'
                  )}
                  title={state.isMuted ? 'Unmute' : 'Mute'}
                >
                  {state.isMuted ? <MicOff className="w-5 h-5" /> : <Mic className="w-5 h-5" />}
                </button>
                <button
                  onClick={handleEnd}
                  className="w-16 h-16 rounded-full bg-red-600 hover:bg-red-500 flex items-center justify-center transition-all shadow-lg shadow-red-900/50 hover:scale-105 active:scale-95"
                  title="End call"
                >
                  <PhoneOff className="w-6 h-6" />
                </button>
              </div>
            )}
            <div className="mt-3 flex items-center justify-center gap-1.5 text-[10px] text-surface-600">
              <span className={cn('w-1.5 h-1.5 rounded-full', state.isConnected ? 'bg-green-500' : 'bg-surface-600')} />
              <span>{state.isConnected ? 'Connected · STT → Translate → TTS' : 'Connecting…'}</span>
            </div>
          </div>
        </div>

        {/* Right — Transcript */}
        <div className="flex-1 overflow-hidden bg-surface-950">
          <TranscriptPanel
            entries={state.transcript}
            myLanguage={myLanguage}
            otherLanguage={state.otherLanguage}
            partialText={state.partialText}
            otherName={state.otherName}
          />
        </div>
      </div>
    </div>
  );
}
