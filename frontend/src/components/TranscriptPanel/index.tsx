'use client';

import { useEffect, useRef } from 'react';
import { TranscriptDisplayEntry } from '@/types';
import { formatTime, getLanguageName, getLanguageFlag } from '@/lib/utils';
import { cn } from '@/lib/utils';

interface Props {
  entries: TranscriptDisplayEntry[];
  myLanguage: string;
  otherLanguage: string | null;
  partialText?: string;
  otherName?: string | null;
}

function TranscriptBubble({ entry }: { entry: TranscriptDisplayEntry }) {
  const isLocal = entry.isLocal;
  return (
    <div className={cn('flex flex-col gap-1 animate-slide-up', isLocal ? 'items-end' : 'items-start')}>
      <div className="flex items-center gap-2 px-1">
        <span className="text-xs text-surface-500">
          {getLanguageFlag(entry.sourceLang)} {entry.speakerName}
        </span>
        <span className="text-xs text-surface-600">{formatTime(entry.timestamp)}</span>
      </div>
      <div className={cn(
        'max-w-[85%] rounded-2xl px-4 py-3 space-y-2',
        isLocal
          ? 'bg-brand-700/30 border border-brand-600/30 rounded-tr-sm'
          : 'bg-surface-700/50 border border-surface-600/30 rounded-tl-sm'
      )}>
        <p className="text-sm text-white leading-relaxed">{entry.originalText}</p>
        <div className="h-px bg-surface-600/50" />
        <div className="flex items-start gap-2">
          <span className="text-xs shrink-0 mt-0.5">{getLanguageFlag(entry.targetLang)}</span>
          <p className="text-sm text-brand-300 leading-relaxed italic">{entry.translatedText}</p>
        </div>
      </div>
    </div>
  );
}

function PartialBubble({ text, name }: { text: string; name: string }) {
  return (
    <div className="flex flex-col gap-1 items-start animate-slide-up">
      <div className="flex items-center gap-2 px-1">
        <span className="text-xs text-surface-500">{name}</span>
        <span className="text-xs text-green-500 animate-pulse">● live</span>
      </div>
      <div className="max-w-[85%] rounded-2xl rounded-tl-sm px-4 py-3 bg-surface-700/30 border border-surface-600/20">
        <p className="text-sm text-surface-300 leading-relaxed">
          {text}
          <span className="inline-block w-0.5 h-4 bg-surface-400 ml-0.5 animate-pulse align-middle" />
        </p>
      </div>
    </div>
  );
}

export function TranscriptPanel({ entries, myLanguage, otherLanguage, partialText, otherName }: Props) {
  const bottomRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [entries, partialText]);

  return (
    <div className="flex flex-col h-full">
      <div className="flex items-center justify-between px-4 py-3 border-b border-surface-700 shrink-0">
        <h3 className="text-sm font-semibold text-white">Live Transcript</h3>
        <div className="flex items-center gap-3 text-xs text-surface-500">
          {myLanguage && <span>{getLanguageFlag(myLanguage)} {getLanguageName(myLanguage)}</span>}
          {otherLanguage && (
            <>
              <span className="text-surface-600">↔</span>
              <span>{getLanguageFlag(otherLanguage)} {getLanguageName(otherLanguage)}</span>
            </>
          )}
        </div>
      </div>

      <div className="flex-1 overflow-y-auto p-4 space-y-4 scrollbar-thin scrollbar-thumb-surface-600">
        {entries.length === 0 && !partialText ? (
          <div className="flex flex-col items-center justify-center h-full text-center gap-3">
            <div className="text-4xl">🎙</div>
            <p className="text-sm text-surface-500">Conversation transcript will appear here.</p>
            <p className="text-xs text-surface-600">Start speaking — words appear in real time.</p>
          </div>
        ) : (
          <>
            {entries.map(entry => (
              <TranscriptBubble key={entry.id} entry={entry} />
            ))}
            {partialText && otherName && (
              <PartialBubble text={partialText} name={otherName} />
            )}
          </>
        )}
        <div ref={bottomRef} />
      </div>
    </div>
  );
}
