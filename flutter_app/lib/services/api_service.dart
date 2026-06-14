import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../models/session.dart';

class CreateSessionResult {
  final String sessionId;
  final String participantId;

  const CreateSessionResult({required this.sessionId, required this.participantId});
}

class ApiService {
  static final _client = http.Client();
  static final _base = AppConfig.apiBaseUrl;

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  static Future<void> registerUser({
    required String phone,
    required String name,
    required String language,
    String? fcmToken,
    String? fcm_token,
  }) async {
    fcmToken ??= fcm_token;
    try {
      await _client.post(
        Uri.parse('$_base/api/users/register'),
        headers: _headers,
        body: jsonEncode({
          'phone': phone,
          'name': name,
          'language': language,
          if (fcmToken != null) 'fcm_token': fcmToken,
        }),
      );
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> findUserByPhone(String phone) async {
    try {
      final encoded = Uri.encodeComponent(phone);
      final res = await _client.get(
        Uri.parse('$_base/api/users/by-phone/$encoded'),
        headers: _headers,
      );
      if (res.statusCode == 404) return null;
      _checkStatus(res);
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<void> markOnline(String phone) async {
    try {
      final encoded = Uri.encodeComponent(phone);
      await _client.post(Uri.parse('$_base/api/users/$encoded/online'), headers: _headers);
    } catch (_) {}
  }

  static Future<void> markOffline(String phone) async {
    try {
      final encoded = Uri.encodeComponent(phone);
      await _client.post(Uri.parse('$_base/api/users/$encoded/offline'), headers: _headers);
    } catch (_) {}
  }

  static Future<CreateSessionResult> createSession({
    required String participantName,
    required String participantLanguage,
    String domain = 'general',
    String? callerPhone,
    String? targetPhone,
  }) async {
    final res = await _client.post(
      Uri.parse('$_base/api/sessions'),
      headers: _headers,
      body: jsonEncode({
        'participant_name': participantName,
        'participant_language': participantLanguage,
        'domain': domain,
        if (callerPhone != null) 'caller_phone': callerPhone,
        if (targetPhone != null) 'target_phone': targetPhone,
      }),
    );
    _checkStatus(res);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return CreateSessionResult(
      sessionId: data['session_id'] as String,
      participantId: data['participant_id'] as String,
    );
  }

  static Future<CreateSessionResult> joinSession({
    required String sessionId,
    required String participantName,
    required String participantLanguage,
    String? phone,
  }) async {
    final res = await _client.post(
      Uri.parse('$_base/api/sessions/$sessionId/join'),
      headers: _headers,
      body: jsonEncode({
        'participant_name': participantName,
        'participant_language': participantLanguage,
        if (phone != null) 'phone': phone,
      }),
    );
    _checkStatus(res);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return CreateSessionResult(
      sessionId: data['session_id'] as String,
      participantId: data['participant_id'] as String,
    );
  }

  static Future<Map<String, dynamic>> getSession(String sessionId) async {
    final res = await _client.get(
      Uri.parse('$_base/api/sessions/$sessionId'),
      headers: _headers,
    );
    _checkStatus(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<List<Map<String, dynamic>>> getChatMessages(String sessionId) async {
    final res = await _client.get(
      Uri.parse('$_base/api/sessions/$sessionId/messages'),
      headers: _headers,
    );
    _checkStatus(res);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['messages'] as List);
  }

  static Future<Map<String, dynamic>> sendTextMessage({
    required String sessionId,
    required String participantId,
    required String participantName,
    required String content,
  }) async {
    final res = await _client.post(
      Uri.parse('$_base/api/sessions/$sessionId/messages'),
      headers: _headers,
      body: jsonEncode({
        'participant_id': participantId,
        'participant_name': participantName,
        'content': content,
      }),
    );
    _checkStatus(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> uploadFile({
    required String sessionId,
    required String participantId,
    required String participantName,
    required File file,
    required String messageType,
    required String mimeType,
    int? durationMs,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_base/api/sessions/$sessionId/upload'),
    );
    request.fields['participant_id'] = participantId;
    request.fields['participant_name'] = participantName;
    request.fields['message_type'] = messageType;
    if (durationMs != null) request.fields['duration_ms'] = durationMs.toString();
    request.files.add(await http.MultipartFile.fromPath(
      'file',
      file.path,
      contentType: _parseMediaType(mimeType),
    ));
    final streamed = await _client.send(request);
    final res = await http.Response.fromStream(streamed);
    _checkStatus(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static http.MediaType _parseMediaType(String mime) {
    final parts = mime.split('/');
    return http.MediaType(parts[0], parts.length > 1 ? parts[1] : '*');
  }

  static Future<List<Map<String, dynamic>>> listSessions() async {
    final res = await _client.get(
      Uri.parse('$_base/api/sessions'),
      headers: _headers,
    );
    _checkStatus(res);
    return List<Map<String, dynamic>>.from(jsonDecode(res.body) as List);
  }

  static Future<String> getTranslatedVoice({
    required String sessionId,
    required String msgId,
    required String language,
  }) async {
    final uri = Uri.parse(
        '$_base/api/sessions/$sessionId/messages/$msgId/audio?language=$language');
    final res = await _client.get(uri, headers: _headers);
    _checkStatus(res);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return '$_base${data['audio_url'] as String}';
  }

  static Future<Map<String, dynamic>> sendDirectMessage({
    required String senderPhone,
    required String receiverPhone,
    required String content,
  }) async {
    final res = await _client.post(
      Uri.parse('$_base/api/dm/send'),
      headers: _headers,
      body: jsonEncode({
        'sender_phone': senderPhone,
        'receiver_phone': receiverPhone,
        'content': content,
      }),
    );
    _checkStatus(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<List<Map<String, dynamic>>> getDirectMessages({
    required String me,
    required String other,
  }) async {
    final uri = Uri.parse('$_base/api/dm/conversation?me=${Uri.encodeComponent(me)}&other=${Uri.encodeComponent(other)}');
    final res = await _client.get(uri, headers: _headers);
    _checkStatus(res);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['messages'] as List);
  }

  static Future<List<Map<String, dynamic>>> getConversations(String phone) async {
    final uri = Uri.parse('$_base/api/dm/conversations/${Uri.encodeComponent(phone)}');
    final res = await _client.get(uri, headers: _headers);
    _checkStatus(res);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['conversations'] as List);
  }

  static Future<List<Map<String, dynamic>>> listLanguages() async {
    final res = await _client.get(
      Uri.parse('$_base/api/languages'),
      headers: _headers,
    );
    _checkStatus(res);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['languages'] as List);
  }

  static void _checkStatus(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final body = jsonDecode(res.body) as Map<String, dynamic>?;
      final msg = body?['detail'] as String? ?? 'Request failed (${res.statusCode})';
      throw ApiException(msg, res.statusCode);
    }
  }
}

class ApiException implements Exception {
  final String message;
  final int statusCode;
  const ApiException(this.message, this.statusCode);

  @override
  String toString() => 'ApiException($statusCode): $message';
}
