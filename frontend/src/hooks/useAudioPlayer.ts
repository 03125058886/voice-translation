'use client';

import { useRef, useCallback } from 'react';

export function useAudioPlayer() {
  const playingRef = useRef(false);
  const queueRef = useRef<string[]>([]);

  const playNext = useCallback(() => {
    if (queueRef.current.length === 0) {
      playingRef.current = false;
      return;
    }
    playingRef.current = true;
    const src = queueRef.current.shift()!;
    const audio = new Audio(src);
    audio.onended = playNext;
    audio.onerror = () => {
      console.error('[Audio] playback error, skipping');
      playNext();
    };
    audio.play().catch(err => {
      console.error('[Audio] play() failed:', err);
      playNext();
    });
  }, []);

  // Call this during a user gesture (e.g. Start Call click) to unlock autoplay
  const initContext = useCallback(() => {
    // Tiny silent WAV — unlocks audio policy in Chrome/Safari
    const silent = new Audio(
      'data:audio/wav;base64,UklGRigAAABXQVZFZm10IBIAAAABAAEARKwAAIhYAQACABAAAABkYXRhAgAAAAEA'
    );
    silent.play().catch(() => {});
  }, []);

  const playAudio = useCallback(
    (base64Audio: string, format: string = 'mp3') => {
      if (!base64Audio) return;
      const src = `data:audio/${format};base64,${base64Audio}`;
      queueRef.current.push(src);
      if (!playingRef.current) playNext();
    },
    [playNext]
  );

  return { playAudio, initContext };
}
