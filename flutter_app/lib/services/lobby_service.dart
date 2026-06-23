import 'dart:async';
import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/app_config.dart';

typedef OnlineListCallback = void Function(List<OnlineUser> users, String myId);
typedef IncomingCallCallback = void Function(IncomingCall call);
typedef CallInitiatedCallback = void Function(CallInitiated call);
typedef CallRejectedCallback = void Function(String byName);
typedef UserStatusCallback = void Function(OnlineUser user, bool online);

class OnlineUser {
  final String userId;
  final String name;
  final String language;

  const OnlineUser({
    required this.userId,
    required this.name,
    required this.language,
  });

  factory OnlineUser.fromJson(Map<String, dynamic> json) => OnlineUser(
        userId: json['user_id'] as String,
        name: json['name'] as String,
        language: json['language'] as String? ?? 'en',
      );
}

class IncomingCall {
  final String callerId;
  final String callerName;
  final String callerLanguage;
  final String sessionId;

  const IncomingCall({
    required this.callerId,
    required this.callerName,
    required this.callerLanguage,
    required this.sessionId,
  });
}

class CallInitiated {
  final String sessionId;
  final String participantId;
  final String targetUserId;
  final bool targetFound;

  const CallInitiated({
    required this.sessionId,
    required this.participantId,
    required this.targetUserId,
    required this.targetFound,
  });
}

typedef VoidCallback = void Function();

class LobbyService {
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  bool _disposed = true;
  final _uuid = const Uuid();

  String? _userId;
  String? _name;
  String? _language;
  String? _phone;

  bool _connected = false;
  bool get isConnected => _connected;
  String? get userId => _userId;

  OnlineListCallback? onOnlineList;
  IncomingCallCallback? onIncomingCall;
  CallInitiatedCallback? onCallInitiated;
  CallRejectedCallback? onCallRejected;
  UserStatusCallback? onUserStatusChange;
  VoidCallback? onConnected;
  VoidCallback? onDisconnected;

  Future<void> connect({required String name, required String language, String? phone}) async {
    _name = name;
    _language = language;
    _phone = phone;
    _userId ??= _uuid.v4();
    _disposed = false;
    _reconnectAttempts = 0;
    await _doConnect();
  }

  Future<void> _doConnect() async {
    if (_disposed) return;
    final wsBase = AppConfig.wsBaseUrl;
    final phoneParam = _phone != null && _phone!.isNotEmpty ? '&phone=${Uri.encodeComponent(_phone!)}' : '';
    final uri = Uri.parse(
      '$wsBase/ws/lobby?name=${Uri.encodeComponent(_name ?? '')}&language=$_language&user_id=$_userId$phoneParam',
    );

    try {
      _channel = WebSocketChannel.connect(uri);
      await _channel!.ready;
      _connected = true;
      _reconnectAttempts = 0;
      onConnected?.call();

      _sub = _channel!.stream.listen(
        _onMessage,
        onDone: _handleDisconnect,
        onError: (_) => _handleDisconnect(),
      );

      _pingTimer?.cancel();
      _pingTimer = Timer.periodic(const Duration(seconds: 20), (_) {
        _send({'type': 'ping'});
      });
    } catch (_) {
      _connected = false;
      onDisconnected?.call();
      _scheduleReconnect();
    }
  }

  void _handleDisconnect() {
    final wasConnected = _connected;
    _connected = false;
    if (wasConnected) onDisconnected?.call();
    if (!_disposed) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed || _reconnectAttempts >= 8) return;
    final delay = Duration(seconds: (1 << _reconnectAttempts).clamp(1, 20));
    _reconnectAttempts++;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      if (!_disposed) _doConnect();
    });
  }

  void _onMessage(dynamic raw) {
    try {
      final msg = jsonDecode(raw as String) as Map<String, dynamic>;
      final type = msg['type'] as String?;
      final data = msg['data'] as Map<String, dynamic>? ?? {};

      switch (type) {
        case 'online_list':
          _userId = data['your_id'] as String?;
          final users = (data['users'] as List? ?? [])
              .map((e) => OnlineUser.fromJson(e as Map<String, dynamic>))
              .where((u) => u.userId != _userId)
              .toList();
          onOnlineList?.call(users, _userId ?? '');

        case 'user_online':
          final user = OnlineUser.fromJson(data);
          if (user.userId != _userId) {
            onUserStatusChange?.call(user, true);
          }

        case 'user_offline':
          final uid = data['user_id'] as String?;
          if (uid != null && uid != _userId) {
            onUserStatusChange?.call(
              OnlineUser(userId: uid, name: '', language: ''),
              false,
            );
          }

        case 'incoming_call':
          onIncomingCall?.call(IncomingCall(
            callerId: data['caller_id'] as String,
            callerName: data['caller_name'] as String,
            callerLanguage: data['caller_language'] as String? ?? 'en',
            sessionId: data['session_id'] as String,
          ));

        case 'call_initiated':
          onCallInitiated?.call(CallInitiated(
            sessionId: data['session_id'] as String,
            participantId: data['participant_id'] as String,
            targetUserId: data['target_user_id'] as String,
            targetFound: data['target_found'] as bool? ?? false,
          ));

        case 'call_rejected':
          onCallRejected?.call(data['by_name'] as String? ?? 'Unknown');
      }
    } catch (_) {}
  }

  void callUser(String targetUserId) {
    _send({
      'type': 'call_user',
      'data': {'target_user_id': targetUserId},
    });
  }

  void callByPhone(String targetPhone) {
    _send({
      'type': 'call_by_phone',
      'data': {'target_phone': targetPhone},
    });
  }

  void rejectCall(String callerId) {
    _send({
      'type': 'call_rejected',
      'data': {'caller_id': callerId},
    });
  }

  void _send(Map<String, dynamic> msg) {
    if (_connected && _channel != null) {
      try {
        _channel!.sink.add(jsonEncode(msg));
      } catch (_) {}
    }
  }

  Future<void> disconnect() async {
    _disposed = true;
    _connected = false;
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    await _sub?.cancel();
    await _channel?.sink.close();
  }
}
