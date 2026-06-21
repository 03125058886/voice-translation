import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'api_service.dart';
import '../utils/phone_utils.dart';

// Top-level background handler (required by FCM) — must stay top-level.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await NotificationService.ensureLocalNotificationsReady();
  final data = message.data;
  final type = data['type'];
  if (type == 'incoming_call') {
    await NotificationService.showIncomingCallFromData(data);
  } else if (type == 'new_message') {
    await NotificationService.showMessageNotificationFromData(data);
  }
}

class NotificationService {
  static final _fcm = FirebaseMessaging.instance;
  static final _localNotif = FlutterLocalNotificationsPlugin();
  static bool _localReady = false;
  static String? _registeredPhone;

  static const _callChannelId = 'incoming_calls_ring';
  static const _callChannelName = 'Incoming Calls';
  static const _msgChannelId = 'new_messages';
  static const _msgChannelName = 'Messages';
  static const _callNotifId = 0;
  static const _msgNotifId = 1;

  static void Function(Map<String, dynamic>)? onIncomingCallData;
  static Map<String, dynamic>? pendingCallData;

  static AndroidNotificationDetails _callDetails(String callerName) => AndroidNotificationDetails(
        _callChannelId,
        _callChannelName,
        channelDescription: 'Incoming voice translation calls',
        importance: Importance.max,
        priority: Priority.max,
        playSound: true,
        sound: const UriAndroidNotificationSound('content://settings/system/ringtone'),
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 800, 400, 800, 400, 800]),
        fullScreenIntent: true,
        category: AndroidNotificationCategory.call,
        ongoing: true,
        autoCancel: false,
        timeoutAfter: 45000,
        visibility: NotificationVisibility.public,
        color: const Color(0xFF25D366),
        colorized: true,
        ticker: '$callerName is calling…',
        styleInformation: BigTextStyleInformation(
          'Voice Translation Call\nTap Accept or open the app to answer',
          contentTitle: '$callerName is calling…',
          summaryText: 'Incoming call',
        ),
        actions: <AndroidNotificationAction>[
          const AndroidNotificationAction(
            'decline_call',
            'Decline',
            cancelNotification: true,
            showsUserInterface: false,
          ),
          const AndroidNotificationAction(
            'accept_call',
            'Accept',
            cancelNotification: true,
            showsUserInterface: true,
          ),
        ],
      );

  static AndroidNotificationDetails _messageDetails() => const AndroidNotificationDetails(
        _msgChannelId,
        _msgChannelName,
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        visibility: NotificationVisibility.public,
      );

  static Future<void> ensureLocalNotificationsReady() async {
    if (_localReady) return;

    final androidPlugin = _localNotif
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(AndroidNotificationChannel(
      _callChannelId,
      _callChannelName,
      description: 'Incoming voice translation calls',
      importance: Importance.max,
      playSound: true,
      sound: const UriAndroidNotificationSound('content://settings/system/ringtone'),
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 800, 400, 800, 400, 800]),
    ));

    await androidPlugin?.createNotificationChannel(const AndroidNotificationChannel(
      _msgChannelId,
      _msgChannelName,
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    ));

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
    final actionId = details.actionId;
    final payload = details.payload;
    if (payload == null || payload.isEmpty) return;
    if (!payload.startsWith('call|')) return;

    if (actionId == 'decline_call') {
      cancelCallNotification();
      return;
    }

    final parts = payload.substring(5).split('|');
    if (parts.length < 4) return;
    final data = {
      'session_id': parts[0],
      'caller_name': parts[1],
      'caller_language': parts[2],
      'caller_id': parts[3],
      'type': 'incoming_call',
      'auto_accept': actionId == 'accept_call',
    };
    if (onIncomingCallData != null) {
      onIncomingCallData!(data);
    } else {
      pendingCallData = data;
    }
  }

  static const _batteryChannel = MethodChannel('com.example.voice_translation/audio');

  /// Ask Android to stop killing the app in the background, so incoming
  /// calls keep ringing the way they do on WhatsApp.
  static Future<void> requestBackgroundReliability() async {
    if (!Platform.isAndroid) return;
    try {
      await _batteryChannel.invokeMethod('requestIgnoreBatteryOptimizations');
    } catch (e) {
      debugPrint('[NotificationService] battery optimization request failed: $e');
    }
  }

  static Future<void> initialize() async {
    await _fcm.requestPermission(alert: true, badge: true, sound: true);
    await ensureLocalNotificationsReady();
    await requestBackgroundReliability();

    FirebaseMessaging.onMessage.listen((message) {
      final data = message.data;
      final type = data['type'];
      if (type == 'incoming_call') {
        showIncomingCallFromData(data);
        onIncomingCallData?.call(data);
      } else if (type == 'new_message') {
        showMessageNotificationFromData(data);
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final data = message.data;
      if (data['type'] == 'incoming_call') {
        data['auto_accept'] = 'false';
        if (onIncomingCallData != null) {
          onIncomingCallData!(data);
        } else {
          pendingCallData = data;
        }
      }
    });

    final initial = await _fcm.getInitialMessage();
    if (initial != null && initial.data['type'] == 'incoming_call') {
      pendingCallData = Map<String, dynamic>.from(initial.data);
      pendingCallData!['auto_accept'] = 'false';
    }

    _fcm.onTokenRefresh.listen((token) async {
      final phone = _registeredPhone;
      if (phone != null && phone.isNotEmpty) {
        await ApiService.updateFcmToken(phone: phone, token: token);
      }
    });
  }

  /// Register FCM token with backend — call on every app start after login.
  static Future<void> syncFcmToken(
    String phone, {
    String? name,
    String? language,
  }) async {
    final normalized = PhoneUtils.normalize(phone);
    if (normalized.isEmpty) return;
    _registeredPhone = normalized;
    try {
      final token = await _fcm.getToken();
      if (token == null) {
        debugPrint('[FCM] getToken returned null — check notification permission');
        return;
      }
      if (name != null && name.isNotEmpty) {
        await ApiService.registerUser(
          phone: normalized,
          name: name,
          language: language ?? 'en',
          fcmToken: token,
        );
      } else {
        await ApiService.updateFcmToken(phone: normalized, token: token);
      }
      debugPrint('[FCM] token synced for $normalized');
    } catch (e) {
      debugPrint('[FCM] token sync failed: $e');
    }
  }

  static Future<String?> getToken() async => _fcm.getToken();

  static Future<void> showIncomingCallFromData(Map<String, dynamic> data) async {
    await ensureLocalNotificationsReady();
    final callerName = data['caller_name'] ?? 'Someone';
    await _localNotif.show(
      _callNotifId,
      '$callerName is calling…',
      'Voice Translation Call — tap Accept to answer',
      NotificationDetails(android: _callDetails(callerName)),
      payload:
          'call|${data['session_id']}|${data['caller_name']}|${data['caller_language']}|${data['caller_id']}',
    );
  }

  static Future<void> showMessageNotificationFromData(Map<String, dynamic> data) async {
    await ensureLocalNotificationsReady();
    final sender = data['sender_name'] ?? 'Someone';
    final preview = data['preview'] ?? 'New message';
    await _localNotif.show(
      _msgNotifId,
      sender,
      preview,
      NotificationDetails(android: _messageDetails()),
    );
  }

  static Future<void> showCallNotification(RemoteMessage message) async {
    await showIncomingCallFromData(message.data);
  }

  static Future<void> cancelCallNotification() async {
    await _localNotif.cancel(_callNotifId);
  }
}
