'use client';

import { WSMessage, MessageType } from '@/types';

type MessageHandler = (msg: WSMessage) => void;
type BinaryHandler = (data: ArrayBuffer) => void;

function getWsBase(): string {
  // Env var set karo production mein
  if (process.env.NEXT_PUBLIC_WS_URL) return process.env.NEXT_PUBLIC_WS_URL;

  if (typeof window === 'undefined') return 'ws://localhost:8000';

  const proto = window.location.protocol === 'https:' ? 'wss' : 'ws';
  const hostname = window.location.hostname;

  // Next.js dev/prod port 3000 pe chalta hai → backend 8000 pe hai
  // Nginx 8080 pe chalta hai → woh proxy karta hai
  if (window.location.port === '3000') {
    return `${proto}://${hostname}:8000`;
  }

  // Nginx (port 8080) ya koi aur proxy
  return `${proto}://${window.location.host}`;
}

function getWsUrl(sessionId: string, participantId: string): string {
  return `${getWsBase()}/ws/${sessionId}/${participantId}`;
}

export class TranslationWebSocket {
  private ws: WebSocket | null = null;
  private handlers = new Map<MessageType | 'binary', Set<MessageHandler | BinaryHandler>>();
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  private pingTimer: ReturnType<typeof setInterval> | null = null;
  private _sessionId: string;
  private _participantId: string;
  private _reconnectAttempts = 0;
  private _maxReconnects = 5;
  private _closed = false;

  constructor(sessionId: string, participantId: string) {
    this._sessionId = sessionId;
    this._participantId = participantId;
  }

  connect(): Promise<void> {
    return new Promise((resolve, reject) => {
      const url = getWsUrl(this._sessionId, this._participantId);
      console.log('[WS] Connecting to:', url);
      this.ws = new WebSocket(url);
      this.ws.binaryType = 'arraybuffer';

      this.ws.onopen = () => {
        console.log('[WS] Connected');
        this._reconnectAttempts = 0;
        this._startPing();
        resolve();
      };

      this.ws.onmessage = (event) => {
        if (event.data instanceof ArrayBuffer) {
          this._emit('binary' as MessageType, event.data as unknown as WSMessage);
          return;
        }
        try {
          const msg: WSMessage = JSON.parse(event.data);
          this._emit(msg.type, msg);
        } catch {
          // ignore malformed messages
        }
      };

      this.ws.onclose = (event) => {
        console.log('[WS] Closed:', event.code);
        this._stopPing();
        if (!this._closed && this._reconnectAttempts < this._maxReconnects) {
          const delay = Math.min(1000 * 2 ** this._reconnectAttempts, 10000);
          this._reconnectAttempts++;
          this.reconnectTimer = setTimeout(() => this.connect().catch(() => {}), delay);
        }
      };

      this.ws.onerror = (err) => {
        console.error('[WS] Error:', err);
        reject(new Error('WebSocket connection failed'));
      };
    });
  }

  on(type: MessageType, handler: MessageHandler): () => void {
    if (!this.handlers.has(type)) this.handlers.set(type, new Set());
    this.handlers.get(type)!.add(handler as MessageHandler);
    return () => this.handlers.get(type)?.delete(handler as MessageHandler);
  }

  onBinary(handler: BinaryHandler): () => void {
    const key = 'binary' as MessageType;
    if (!this.handlers.has(key)) this.handlers.set(key, new Set());
    this.handlers.get(key)!.add(handler as unknown as MessageHandler);
    return () => this.handlers.get(key)?.delete(handler as unknown as MessageHandler);
  }

  private _emit(type: MessageType, data: WSMessage) {
    this.handlers.get(type)?.forEach(h => h(data));
  }

  send(type: MessageType, data?: Record<string, unknown>) {
    if (this.ws?.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify({ type, data: data ?? {} }));
    }
  }

  sendBinary(data: ArrayBuffer | Uint8Array) {
    if (this.ws?.readyState === WebSocket.OPEN) {
      this.ws.send(data);
    }
  }

  sendAudio(pcmBuffer: ArrayBuffer) { this.sendBinary(pcmBuffer); }
  mute() { this.send('mute'); }
  unmute() { this.send('unmute'); }
  flush() { this.send('flush'); }

  private _startPing() {
    this.pingTimer = setInterval(() => this.send('ping'), 20000);
  }

  private _stopPing() {
    if (this.pingTimer) { clearInterval(this.pingTimer); this.pingTimer = null; }
  }

  disconnect() {
    this._closed = true;
    this._stopPing();
    if (this.reconnectTimer) clearTimeout(this.reconnectTimer);
    this.ws?.close();
    this.ws = null;
  }

  get isConnected() { return this.ws?.readyState === WebSocket.OPEN; }
}
