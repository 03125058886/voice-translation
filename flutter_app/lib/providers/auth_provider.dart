import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_profile.dart';

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
  }

  /// Step 1: Send OTP to phone number
  /// Returns null on success, error string on failure
  Future<String?> sendOtp({
    required String phone,
    required void Function(String verificationId) onCodeSent,
    required void Function(PhoneAuthCredential) onAutoVerified,
  }) async {
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phone,
        verificationCompleted: onAutoVerified,
        verificationFailed: (e) {},
        codeSent: (verificationId, _) => onCodeSent(verificationId),
        codeAutoRetrievalTimeout: (_) {},
        timeout: const Duration(seconds: 60),
      );
      return null;
    } catch (e) {
      return 'Failed to send OTP: ${e.toString().split('\n').first}';
    }
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
