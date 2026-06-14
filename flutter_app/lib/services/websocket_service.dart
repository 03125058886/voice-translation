import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/app_config.dart';

typedef JsonHandler = void Function(Map<String, dynamic> message);

class WebSocketService {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  final _handlers = <String, List<JsonHandler>>{};
  bool _disposed = false;

  Timer? _pingTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;

  late String _sessionId;
  late String _participantId;

  VoidCallback? onConnected;
  VoidCallback? onDisconnected;

  Future<void> connect(String sessionId, String participantId) async {
    _sessionId = sessionId;
    _participantId = participantId;
    _disposed = false;
    await _doConnect();
  }

  Future<void> _doConnect() async {
    final url = AppConfig.sessionWsUrl(_sessionId, _participantId);
    _channel = WebSocketChannel.connect(Uri.parse(url));

    await _channel!.ready.catchError((_) {});

    onConnected?.call();
    _reconnectAttempts = 0;
    _startPing();

    _subscription = _channel!.stream.listen(
      _onMessage,
      onError: _onError,
      onDone: _onDone,
    );
  }

  void _onMessage(dynamic data) {
    if (data is String) {
      try {
        final json = jsonDecode(data) as Map<String, dynamic>;
        final type = json['type'] as String?;
        if (type != null) {
          _handlers[type]?.forEach((h) => h(json));
          _handlers['*']?.forEach((h) => h(json));
        }
      } catch (_) {}
    }
  }

  void _onError(Object err) {
    onDisconnected?.call();
    _scheduleReconnect();
  }

  void _onDone() {
    onDisconnected?.call();
    if (!_disposed) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed || _reconnectAttempts >= 5) return;
    final delay = Duration(seconds: (1 << _reconnectAttempts).clamp(1, 16));
    _reconnectAttempts++;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      if (!_disposed) _doConnect();
    });
  }

  void on(String type, JsonHandler handler) {
    _handlers.putIfAbsent(type, () => []).add(handler);
  }

  void off(String type, JsonHandler handler) {
    _handlers[type]?.remove(handler);
  }

  void send(String type, [Map<String, dynamic>? data]) {
    final msg = jsonEncode({'type': type, 'data': data ?? {}});
    _channel?.sink.add(msg);
  }

  void sendBinary(Uint8List bytes) {
    _channel?.sink.add(bytes);
  }

  void sendAudio(Uint8List pcmBytes) => sendBinary(pcmBytes);
  void mute() => send('mute');
  void unmute() => send('unmute');
  void flush() => send('flush');

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 20), (_) => send('ping'));
  }

  void dispose() {
    _disposed = true;
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    _handlers.clear();
  }

  bool get isConnected => _channel != null;
}

typedef VoidCallback = void Function();
