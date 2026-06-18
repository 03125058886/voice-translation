import 'dart:async';
import 'dart:typed_data';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Top-level background handler (required by FCM)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.ensureLocalNotificationsReady();
  if (message.data['type'] == 'incoming_call') {
    await NotificationService.showIncomingCallFromData(message.data);
  }
}

class NotificationService {
  static final _fcm = FirebaseMessaging.instance;
  static final _localNotif = FlutterLocalNotificationsPlugin();
  static bool _localReady = false;

  static const _channelId = 'incoming_calls_ring';
  static const _channelName = 'Incoming Calls';
  static const _notifId = 0;

  // Callback set by home_screen when app is in foreground
  static void Function(Map<String, dynamic>)? onIncomingCallData;

  // Holds call data from notification tap when app was terminated
  static Map<String, dynamic>? pendingCallData;

  static AndroidNotificationDetails get _androidCallDetails => AndroidNotificationDetails(
        _channelId,
        _channelName,
        importance: Importance.max,
        priority: Priority.max,
        playSound: true,
        sound: const UriAndroidNotificationSound('content://settings/system/ringtone'),
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 500, 500, 500, 500, 500]),
        fullScreenIntent: true,
        category: AndroidNotificationCategory.call,
        ongoing: true,
        autoCancel: false,
        timeoutAfter: 30000,
        visibility: NotificationVisibility.public,
      );

  static Future<void> ensureLocalNotificationsReady() async {
    if (_localReady) return;

    final androidChannel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      importance: Importance.max,
      playSound: true,
      sound: const UriAndroidNotificationSound('content://settings/system/ringtone'),
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 500, 500, 500, 500, 500]),
    );

    final androidPlugin = _localNotif
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(androidChannel);
    await androidPlugin?.requestNotificationsPermission();

    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _localNotif.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );
    _localReady = true;
  }

  static void _onNotificationTapped(NotificationResponse details) {
    final payload = details.payload;
    if (payload == null || payload.isEmpty) return;
    final parts = payload.split('|');
    if (parts.length < 4) return;
    final data = {
      'session_id': parts[0],
      'caller_name': parts[1],
      'caller_language': parts[2],
      'caller_id': parts[3],
      'type': 'incoming_call',
    };
    if (onIncomingCallData != null) {
      onIncomingCallData!(data);
    } else {
      pendingCallData = data;
    }
  }

  static Future<void> initialize() async {
    await _fcm.requestPermission(alert: true, badge: true, sound: true);
    await ensureLocalNotificationsReady();

    // Foreground FCM — always ring + show in-app overlay
    FirebaseMessaging.onMessage.listen((message) {
      final data = message.data;
      if (data['type'] == 'incoming_call') {
        showIncomingCallFromData(data);
        onIncomingCallData?.call(data);
      }
    });

    // Background → foreground tap handler
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final data = message.data;
      if (data['type'] == 'incoming_call') {
        if (onIncomingCallData != null) {
          onIncomingCallData!(data);
        } else {
          pendingCallData = data;
        }
      }
    });

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    final initial = await _fcm.getInitialMessage();
    if (initial != null && initial.data['type'] == 'incoming_call') {
      pendingCallData = initial.data;
    }
  }

  static Future<String?> getToken() async {
    return await _fcm.getToken();
  }

  /// Show ringing notification — works for FCM, lobby WebSocket, and foreground.
  static Future<void> showIncomingCallFromData(Map<String, dynamic> data) async {
    await ensureLocalNotificationsReady();
    final callerName = data['caller_name'] ?? 'Someone';

    await _localNotif.show(
      _notifId,
      '$callerName is calling...',
      'Incoming Voice Translation Call — tap to answer',
      NotificationDetails(android: _androidCallDetails),
      payload:
          '${data['session_id']}|${data['caller_name']}|${data['caller_language']}|${data['caller_id']}',
    );
  }

  static Future<void> showCallNotification(RemoteMessage message) async {
    await showIncomingCallFromData(message.data);
  }

  static Future<void> cancelCallNotification() async {
    await _localNotif.cancel(_notifId);
  }
}
