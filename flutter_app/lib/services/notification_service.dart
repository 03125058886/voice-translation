import 'dart:async';
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

  static const _channelId = 'incoming_calls';
  static const _channelName = 'Incoming Calls';

  // Callback set by home_screen when app is in foreground
  static void Function(Map<String, dynamic>)? onIncomingCallData;

  static Future<void> initialize() async {
    // Request permission
    await _fcm.requestPermission(alert: true, badge: true, sound: true);

    // Android notification channel
    const androidChannel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );

    await _localNotif
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);

    // Init local notifications
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _localNotif.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        // User tapped notification — payload has call data
        if (details.payload != null) {
          // Will be handled by app routing
        }
      },
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
      if (data['type'] == 'incoming_call' && onIncomingCallData != null) {
        onIncomingCallData!(data);
      }
    });

    // Background message handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  static Future<String?> getToken() async {
    return await _fcm.getToken();
  }

  static Future<void> showCallNotification(RemoteMessage message) async {
    final data = message.data;
    final callerName = data['caller_name'] ?? 'Someone';

    await _localNotif.show(
      0,
      '📞 $callerName is calling',
      'Voice Translation Call — open app to answer',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          enableVibration: true,
          fullScreenIntent: true,
          category: AndroidNotificationCategory.call,
        ),
      ),
      payload: '${data['session_id']}|${data['caller_name']}|${data['caller_language']}|${data['caller_id']}',
    );
  }
}
