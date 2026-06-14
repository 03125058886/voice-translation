import 'package:flutter/material.dart';

enum ParticipantStatus { waiting, connected, speaking, disconnected }

enum SessionStatus { waiting, active, ended, error }

enum PipelineStage { idle, recording, transcribing, translating, synthesizing, playing }

class Participant {
  final String id;
  final String name;
  final String language;
  final ParticipantStatus status;

  const Participant({
    required this.id,
    required this.name,
    required this.language,
    this.status = ParticipantStatus.connected,
  });

  factory Participant.fromJson(Map<String, dynamic> json) => Participant(
        id: json['id'] as String,
        name: json['name'] as String,
        language: json['language'] as String,
        status: ParticipantStatus.values.firstWhere(
          (s) => s.name == (json['status'] as String? ?? 'connected'),
          orElse: () => ParticipantStatus.connected,
        ),
      );

  Participant copyWith({ParticipantStatus? status}) =>
      Participant(id: id, name: name, language: language, status: status ?? this.status);
}

class TranscriptEntry {
  final String id;
  final String speakerId;
  final String speakerName;
  final String originalText;
  final String translatedText;
  final String sourceLang;
  final String targetLang;
  final DateTime timestamp;
  final bool isLocal;

  const TranscriptEntry({
    required this.id,
    required this.speakerId,
    required this.speakerName,
    required this.originalText,
    required this.translatedText,
    required this.sourceLang,
    required this.targetLang,
    required this.timestamp,
    required this.isLocal,
  });
}

class CallState {
  final String? sessionId;
  final String? participantId;
  final String myName;
  final String myLanguage;
  final String? otherName;
  final String? otherLanguage;
  final SessionStatus status;
  final PipelineStage pipelineStage;
  final PipelineStage otherPipelineStage;
  final bool isConnected;
  final bool isMuted;
  final bool isCapturing;
  final double volume;
  final List<TranscriptEntry> transcript;
  final List<Participant> participants;
  final String partialText;
  final List<ChatMessage> chatMessages;
  final bool remoteEnded;

  const CallState({
    this.sessionId,
    this.participantId,
    this.myName = '',
    this.myLanguage = 'en',
    this.otherName,
    this.otherLanguage,
    this.status = SessionStatus.waiting,
    this.pipelineStage = PipelineStage.idle,
    this.otherPipelineStage = PipelineStage.idle,
    this.isConnected = false,
    this.isMuted = false,
    this.isCapturing = false,
    this.volume = 0.0,
    this.transcript = const [],
    this.participants = const [],
    this.partialText = '',
    this.chatMessages = const [],
    this.remoteEnded = false,
  });

  // clearOtherParticipant: explicitly set otherName/otherLanguage to null
  CallState copyWith({
    String? sessionId,
    String? participantId,
    String? myName,
    String? myLanguage,
    String? otherName,
    String? otherLanguage,
    bool clearOtherParticipant = false,
    SessionStatus? status,
    PipelineStage? pipelineStage,
    PipelineStage? otherPipelineStage,
    bool? isConnected,
    bool? isMuted,
    bool? isCapturing,
    double? volume,
    List<TranscriptEntry>? transcript,
    List<Participant>? participants,
    String? partialText,
    List<ChatMessage>? chatMessages,
    bool? remoteEnded,
  }) =>
      CallState(
        sessionId: sessionId ?? this.sessionId,
        participantId: participantId ?? this.participantId,
        myName: myName ?? this.myName,
        myLanguage: myLanguage ?? this.myLanguage,
        otherName: clearOtherParticipant ? null : (otherName ?? this.otherName),
        otherLanguage: clearOtherParticipant ? null : (otherLanguage ?? this.otherLanguage),
        status: status ?? this.status,
        pipelineStage: pipelineStage ?? this.pipelineStage,
        otherPipelineStage: otherPipelineStage ?? this.otherPipelineStage,
        isConnected: isConnected ?? this.isConnected,
        isMuted: isMuted ?? this.isMuted,
        isCapturing: isCapturing ?? this.isCapturing,
        volume: volume ?? this.volume,
        transcript: transcript ?? this.transcript,
        participants: participants ?? this.participants,
        partialText: partialText ?? this.partialText,
        chatMessages: chatMessages ?? this.chatMessages,
        remoteEnded: remoteEnded ?? this.remoteEnded,
      );
}

// Language metadata
const Map<String, String> kLanguageNames = {
  'en': 'English', 'es': 'Spanish', 'fr': 'French', 'de': 'German',
  'it': 'Italian', 'pt': 'Portuguese', 'ru': 'Russian', 'zh': 'Chinese',
  'ja': 'Japanese', 'ko': 'Korean', 'ar': 'Arabic', 'hi': 'Hindi',
  'ur': 'Urdu', 'tr': 'Turkish', 'nl': 'Dutch', 'pl': 'Polish',
  'sv': 'Swedish', 'no': 'Norwegian', 'da': 'Danish', 'fi': 'Finnish',
};

const Map<String, String> kLanguageFlags = {
  'en': '🇺🇸', 'es': '🇪🇸', 'fr': '🇫🇷', 'de': '🇩🇪', 'it': '🇮🇹',
  'pt': '🇧🇷', 'ru': '🇷🇺', 'zh': '🇨🇳', 'ja': '🇯🇵', 'ko': '🇰🇷',
  'ar': '🇸🇦', 'hi': '🇮🇳', 'ur': '🇵🇰', 'tr': '🇹🇷', 'nl': '🇳🇱',
  'pl': '🇵🇱', 'sv': '🇸🇪', 'no': '🇳🇴', 'da': '🇩🇰', 'fi': '🇫🇮',
};

String languageName(String code) => kLanguageNames[code] ?? code.toUpperCase();
String languageFlag(String code) => kLanguageFlags[code] ?? '🌐';

enum ChatMessageType { text, voice, image, file }

class ChatMessage {
  final String id;
  final String sessionId;
  final String participantId;
  final String participantName;
  final ChatMessageType type;
  final String? content;
  final String? fileUrl;
  final String? fileName;
  final String? mimeType;
  final int? durationMs;
  final DateTime createdAt;
  final bool isLocal;

  const ChatMessage({
    required this.id,
    required this.sessionId,
    required this.participantId,
    required this.participantName,
    required this.type,
    this.content,
    this.fileUrl,
    this.fileName,
    this.mimeType,
    this.durationMs,
    required this.createdAt,
    required this.isLocal,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json, String myParticipantId) {
    final typeStr = json['message_type'] as String? ?? 'text';
    final type = ChatMessageType.values.firstWhere(
      (t) => t.name == typeStr,
      orElse: () => ChatMessageType.text,
    );
    return ChatMessage(
      id: json['id'] as String,
      sessionId: json['session_id'] as String? ?? '',
      participantId: json['participant_id'] as String,
      participantName: json['participant_name'] as String,
      type: type,
      content: json['content'] as String?,
      fileUrl: json['file_url'] as String?,
      fileName: json['file_name'] as String?,
      mimeType: json['mime_type'] as String?,
      durationMs: json['duration_ms'] as int?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      isLocal: json['participant_id'] == myParticipantId,
    );
  }
}
