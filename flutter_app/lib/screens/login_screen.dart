import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/language_selector.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

enum _Step { phone, otp, profile }

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _phoneCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();

  _Step _step = _Step.phone;
  String _language = 'en';
  String _verificationId = '';
  bool _loading = false;
  String? _error;

  // For auto-detection
  PhoneAuthCredential? _autoCredential;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  String get _fullPhone {
    final num = _phoneCtrl.text.trim();
    if (num.startsWith('+')) return num;
    return '+92${num.replaceFirst(RegExp(r'^0'), '')}'; // Pakistan default
  }

  Future<void> _sendOtp() async {
    final phone = _fullPhone;
    if (phone.length < 10) {
      _setError('Please enter a valid phone number');
      return;
    }
    setState(() { _loading = true; _error = null; });

    final error = await ref.read(authProvider.notifier).sendOtp(
      phone: phone,
      onCodeSent: (vid) {
        _verificationId = vid;
        if (mounted) setState(() { _loading = false; _step = _Step.otp; });
      },
      onAutoVerified: (credential) {
        _autoCredential = credential;
        if (mounted) setState(() { _step = _Step.profile; });
      },
    );

    if (error != null && mounted) {
      setState(() { _loading = false; _error = error; });
    }
  }

  Future<void> _verifyOtp() async {
    final otp = _otpCtrl.text.trim();
    if (otp.length != 6) {
      _setError('Enter the 6-digit OTP');
      return;
    }
    setState(() { _loading = true; _error = null; _step = _Step.profile; _loading = false; });
  }

  Future<void> _completeProfile() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _setError('Please enter your name');
      return;
    }
    setState(() { _loading = true; _error = null; });

    String? error;
    if (_autoCredential != null) {
      await ref.read(authProvider.notifier).signInWithCredential(
        _autoCredential!,
        name: name,
        language: _language,
        phone: _fullPhone,
      );
    } else {
      error = await ref.read(authProvider.notifier).verifyOtp(
        verificationId: _verificationId,
        otp: _otpCtrl.text.trim(),
        name: name,
        language: _language,
        phone: _fullPhone,
      );
    }

    if (mounted) {
      setState(() { _loading = false; });
      if (error != null) _setError(error);
    }
  }

  void _setError(String msg) => setState(() => _error = msg);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg950,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 48),

              // Logo
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.brand600,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.brand600.withOpacity(0.5),
                      blurRadius: 30,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: const Center(
                  child: Text('VT',
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                ),
              ).animate().fadeIn(duration: 600.ms).scaleXY(begin: 0.8, end: 1.0, duration: 600.ms),

              const SizedBox(height: 28),
              Text(
                _step == _Step.phone
                    ? 'Welcome to\nVoice Translate'
                    : _step == _Step.otp
                        ? 'Enter OTP'
                        : 'Your Profile',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 28, fontWeight: FontWeight.w700, height: 1.3),
              ).animate().fadeIn(delay: 200.ms),

              const SizedBox(height: 8),
              Text(
                _step == _Step.phone
                    ? 'Enter your phone number to get started'
                    : _step == _Step.otp
                        ? 'We sent a code to ${_fullPhone}'
                        : 'Tell us a bit about yourself',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.surface400, fontSize: 14),
              ).animate().fadeIn(delay: 300.ms),

              const SizedBox(height: 40),

              if (_step == _Step.phone) _buildPhoneStep(),
              if (_step == _Step.otp) _buildOtpStep(),
              if (_step == _Step.profile) _buildProfileStep(),

              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.red600.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.red600.withOpacity(0.4)),
                  ),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.red500, fontSize: 13),
                  ),
                ),
              ],

              const SizedBox(height: 32),
              const Text(
                'By continuing you agree to our Terms of Service',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.bg500, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhoneStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('PHONE NUMBER',
            style: TextStyle(
                color: AppColors.surface400,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8)),
        const SizedBox(height: 8),
        TextField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          style: const TextStyle(color: AppColors.white, fontSize: 15),
          decoration: const InputDecoration(
            hintText: '03XX XXXXXXX',
            prefixIcon: Icon(Icons.phone_rounded, color: AppColors.bg500, size: 20),
            prefixText: '+92  ',
            prefixStyle: TextStyle(color: AppColors.surface400, fontSize: 15),
          ),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _sendOtp(),
        ),
        const SizedBox(height: 24),
        _ActionButton(
          label: 'Send OTP',
          loading: _loading,
          onTap: _sendOtp,
        ),
      ],
    ).animate().fadeIn(delay: 400.ms);
  }

  Widget _buildOtpStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('6-DIGIT OTP',
            style: TextStyle(
                color: AppColors.surface400,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8)),
        const SizedBox(height: 8),
        TextField(
          controller: _otpCtrl,
          keyboardType: TextInputType.number,
          maxLength: 6,
          style: const TextStyle(
              color: AppColors.white, fontSize: 22, letterSpacing: 6),
          textAlign: TextAlign.center,
          decoration: const InputDecoration(
            hintText: '------',
            counterText: '',
            prefixIcon: Icon(Icons.lock_rounded, color: AppColors.bg500, size: 20),
          ),
          onSubmitted: (_) => _verifyOtp(),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _loading ? null : _sendOtp,
          child: const Text('Resend OTP',
              style: TextStyle(color: AppColors.brand400, fontSize: 13)),
        ),
        const SizedBox(height: 16),
        _ActionButton(
          label: 'Verify OTP',
          loading: _loading,
          onTap: _verifyOtp,
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => setState(() { _step = _Step.phone; _error = null; }),
          child: const Text('Change number',
              style: TextStyle(color: AppColors.surface400, fontSize: 13)),
        ),
      ],
    ).animate().fadeIn(delay: 200.ms);
  }

  Widget _buildProfileStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('YOUR NAME',
            style: TextStyle(
                color: AppColors.surface400,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8)),
        const SizedBox(height: 8),
        TextField(
          controller: _nameCtrl,
          style: const TextStyle(color: AppColors.white, fontSize: 15),
          decoration: const InputDecoration(
            hintText: 'Enter your name',
            prefixIcon: Icon(Icons.person_outline_rounded,
                color: AppColors.bg500, size: 20),
          ),
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 20),
        LanguageSelector(
          value: _language,
          onChanged: (v) => setState(() => _language = v),
          label: 'Your Language',
        ),
        const SizedBox(height: 24),
        _ActionButton(
          label: 'Get Started',
          loading: _loading,
          onTap: _completeProfile,
        ),
      ],
    ).animate().fadeIn(delay: 200.ms);
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: loading ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.brand600,
          disabledBackgroundColor: AppColors.bg700,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Text(label,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
