# VoiceTranslate — Flutter App

Real-time bidirectional voice translation mobile app (Android & iOS).

## Features

- Real-time voice capture and streaming (PCM-16, 16kHz)
- Live audio visualizer with pipeline stage indication
- Bidirectional transcript with original + translated text
- 20 supported languages with flags
- Mute/unmute during call
- Session invite via session ID
- Beautiful dark UI with animated components

## Setup

### 1. Configure backend URL

Edit `lib/config/app_config.dart`:

```dart
// Android emulator → your laptop localhost
static const String apiBaseUrl = 'http://10.0.2.2:8000';

// Physical device → your laptop's IP on same network
static const String apiBaseUrl = 'http://192.168.1.x:8000';

// Production
static const String apiBaseUrl = 'https://your-domain.com';
```

### 2. Install dependencies

```bash
flutter pub get
```

### 3. Run

```bash
# Android
flutter run

# iOS
flutter run --device-id=<your-iphone-id>

# Release build
flutter build apk --release          # Android APK
flutter build appbundle --release    # Android App Bundle
flutter build ipa --release          # iOS
```

## How to Use

1. Open the app
2. Enter your name and select your language
3. Tap **Start Call** — you'll get a Session ID
4. Share the Session ID with the other person
5. They open the app, tap **Join Call**, paste the ID
6. Both speak naturally — translations happen automatically

## Architecture

```
Flutter App
├── lib/
│   ├── main.dart                     # Entry point
│   ├── app.dart                      # MaterialApp
│   ├── config/app_config.dart        # Backend URLs
│   ├── models/session.dart           # Data models
│   ├── services/
│   │   ├── api_service.dart          # REST API (create/join session)
│   │   ├── websocket_service.dart    # WebSocket (audio streaming + events)
│   │   └── audio_service.dart        # Mic recording + TTS playback
│   ├── providers/call_provider.dart  # Riverpod state management
│   ├── screens/
│   │   ├── home_screen.dart          # Landing page
│   │   ├── call_screen.dart          # Active call UI
│   │   └── join_screen.dart          # Join by session ID
│   ├── widgets/
│   │   ├── audio_visualizer.dart     # Animated waveform
│   │   ├── transcript_panel.dart     # Chat-style transcript
│   │   └── language_selector.dart    # Language dropdown
│   └── theme/app_theme.dart          # Dark theme
```

## Audio Pipeline

```
Microphone (16kHz PCM-16)
    ↓
record package (stream chunks every 100ms)
    ↓
WebSocket → Backend (VAD → Whisper → GPT-4o → TTS)
    ↓
Receive base64 MP3 audio
    ↓
just_audio → Speaker
```

## Permissions Required

| Platform | Permission | Reason |
|----------|-----------|--------|
| Android | `RECORD_AUDIO` | Microphone capture |
| Android | `INTERNET` | WebSocket + API |
| iOS | `NSMicrophoneUsageDescription` | Microphone capture |

## Dependencies

| Package | Purpose |
|---------|---------|
| `flutter_riverpod` | State management |
| `record` | Microphone streaming (PCM-16) |
| `just_audio` | Audio playback |
| `web_socket_channel` | WebSocket connection |
| `http` | REST API calls |
| `flutter_animate` | Smooth animations |
| `google_fonts` | Inter font |
| `permission_handler` | Runtime permissions |
| `audio_session` | Audio focus management |
