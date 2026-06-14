'use client';

import { useRef, useState, useCallback } from 'react';

interface UseAudioCaptureOptions {
  sampleRate?: number;
  chunkMs?: number;
  onChunk: (pcmBuffer: ArrayBuffer) => void;
}

export function useAudioCapture({
  sampleRate = 16000,
  chunkMs = 100,
  onChunk,
}: UseAudioCaptureOptions) {
  const [isCapturing, setIsCapturing] = useState(false);
  const [volume, setVolume] = useState(0);
  const contextRef = useRef<AudioContext | null>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const processorRef = useRef<ScriptProcessorNode | null>(null);
  const sourceRef = useRef<MediaStreamAudioSourceNode | null>(null);
  const analyserRef = useRef<AnalyserNode | null>(null);
  const animRef = useRef<number | null>(null);

  const start = useCallback(async () => {
    if (isCapturing) return;
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        audio: {
          sampleRate,
          channelCount: 1,
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true,
        },
      });
      streamRef.current = stream;

      const ctx = new AudioContext({ sampleRate });
      contextRef.current = ctx;

      const source = ctx.createMediaStreamSource(stream);
      sourceRef.current = source;

      const analyser = ctx.createAnalyser();
      analyser.fftSize = 256;
      analyserRef.current = analyser;
      source.connect(analyser);

      // createScriptProcessor requires power of 2 (256,512,1024,2048,4096,8192,16384)
      const rawSize = Math.floor((sampleRate * chunkMs) / 1000);
      const bufferSize = Math.pow(2, Math.ceil(Math.log2(Math.max(256, rawSize))));
      const processor = ctx.createScriptProcessor(bufferSize, 1, 1);
      processorRef.current = processor;

      processor.onaudioprocess = (e) => {
        const floatData = e.inputBuffer.getChannelData(0);
        const pcm16 = new Int16Array(floatData.length);
        for (let i = 0; i < floatData.length; i++) {
          pcm16[i] = Math.max(-32768, Math.min(32767, Math.round(floatData[i] * 32767)));
        }
        onChunk(pcm16.buffer);
      };

      source.connect(processor);
      processor.connect(ctx.destination);

      const trackVolume = () => {
        const data = new Uint8Array(analyser.frequencyBinCount);
        analyser.getByteFrequencyData(data);
        const avg = data.reduce((a, b) => a + b, 0) / data.length;
        setVolume(avg / 128);
        animRef.current = requestAnimationFrame(trackVolume);
      };
      trackVolume();

      setIsCapturing(true);
    } catch (err) {
      console.error('Microphone access denied:', err);
      throw err;
    }
  }, [isCapturing, sampleRate, chunkMs, onChunk]);

  const stop = useCallback(() => {
    if (animRef.current) cancelAnimationFrame(animRef.current);
    processorRef.current?.disconnect();
    sourceRef.current?.disconnect();
    analyserRef.current?.disconnect();
    streamRef.current?.getTracks().forEach(t => t.stop());
    contextRef.current?.close();

    processorRef.current = null;
    sourceRef.current = null;
    analyserRef.current = null;
    streamRef.current = null;
    contextRef.current = null;

    setIsCapturing(false);
    setVolume(0);
  }, []);

  return { start, stop, isCapturing, volume };
}
