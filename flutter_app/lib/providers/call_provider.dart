import 'dart:async';
import 'package:flutter/foundation.dart';
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

  Future<void> createSession({
    required String name,
    required String language,
    String domain = 'general',
    String? callerPhone,
    String? targetPhone,
  }) async {
    await _resetCallServices();
    state = const CallState().copyWith(
      myName: name,
      myLanguage: language,
      status: SessionStatus.waiting,
    );
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
    await _resetCallServices();
    state = const CallState().copyWith(
      myName: name,
      myLanguage: language,
      status: SessionStatus.waiting,
    );
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

  Future<void> enterAsHost({
    required String sessionId,
    required String participantId,
    required String name,
    required String language,
  }) async {
    await _resetCallServices();
    state = const CallState().copyWith(
      sessionId: sessionId,
      participantId: participantId,
      myName: name,
      myLanguage: language,
      status: SessionStatus.waiting,
    );
    await _connectAndStart();
  }

  Future<void> _resetCallServices() async {
    _ws.dispose();
    await _audio.dispose();
    _ws = WebSocketService();
    _audio = AudioService();
  }

  Future<void> _connectAndStart() async {
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
    if (!_ws.isConnected) {
      throw Exception('Could not connect to translation server');
    }
    _ws.setLanguage(state.myLanguage);
  }

  Future<void> startCapture() async {
    if (state.isCapturing) return;
    if (!_ws.isConnected) return;
    try {
      await _audio.startRecording();
      state = state.copyWith(isCapturing: true);
      debugPrint('[Call] mic ON');
    } catch (e) {
      debugPrint('[Call] mic failed: $e');
      rethrow;
    }
  }

  void _markActiveAndStartMic() {
    if (state.status != SessionStatus.active) {
      state = state.copyWith(status: SessionStatus.active);
    }
    if (!state.isCapturing) {
      unawaited(startCapture());
    }
  }

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
    if (hasOther) _markActiveAndStartMic();
  }

  void _onParticipantJoined(Map<String, dynamic> msg) {
    final data = msg['data'] as Map<String, dynamic>;
    state = state.copyWith(
      otherName: data['name'] as String?,
      otherLanguage: data['language'] as String?,
      status: SessionStatus.active,
    );
    _markActiveAndStartMic();
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
      state = state.copyWith(partialText: data['text'] as String? ?? '');
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
      partialText: '',
    );
  }

  void _onAudioResponse(Map<String, dynamic> msg) {
    final data = msg['data'] as Map<String, dynamic>;
    final audio = data['audio'] as String?;
    final format = data['format'] as String? ?? 'mp3';
    if (audio != null && audio.isNotEmpty) {
      _audio.playAudioBase64(audio, format: format);
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
      state = state.copyWith(otherPipelineStage: stage);
      if (stage == PipelineStage.idle) {
        state = state.copyWith(partialText: '');
      }
    }
  }

  void _onChatMessage(Map<String, dynamic> msg) {
    final data = msg['data'] as Map<String, dynamic>;
    final chatMsg = ChatMessage.fromJson(data, state.participantId ?? '');
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
    debugPrint('[Pipeline error] ${data['message']}');
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
