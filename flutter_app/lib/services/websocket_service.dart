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
    await _channel!.ready.timeout(
      const Duration(seconds: 15),
      onTimeout: () => throw Exception('WebSocket connection timed out'),
    );

    onConnected?.call();
    _startPing();

    _subscription = _channel!.stream.listen(
      _onMessage,
      onError: (_) => onDisconnected?.call(),
      onDone: () => onDisconnected?.call(),
    );
  }

  void _onMessage(dynamic data) {
    if (data is String) {
      try {
        final json = jsonDecode(data) as Map<String, dynamic>;
        final type = json['type'] as String?;
        if (type != null) {
          _handlers[type]?.forEach((h) => h(json));
        }
      } catch (_) {}
    }
  }

  void on(String type, JsonHandler handler) {
    _handlers.putIfAbsent(type, () => []).add(handler);
  }

  void send(String type, [Map<String, dynamic>? data]) {
    final msg = jsonEncode({'type': type, 'data': data ?? {}});
    _channel?.sink.add(msg);
  }

  void sendBinary(Uint8List bytes) {
    _channel?.sink.add(bytes);
  }

  void sendAudio(Uint8List pcmBytes) => sendBinary(pcmBytes);
  void setLanguage(String language) => send('set_language', {'language': language});
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
    _subscription?.cancel();
    _channel?.sink.close();
    _handlers.clear();
    _channel = null;
  }

  bool get isConnected => _channel != null;
}

typedef VoidCallback = void Function();
