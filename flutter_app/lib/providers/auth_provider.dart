import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_profile.dart';
import '../services/notification_service.dart';
import '../services/api_service.dart';

final authProvider =
    StateNotifierProvider<AuthNotifier, UserProfile?>((ref) => AuthNotifier());

class AuthNotifier extends StateNotifier<UserProfile?> {
  AuthNotifier() : super(null) {
    _loadProfile();
  }

  static const _kName = 'profile_name';
  static const _kLang = 'profile_lang';
  static const _kPhone = 'profile_phone';

  final _auth = FirebaseAuth.instance;

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_kName);
    final phone = prefs.getString(_kPhone);
    if (name == null || name.isEmpty || phone == null || phone.isEmpty) return;
    state = UserProfile(
      name: name,
      language: prefs.getString(_kLang) ?? 'en',
      phone: phone,
    );
  }

  Future<void> _saveProfile(UserProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kName, profile.name);
    await prefs.setString(_kLang, profile.language);
    await prefs.setString(_kPhone, profile.phone);
    state = profile;
    // Save FCM token to backend
    _registerFcmToken(profile);
  }

  Future<void> _registerFcmToken(UserProfile profile) async {
    try {
      final token = await NotificationService.getToken();
      if (token != null) {
        await ApiService.registerUser(
          phone: profile.phone,
          name: profile.name,
          language: profile.language,
          fcmToken: token,
        );
      }
    } catch (_) {}
  }

  /// Step 1: Send OTP to phone number
  /// Returns null on success, error string on failure
  Future<String?> sendOtp({
    required String phone,
    required void Function(String verificationId) onCodeSent,
    required void Function(PhoneAuthCredential) onAutoVerified,
    required void Function(String error) onFailed,
  }) async {
    final completer = Completer<String?>();

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phone,
        verificationCompleted: (credential) {
          onAutoVerified(credential);
          if (!completer.isCompleted) completer.complete(null);
        },
        verificationFailed: (e) {
          final msg = switch (e.code) {
            'invalid-phone-number' => 'Invalid phone number format.',
            'too-many-requests'    => 'Too many attempts. Try again later.',
            'app-not-authorized'   => 'App not authorized for Firebase (check SHA-1).',
            'quota-exceeded'       => 'SMS quota exceeded. Try again later.',
            _                      => '${e.message ?? e.code}',
          };
          onFailed(msg);
          if (!completer.isCompleted) completer.complete(msg);
        },
        codeSent: (verificationId, _) {
          onCodeSent(verificationId);
          if (!completer.isCompleted) completer.complete(null);
        },
        codeAutoRetrievalTimeout: (_) {
          if (!completer.isCompleted) completer.complete(null);
        },
        timeout: const Duration(seconds: 30),
      );
    } catch (e) {
      if (!completer.isCompleted) {
        completer.complete('Error: ${e.toString().split('\n').first}');
      }
    }

    // Timeout fallback — if Firebase never responds in 35s
    return Future.any([
      completer.future,
      Future.delayed(
        const Duration(seconds: 35),
        () => 'OTP request timed out. Check internet & Firebase setup.',
      ),
    ]);
  }

  /// Step 2: Verify OTP and complete login
  Future<String?> verifyOtp({
    required String verificationId,
    required String otp,
    required String name,
    required String language,
    required String phone,
  }) async {
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: otp,
      );
      await _auth.signInWithCredential(credential);
      await _saveProfile(UserProfile(name: name, language: language, phone: phone));
      return null;
    } on FirebaseAuthException catch (e) {
      return switch (e.code) {
        'invalid-verification-code' => 'Wrong OTP. Please check and try again.',
        'session-expired' => 'OTP expired. Please request a new one.',
        _ => e.message ?? 'Verification failed.',
      };
    } catch (e) {
      return 'Verification failed: ${e.toString().split('\n').first}';
    }
  }

  /// Auto-verify credential (when Firebase detects OTP automatically)
  Future<void> signInWithCredential(PhoneAuthCredential credential, {
    required String name,
    required String language,
    required String phone,
  }) async {
    await _auth.signInWithCredential(credential);
    await _saveProfile(UserProfile(name: name, language: language, phone: phone));
  }

  Future<void> updateLanguage(String language) async {
    if (state == null) return;
    await _saveProfile(state!.copyWith(language: language));
  }

  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kName);
    await prefs.remove(_kLang);
    await prefs.remove(_kPhone);
    try { await _auth.signOut(); } catch (_) {}
    state = null;
  }
}
