'use client';

import { PipelineStage } from '@/types';
import { cn } from '@/lib/utils';

interface Props {
  volume: number;
  stage: PipelineStage;
  isActive: boolean;
  label?: string;
}

const STAGE_COLORS: Record<PipelineStage, string> = {
  idle: 'bg-surface-600',
  recording: 'bg-green-500',
  transcribing: 'bg-yellow-500',
  translating: 'bg-brand-500',
  synthesizing: 'bg-purple-500',
  playing: 'bg-cyan-500',
};

const STAGE_LABELS: Record<PipelineStage, string> = {
  idle: 'Ready',
  recording: 'Listening...',
  transcribing: 'Transcribing...',
  translating: 'Translating...',
  synthesizing: 'Generating voice...',
  playing: 'Playing...',
};

const BAR_COUNT = 20;

export function AudioVisualizer({ volume, stage, isActive, label }: Props) {
  const barColor = STAGE_COLORS[stage];
  const bars = Array.from({ length: BAR_COUNT }, (_, i) => {
    const center = BAR_COUNT / 2;
    const distance = Math.abs(i - center) / center;
    const baseHeight = 0.15 + (1 - distance) * 0.25;
    const animated = isActive && stage === 'recording';
    const height = animated
      ? baseHeight + volume * (1 - distance * 0.5) * 0.8
      : baseHeight;
    return Math.min(1, height);
  });

  return (
    <div className="flex flex-col items-center gap-3">
      <div className="flex items-end justify-center gap-0.5 h-16">
        {bars.map((h, i) => (
          <div
            key={i}
            className={cn('w-1.5 rounded-full transition-all', barColor, {
              'animate-wave': isActive && stage === 'recording',
              'opacity-30': !isActive,
            })}
            style={{
              height: `${h * 100}%`,
              animationDelay: `${i * 0.05}s`,
              minHeight: '4px',
            }}
          />
        ))}
      </div>
      <div className="flex items-center gap-2">
        <div
          className={cn('w-2 h-2 rounded-full', barColor, {
            'animate-pulse': isActive && stage !== 'idle',
          })}
        />
        <span className="text-xs text-surface-500 font-medium">
          {label || STAGE_LABELS[stage]}
        </span>
      </div>
    </div>
  );
}
