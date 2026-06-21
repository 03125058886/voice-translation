import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/session.dart';
import '../providers/call_provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'call_screen.dart';

class JoinScreen extends ConsumerStatefulWidget {
  final String name;
  final String language;

  const JoinScreen({super.key, required this.name, required this.language});

  @override
  ConsumerState<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends ConsumerState<JoinScreen> {
  final _codeCtrl = TextEditingController();
  bool _loading = false;
  bool _joiningSessionId = false;

  List<Map<String, dynamic>> _sessions = [];
  bool _sessionsLoading = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _fetchSessions();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _fetchSessions());
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchSessions() async {
    if (!mounted) return;
    setState(() => _sessionsLoading = true);
    try {
      final all = await ApiService.listSessions();
      if (!mounted) return;
      setState(() {
        _sessions = all.where((s) {
          final status = s['status'] as String? ?? '';
          final participants = s['participants'] as List? ?? [];
          return status == 'waiting' && participants.length == 1;
        }).toList();
      });
    } catch (_) {
      // silently ignore — network may not be ready
    } finally {
      if (mounted) setState(() => _sessionsLoading = false);
    }
  }

  String _extractSessionId(String input) {
    final uuidRegex = RegExp(
      r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
    );
    final match = uuidRegex.firstMatch(input);
    return match?.group(0) ?? input;
  }

  Future<void> _joinWithCode() async {
    final raw = _codeCtrl.text.trim();
    if (raw.isEmpty) {
      _toast('Enter a session ID or paste invite link');
      return;
    }
    final code = _extractSessionId(raw);
    await _doJoin(code);
  }

  Future<void> _doJoin(String sessionId) async {
    setState(() => _loading = true);
    try {
      await ref.read(callProvider.notifier).joinSession(
        sessionId: sessionId,
        name: widget.name,
        language: widget.language,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const CallScreen()),
      );
    } catch (e) {
      final msg = e is ApiException ? e.message : e.toString().replaceAll('Exception: ', '');
      _toast(msg);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: AppColors.bg700,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg950,
      appBar: AppBar(
        title: const Text('Join Session'),
        backgroundColor: AppColors.bg900,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Active sessions
              Row(
                children: [
                  const Text(
                    'WAITING TO CONNECT',
                    style: TextStyle(
                      color: AppColors.surface400,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const Spacer(),
                  if (_sessionsLoading)
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.surface400),
                    )
                  else
                    GestureDetector(
                      onTap: _fetchSessions,
                      child: const Icon(Icons.refresh_rounded, size: 16, color: AppColors.surface400),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              if (_sessions.isEmpty && !_sessionsLoading)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  decoration: BoxDecoration(
                    color: AppColors.bg900,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.bg700),
                  ),
                  child: const Column(
                    children: [
                      Icon(Icons.people_outline_rounded, color: AppColors.surface400, size: 28),
                      SizedBox(height: 8),
                      Text(
                        'No one waiting right now',
                        style: TextStyle(color: AppColors.surface400, fontSize: 13),
                      ),
                      Text(
                        'Refreshes every 5 seconds',
                        style: TextStyle(color: AppColors.bg600, fontSize: 11),
                      ),
                    ],
                  ),
                )
              else
                ...(_sessions.map((s) => _SessionCard(
                  session: s,
                  onJoin: _loading ? null : () => _doJoin(s['id'] as String),
                ))),

              const SizedBox(height: 28),

              // Manual entry
              const Text(
                'OR ENTER SESSION ID',
                style: TextStyle(
                  color: AppColors.surface400,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _codeCtrl,
                style: const TextStyle(color: AppColors.white, fontSize: 14, fontFamily: 'monospace'),
                decoration: const InputDecoration(
                  hintText: 'Paste session ID or invite link here',
                ),
                autofocus: false,
                textInputAction: TextInputAction.go,
                onSubmitted: (_) => _joinWithCode(),
              ),
              const SizedBox(height: 8),
              Text(
                'Joining as ${widget.name}',
                style: const TextStyle(color: AppColors.surface400, fontSize: 11),
              ),

              const Spacer(),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _joinWithCode,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brand600,
                    disabledBackgroundColor: AppColors.bg600,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Join with Code', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  final Map<String, dynamic> session;
  final VoidCallback? onJoin;

  const _SessionCard({required this.session, required this.onJoin});

  @override
  Widget build(BuildContext context) {
    final participants = (session['participants'] as List?) ?? [];
    final host = participants.isNotEmpty
        ? (participants.first as Map<String, dynamic>)
        : <String, dynamic>{};
    final hostName = host['name'] as String? ?? 'Unknown';
    final hostLang = host['language'] as String? ?? 'en';
    final flag = kLanguageFlags[hostLang] ?? '🌐';
    final langName = languageName(hostLang);
    final domain = session['domain'] as String? ?? 'general';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.bg900,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.brand600.withOpacity(0.3)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onJoin,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.brand600.withOpacity(0.2),
                child: Text(
                  hostName.isNotEmpty ? hostName[0].toUpperCase() : '?',
                  style: const TextStyle(
                    color: AppColors.brand400,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hostName,
                      style: const TextStyle(
                        color: AppColors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$flag $langName · $domain',
                      style: const TextStyle(color: AppColors.surface400, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.brand600,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'Join',
                  style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
