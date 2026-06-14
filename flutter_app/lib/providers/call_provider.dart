import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/session.dart';
import '../services/api_service.dart';
export '../models/session.dart' show ChatMessage, ChatMessageType;
import '../services/audio_service.dart';
import '../services/websocket_service.dart';

final callProvider = StateNotifierProvider<CallNotifier, CallState>((ref) {
  return CallNotifier();
});

class CallNotifier extends StateNotifier<CallState> {
  CallNotifier() : super(const CallState());

  WebSocketService _ws = WebSocketService();
  AudioService _audio = AudioService();
  final _uuid = const Uuid();

  // --- Session creation ---

  Future<void> createSession({
    required String name,
    required String language,
    String domain = 'general',
    String? callerPhone,
    String? targetPhone,
  }) async {
    state = state.copyWith(myName: name, myLanguage: language, status: SessionStatus.waiting);
    final result = await ApiService.createSession(
      participantName: name,
      participantLanguage: language,
      domain: domain,
      callerPhone: callerPhone,
      targetPhone: targetPhone,
    );
    state = state.copyWith(
      sessionId: result.sessionId,
      participantId: result.participantId,
    );
    await _connectAndStart();
  }

  Future<void> joinSession({
    required String sessionId,
    required String name,
    required String language,
    String? phone,
  }) async {
    state = state.copyWith(myName: name, myLanguage: language, status: SessionStatus.waiting);
    final result = await ApiService.joinSession(
      sessionId: sessionId,
      participantName: name,
      participantLanguage: language,
      phone: phone,
    );
    state = state.copyWith(
      sessionId: result.sessionId,
      participantId: result.participantId,
    );
    await _connectAndStart();
  }

  /// Enter a session that was already created on the server (direct call flow).
  /// [participantId] is the caller's participant ID returned by the backend.
  Future<void> enterAsHost({
    required String sessionId,
    required String participantId,
    required String name,
    required String language,
  }) async {
    state = state.copyWith(
      sessionId: sessionId,
      participantId: participantId,
      myName: name,
      myLanguage: language,
      status: SessionStatus.waiting,
    );
    await _connectAndStart();
  }

  // --- WebSocket + audio ---

  Future<void> _connectAndStart() async {
    // Fresh services for each call
    _ws = WebSocketService();
    _audio = AudioService();
    await _audio.initialize();

    _audio.onChunk = (bytes) => _ws.sendAudio(bytes);
    _audio.onVolume = (v) => state = state.copyWith(volume: v);

    _ws.onConnected = () => state = state.copyWith(isConnected: true);
    _ws.onDisconnected = () => state = state.copyWith(isConnected: false);

    _ws.on('session_info',       _onSessionInfo);
    _ws.on('participant_joined', _onParticipantJoined);
    _ws.on('participant_left',   _onParticipantLeft);
    _ws.on('transcript_partial', _onTranscriptPartial);
    _ws.on('translation',        _onTranslation);
    _ws.on('audio_response',     _onAudioResponse);
    _ws.on('pipeline_status',    _onPipelineStatus);
    _ws.on('chat_message',       _onChatMessage);
    _ws.on('error',              _onError);

    await _ws.connect(state.sessionId!, state.participantId!);
  }

  Future<void> startCapture() async {
    final granted = await _audio.hasPermission();
    if (!granted) throw Exception('Microphone permission denied');
    await _audio.startRecording();
    state = state.copyWith(isCapturing: true);
  }

  // --- Event handlers ---

  void _onSessionInfo(Map<String, dynamic> msg) {
    final data = msg['data'] as Map<String, dynamic>;
    final participants = (data['participants'] as List<dynamic>?)
            ?.map((p) => Participant.fromJson(p as Map<String, dynamic>))
            .toList() ??
        [];
    final other = participants.firstWhere(
      (p) => p.id != state.participantId,
      orElse: () => const Participant(id: '', name: '', language: ''),
    );
    final hasOther = other.id.isNotEmpty;
    state = state.copyWith(
      status: hasOther ? SessionStatus.active : SessionStatus.waiting,
      participants: participants,
      clearOtherParticipant: !hasOther,
      otherName: hasOther ? other.name : null,
      otherLanguage: hasOther ? other.language : null,
    );
  }

  void _onParticipantJoined(Map<String, dynamic> msg) {
    final data = msg['data'] as Map<String, dynamic>;
    state = state.copyWith(
      otherName: data['name'] as String?,
      otherLanguage: data['language'] as String?,
      status: SessionStatus.active,
    );
  }

  void _onParticipantLeft(Map<String, dynamic> msg) {
    state = state.copyWith(
      clearOtherParticipant: true,
      status: SessionStatus.ended,
      otherPipelineStage: PipelineStage.idle,
      partialText: '',
      remoteEnded: true,
    );
  }

  void _onTranscriptPartial(Map<String, dynamic> msg) {
    final data = msg['data'] as Map<String, dynamic>;
    final speakerId = data['participant_id'] as String?;
    if (speakerId != null && speakerId != state.participantId) {
      // Other person is speaking — show their partial text live
      final text = data['text'] as String? ?? '';
      state = state.copyWith(partialText: text);
    }
  }

  void _onTranslation(Map<String, dynamic> msg) {
    final data = msg['data'] as Map<String, dynamic>;
    final isLocal = data['speaker_id'] == state.participantId;

    final entry = TranscriptEntry(
      id: _uuid.v4(),
      speakerId: data['speaker_id'] as String,
      speakerName: data['speaker_name'] as String,
      originalText: data['original_text'] as String,
      translatedText: data['translated_text'] as String,
      sourceLang: data['source_language'] as String,
      targetLang: data['target_language'] as String,
      timestamp: DateTime.now(),
      isLocal: isLocal,
    );

    state = state.copyWith(
      transcript: [...state.transcript, entry],
      partialText: '',  // clear live text once translation arrives
    );
  }

  void _onAudioResponse(Map<String, dynamic> msg) {
    final data = msg['data'] as Map<String, dynamic>;
    final audio = data['audio'] as String?;
    final format = data['format'] as String? ?? 'mp3';
    if (audio != null && audio.isNotEmpty) {
      _audio.playAudioBase64(audio, format: format);
      state = state.copyWith(pipelineStage: PipelineStage.idle);
    }
  }

  void _onPipelineStatus(Map<String, dynamic> msg) {
    final data = msg['data'] as Map<String, dynamic>;
    final stageName = data['stage'] as String? ?? 'idle';
    final stage = PipelineStage.values.firstWhere(
      (s) => s.name == stageName,
      orElse: () => PipelineStage.idle,
    );
    if (data['participant_id'] == state.participantId) {
      state = state.copyWith(pipelineStage: stage);
    } else {
      // Other participant's stage — update their indicator
      state = state.copyWith(otherPipelineStage: stage);
      // Clear partial text when they go back to idle
      if (stage == PipelineStage.idle) {
        state = state.copyWith(partialText: '');
      }
    }
  }

  void _onChatMessage(Map<String, dynamic> msg) {
    final data = msg['data'] as Map<String, dynamic>;
    final chatMsg = ChatMessage.fromJson(data, state.participantId ?? '');
    // Avoid duplicate if we sent it ourselves (broadcast also hits sender)
    if (state.chatMessages.any((m) => m.id == chatMsg.id)) return;
    state = state.copyWith(chatMessages: [...state.chatMessages, chatMsg]);
  }

  void addLocalChatMessage(ChatMessage msg) {
    state = state.copyWith(chatMessages: [...state.chatMessages, msg]);
  }

  void loadChatHistory(List<Map<String, dynamic>> history) {
    final msgs = history
        .map((m) => ChatMessage.fromJson(m, state.participantId ?? ''))
        .toList();
    state = state.copyWith(chatMessages: msgs);
  }

  void _onError(Map<String, dynamic> msg) {
    final data = msg['data'] as Map<String, dynamic>;
    final message = data['message'] as String? ?? 'An error occurred';
    // Store error to show as snackbar — callers listen to state changes
    // We signal via status = error briefly; UI shows SnackBar
    state = state.copyWith(status: SessionStatus.error);
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) state = state.copyWith(status: SessionStatus.active);
    });
    // Log for debugging
    // ignore: avoid_print
    print('[Pipeline error] $message');
  }

  void toggleMute() {
    if (state.isMuted) {
      _audio.unmute();
      _ws.unmute();
      state = state.copyWith(isMuted: false);
    } else {
      _audio.mute();
      _ws.mute();
      state = state.copyWith(isMuted: true);
    }
  }

  Future<void> endCall() async {
    _ws.flush();
    await _audio.stopRecording();
    _ws.dispose();
    await _audio.dispose();
    state = const CallState();
  }

  @override
  void dispose() {
    _ws.dispose();
    _audio.dispose();
    super.dispose();
  }
}
