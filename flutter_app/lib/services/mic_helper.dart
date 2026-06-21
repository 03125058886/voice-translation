import 'dart:io';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Shared mic permission + Android audio-mode reset for all recording paths.
class MicHelper {
  static const _channel = MethodChannel('com.example.voice_translation/audio');

  static Future<bool> ensurePermission() async {
    final status = await Permission.microphone.request();
    if (status.isGranted) return true;
    if (status.isPermanentlyDenied) {
      await openAppSettings();
    }
    return false;
  }

  static Future<void> prepareForRecording() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('resetAudioMode');
    } catch (_) {}
  }
}
