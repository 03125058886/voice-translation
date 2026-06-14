import 'dart:async';
import 'dart:typed_data';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Top-level background handler (required by FCM)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await NotificationService.showCallNotification(message);
}

class NotificationService {
  static final _fcm = FirebaseMessaging.instance;
  static final _localNotif = FlutterLocalNotificationsPlugin();

  // New channel ID — forces Android to create a fresh channel with ringtone
  static const _channelId = 'incoming_calls_ring';
  static const _channelName = 'Incoming Calls';

  // Callback set by home_screen when app is in foreground
  static void Function(Map<String, dynamic>)? onIncomingCallData;

  // Holds call data from notification tap when app was terminated
  static Map<String, dynamic>? pendingCallData;

  static Future<void> initialize() async {
    await _fcm.requestPermission(alert: true, badge: true, sound: true);

    // Channel using system ringtone URI
    final androidChannel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      importance: Importance.max,
      playSound: true,
      sound: const UriAndroidNotificationSound('content://settings/system/ringtone'),
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 500, 500, 500, 500, 500]),
    );

    await _localNotif
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);

    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _localNotif.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {},
    );

    // Foreground FCM handler
    FirebaseMessaging.onMessage.listen((message) {
      final data = message.data;
      if (data['type'] == 'incoming_call') {
        if (onIncomingCallData != null) {
          onIncomingCallData!(data);
        } else {
          showCallNotification(message);
        }
      }
    });

    // Background → foreground tap handler
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final data = message.data;
      if (data['type'] == 'incoming_call') {
        if (onIncomingCallData != null) {
          onIncomingCallData!(data);
        } else {
          // Home screen not ready yet — store for later
          pendingCallData = data;
        }
      }
    });

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Handle notification tap when app was TERMINATED
    final initial = await _fcm.getInitialMessage();
    if (initial != null && initial.data['type'] == 'incoming_call') {
      pendingCallData = initial.data;
    }
  }

  static Future<String?> getToken() async {
    return await _fcm.getToken();
  }

  static Future<void> showCallNotification(RemoteMessage message) async {
    final data = message.data;
    final callerName = data['caller_name'] ?? 'Someone';

    await _localNotif.show(
      0,
      '$callerName is calling...',
      'Incoming Voice Translation Call — tap to answer',
      NotificationDetails(
        android: AndroidNotificationDetails(
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
        ),
      ),
      payload: '${data['session_id']}|${data['caller_name']}|${data['caller_language']}|${data['caller_id']}',
    );
  }

  static Future<void> cancelCallNotification() async {
    await _localNotif.cancel(0);
  }
}
