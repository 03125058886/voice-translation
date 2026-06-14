# Voice Translation Platform

Real-time bidirectional voice translation enabling two people speaking different languages to communicate naturally via live voice calls.

## Architecture

```
Browser A (English) ←→ WebSocket ←→ FastAPI Backend ←→ WebSocket ←→ Browser B (Spanish)
                                          │
                         ┌───────────────┼───────────────┐
                         ▼               ▼               ▼
                   OpenAI Whisper    GPT-4o          OpenAI TTS
                   (Speech-to-Text) (Translation)  (Text-to-Speech)
```

**Pipeline per speaker utterance:**
1. Browser captures PCM audio → streams to backend via WebSocket
2. VAD (Voice Activity Detection) detects speech segments
3. Whisper transcribes the speech segment
4. GPT-4o translates with conversation context
5. OpenAI TTS synthesizes translated audio
6. Audio sent back to other participant's browser and played

## Stack

| Layer | Technology |
|-------|-----------|
| Backend API | FastAPI + WebSockets |
| Speech-to-Text | OpenAI Whisper |
| Translation | GPT-4o (context-aware) |
| Text-to-Speech | OpenAI TTS-HD / ElevenLabs |
| State | Redis |
| Database | PostgreSQL |
| Frontend | Next.js 15 + Tailwind CSS |
| Proxy | Nginx |
| Telephony | Twilio (optional) |
| Containers | Docker Compose |

## Quick Start

### 1. Set up environment variables

```bash
cp .env.example .env
# Edit .env and add your OPENAI_API_KEY
```

### 2. Run with Docker Compose

```bash
docker compose up --build
```

Open [http://localhost](http://localhost) in **two browser tabs** (or on two devices).

### 3. Make a call

**Tab 1:**
- Enter your name, select English
- Click **Start Call**
- Copy the invite link

**Tab 2:**
- Open the invite link
- Enter a name, select Spanish
- Click **Join Call**

Both participants speak naturally — translations happen in real time.

## Local Development (without Docker)

### Backend

```bash
cd backend
python -m venv venv
venv\Scripts\activate  # Windows
pip install -r requirements.txt
cp .env.example .env   # Add your OPENAI_API_KEY
uvicorn app.main:app --reload --port 8000
```

### Frontend

```bash
cd frontend
npm install
npm run dev
```

Open [http://localhost:3000](http://localhost:3000)

## Supported Languages

English, Spanish, French, German, Italian, Portuguese, Russian, Chinese,
Japanese, Korean, Arabic, Hindi, Urdu, Turkish, Dutch, Polish,
Swedish, Norwegian, Danish, Finnish

## Conversation Domains

Domain-specific prompting improves translation quality for specialized fields:

| Domain | Use Case |
|--------|----------|
| General | Everyday conversations |
| Medical | Patient/doctor consultations |
| Legal | Legal proceedings, contracts |
| Business | Meetings, negotiations |
| Travel | Tourist assistance |
| Customer Support | Service interactions |

## API Reference

### REST Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/sessions` | Create a new session |
| POST | `/api/sessions/{id}/join` | Join an existing session |
| GET | `/api/sessions/{id}` | Get session details |
| GET | `/api/sessions/{id}/transcript` | Get full transcript |
| DELETE | `/api/sessions/{id}` | End session |
| GET | `/api/languages` | List supported languages |
| GET | `/health` | Health check |

### WebSocket Protocol

Connect: `ws://host/ws/{session_id}/{participant_id}`

**Client → Server:**
```json
// Stream audio (raw PCM-16 binary frames)

// Control messages
{"type": "mute"}
{"type": "unmute"}
{"type": "flush"}
{"type": "ping"}
```

**Server → Client:**
```json
{"type": "session_info", "data": {...}}
{"type": "transcript_final", "data": {"text": "Hello", "language": "en"}}
{"type": "translation", "data": {"original_text": "...", "translated_text": "..."}}
{"type": "audio_response", "data": {"audio": "<base64>", "format": "mp3"}}
{"type": "participant_joined", "data": {"name": "...", "language": "es"}}
{"type": "pipeline_status", "data": {"stage": "translating"}}
```

## Performance

- Typical end-to-end latency: **1.5 – 2.5 seconds**
- Breakdown: STT ~600ms + Translation ~400ms + TTS ~500ms
- For lower latency: use ElevenLabs Turbo + stream TTS output

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `OPENAI_API_KEY` | Yes | OpenAI API key |
| `TTS_PROVIDER` | No | `openai` (default) or `elevenlabs` |
| `ELEVENLABS_API_KEY` | No | ElevenLabs key for premium TTS |
| `TWILIO_ACCOUNT_SID` | No | Twilio for phone call support |
| `REDIS_URL` | No | Redis URL (default: in-memory) |
| `API_SECRET_KEY` | Yes (prod) | JWT signing secret |

## Roadmap

- [ ] Voice cloning — use caller's own voice characteristics
- [ ] Emotion preservation in synthesis
- [ ] Real-time phone call integration (Twilio Media Streams)
- [ ] Call recording and transcript export (PDF/DOCX)
- [ ] Enterprise SSO integration
- [ ] Sub-1s latency with streaming TTS
- [ ] Mobile apps (iOS/Android)
- [ ] Conference calls (3+ participants, multiple language pairs)
