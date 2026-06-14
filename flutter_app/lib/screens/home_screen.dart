import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/session.dart';
import '../providers/auth_provider.dart';
import '../providers/call_provider.dart';
import '../services/api_service.dart';
import '../services/lobby_service.dart';
import '../theme/app_theme.dart';
import '../widgets/language_selector.dart';
import 'call_screen.dart';
import 'join_screen.dart';

const _domains = [
  ('general', 'General', '💬'),
  ('medical', 'Medical', '🏥'),
  ('legal', 'Legal', '⚖️'),
  ('business', 'Business', '💼'),
  ('travel', 'Travel', '✈️'),
  ('customer_support', 'Support', '🎧'),
];

class HomeScreen extends ConsumerStatefulWidget {
  final String initialName;
  final String initialLanguage;
  final String? photoUrl;

  const HomeScreen({
    super.key,
    this.initialName = '',
    this.initialLanguage = 'en',
    this.photoUrl,
  });

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  late final TextEditingController _nameCtrl;
  final _targetPhoneCtrl = TextEditingController();
  late String _language;
  String _domain = 'general';
  bool _loading = false;
  Map<String, dynamic>? _targetUser; // found user by phone

  // Lobby
  final _lobby = LobbyService();
  List<OnlineUser> _onlineUsers = [];
  bool _lobbyConnected = false;
  IncomingCall? _incomingCall;
  Timer? _lobbyConnectDebounce;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName);
    _language = widget.initialLanguage;
    _tab = TabController(length: 2, vsync: this);
    _tab.addListener(_onTabChange);
    _nameCtrl.addListener(_onNameChange);
    _setupLobbyCallbacks();
    // Auto-connect lobby if name already provided from profile
    if (widget.initialName.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        // Register user on backend so others can find them by phone
        final profile = ref.read(authProvider);
        if (profile != null) {
          await ApiService.registerUser(
            phone: profile.phone,
            name: profile.name,
            language: profile.language,
          );
        }
        _connectLobby(widget.initialName, widget.initialLanguage);
      });
    }
  }

  @override
  void dispose() {
    _tab.dispose();
    _nameCtrl.dispose();
    _targetPhoneCtrl.dispose();
    _lobbyConnectDebounce?.cancel();
    _lobby.disconnect();
    super.dispose();
  }

  void _setupLobbyCallbacks() {
    _lobby.onOnlineList = (users, myId) {
      if (mounted) setState(() => _onlineUsers = users);
    };

    _lobby.onUserStatusChange = (user, online) {
      if (!mounted) return;
      setState(() {
        if (online) {
          if (!_onlineUsers.any((u) => u.userId == user.userId)) {
            _onlineUsers = [..._onlineUsers, user];
          }
        } else {
          _onlineUsers = _onlineUsers.where((u) => u.userId != user.userId).toList();
        }
      });
    };

    _lobby.onIncomingCall = (call) {
      if (mounted) setState(() => _incomingCall = call);
    };

    _lobby.onCallInitiated = (call) async {
      if (!mounted) return;
      if (!call.targetFound) {
        _toast('User is not available right now');
        return;
      }
      setState(() => _loading = true);
      try {
        await ref.read(callProvider.notifier).enterAsHost(
          sessionId: call.sessionId,
          participantId: call.participantId,
          name: _nameCtrl.text.trim(),
          language: _language,
        );
        await ref.read(callProvider.notifier).startCapture();
        if (!mounted) return;
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CallScreen()));
      } catch (e) {
        _toast(e.toString().replaceAll('Exception: ', ''));
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    };

    _lobby.onCallRejected = (byName) {
      if (mounted) {
        setState(() => _loading = false);
        _toast('$byName declined the call');
      }
    };
  }

  void _onTabChange() {
    if (_tab.index == 1 && !_lobbyConnected) {
      _maybeConnectLobby();
    }
  }

  void _onNameChange() {
    _lobbyConnectDebounce?.cancel();
    _lobbyConnectDebounce = Timer(const Duration(milliseconds: 800), () {
      if (_tab.index == 1 && !_lobbyConnected) {
        _maybeConnectLobby();
      }
    });
  }

  void _maybeConnectLobby() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    _connectLobby(name, _language);
  }

  Future<void> _connectLobby(String name, String language) async {
    if (_lobbyConnected) {
      await _lobby.disconnect();
    }
    await _lobby.connect(name: name, language: language);
    if (mounted) setState(() => _lobbyConnected = _lobby.isConnected);
  }

  Future<void> _createSession() async {
    final profile = ref.read(authProvider);
    if (profile == null) return;

    final targetPhone = _targetPhoneCtrl.text.trim();
    String? resolvedTarget;

    if (targetPhone.isNotEmpty) {
      final formatted = targetPhone.startsWith('+') ? targetPhone : '+92${targetPhone.replaceFirst(RegExp(r'^0'), '')}';
      final found = await ApiService.findUserByPhone(formatted);
      if (found == null) {
        _toast('No user found with that number');
        return;
      }
      resolvedTarget = formatted;
      setState(() => _targetUser = found);
    }

    setState(() => _loading = true);
    try {
      await ref.read(callProvider.notifier).createSession(
        name: profile.name,
        language: profile.language,
        domain: _domain,
        callerPhone: profile.phone,
        targetPhone: resolvedTarget,
      );
      if (!mounted) return;
      await ref.read(callProvider.notifier).startCapture();
      _goToCall();
    } catch (e) {
      _toast(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _callUser(OnlineUser target) {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) { _toast('Please enter your name first'); return; }
    if (!_lobbyConnected) {
      _maybeConnectLobby();
      _toast('Connecting… try again in a moment');
      return;
    }
    setState(() => _loading = true);
    _lobby.callUser(target.userId);
  }

  Future<void> _acceptCall(IncomingCall call) async {
    setState(() { _incomingCall = null; _loading = true; });
    final profile = ref.read(authProvider);
    try {
      await ref.read(callProvider.notifier).joinSession(
        sessionId: call.sessionId,
        name: profile?.name ?? _nameCtrl.text.trim(),
        language: profile?.language ?? _language,
        phone: profile?.phone,
      );
      await ref.read(callProvider.notifier).startCapture();
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CallScreen()));
    } catch (e) {
      _toast(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _rejectCall(IncomingCall call) {
    _lobby.rejectCall(call.callerId);
    setState(() => _incomingCall = null);
  }

  void _goToCall() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CallScreen()));
  }

  void _openJoin() {
    final profile = ref.read(authProvider);
    final name = profile?.name ?? _nameCtrl.text.trim();
    final language = profile?.language ?? _language;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => JoinScreen(name: name, language: language)),
    );
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.bg700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const SizedBox(height: 24),
                  _buildHero().animate().fadeIn(duration: 600.ms).slideY(begin: -0.1, end: 0),
                  const SizedBox(height: 32),
                  _buildChips().animate().fadeIn(delay: 200.ms, duration: 500.ms),
                  const SizedBox(height: 32),
                  _buildCard().animate().fadeIn(delay: 300.ms, duration: 500.ms).slideY(begin: 0.1, end: 0),
                  const SizedBox(height: 32),
                  _buildStats().animate().fadeIn(delay: 400.ms, duration: 500.ms),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
        // Incoming call overlay
        if (_incomingCall != null) _IncomingCallOverlay(
          call: _incomingCall!,
          onAccept: () => _acceptCall(_incomingCall!),
          onReject: () => _rejectCall(_incomingCall!),
        ),
      ],
    );
  }

  Widget _buildHero() {
    final name = _nameCtrl.text.trim();
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'V';
    return Column(
      children: [
        // Profile row
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Avatar
            widget.photoUrl != null
                ? CircleAvatar(
                    radius: 22,
                    backgroundImage: NetworkImage(widget.photoUrl!),
                  )
                : CircleAvatar(
                    radius: 22,
                    backgroundColor: AppColors.brand600.withOpacity(0.25),
                    child: Text(initial,
                        style: const TextStyle(
                            color: AppColors.brand400,
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                  ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isNotEmpty ? name : 'Voice Translate',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                Consumer(builder: (_, ref, __) {
                  final p = ref.watch(authProvider);
                  return Text(
                    p?.phone ?? '${languageFlag(_language)} ${languageName(_language)}',
                    style: const TextStyle(color: AppColors.surface400, fontSize: 12),
                  );
                }),
              ],
            ),
            const Spacer(),
            // Sign out
            GestureDetector(
              onTap: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    backgroundColor: AppColors.bg800,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    title: const Text('Sign Out?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel',
                            style: TextStyle(color: AppColors.surface400)),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Sign Out',
                            style: TextStyle(color: AppColors.red500)),
                      ),
                    ],
                  ),
                );
                if (confirm == true && mounted) {
                  await ref.read(authProvider.notifier).signOut();
                }
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.bg800,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.bg700),
                ),
                child: const Icon(Icons.logout_rounded,
                    color: AppColors.surface400, size: 18),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Text(
          'Speak in any language.\nHeard in every language.',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 24, fontWeight: FontWeight.w700, height: 1.3),
        ),
        const SizedBox(height: 8),
        const Text(
          'Real-time AI voice translation for natural\nmultilingual conversations.',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 13, color: AppColors.surface400, height: 1.5),
        ),
      ],
    );
  }

  Widget _buildChips() => Wrap(
    alignment: WrapAlignment.center,
    spacing: 8, runSpacing: 8,
    children: ['20 Languages', 'Sub-2s Latency', 'Context-Aware', 'Healthcare Ready']
        .map((f) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.bg800,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.bg700),
              ),
              child: Text(f, style: const TextStyle(fontSize: 12, color: AppColors.surface400)),
            ))
        .toList(),
  );

  Widget _buildCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bg900,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.bg700),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.bg800,
              borderRadius: BorderRadius.circular(14),
            ),
            child: TabBar(
              controller: _tab,
              indicator: BoxDecoration(
                color: AppColors.brand600,
                borderRadius: BorderRadius.circular(12),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelColor: AppColors.white,
              unselectedLabelColor: AppColors.surface400,
              labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              tabs: const [Tab(text: 'New Call'), Tab(text: 'Join Call')],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: AnimatedBuilder(
              animation: _tab,
              builder: (_, __) => _tab.index == 0 ? _buildCreateForm() : _buildJoinForm(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreateForm() {
    final profile = ref.read(authProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Target phone number
        const Text('CALL NUMBER', style: TextStyle(color: AppColors.surface400, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8)),
        const SizedBox(height: 6),
        TextField(
          controller: _targetPhoneCtrl,
          keyboardType: TextInputType.phone,
          style: const TextStyle(color: AppColors.white, fontSize: 14),
          decoration: const InputDecoration(
            hintText: '03XX XXXXXXX  (leave empty for open session)',
            prefixIcon: Icon(Icons.dialpad_rounded, color: AppColors.bg500, size: 20),
          ),
          onChanged: (_) => setState(() => _targetUser = null),
        ),
        if (_targetUser != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.green400.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.green400.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: AppColors.green400, size: 16),
                const SizedBox(width: 8),
                Text(
                  '${_targetUser!['name']}  •  ${languageFlag(_targetUser!['language'])} ${languageName(_targetUser!['language'])}',
                  style: const TextStyle(color: AppColors.green400, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        // Language selector (user can change their own language)
        LanguageSelector(
          value: profile?.language ?? _language,
          onChanged: (v) async {
            setState(() => _language = v);
            if (profile != null) {
              await ref.read(authProvider.notifier).updateLanguage(v);
            }
          },
          label: 'Your Language',
        ),
        const SizedBox(height: 16),
        const Text('CONVERSATION DOMAIN', style: TextStyle(color: AppColors.surface400, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8)),
        const SizedBox(height: 8),
        _domainGrid(),
        const SizedBox(height: 20),
        _primaryButton('Start Call', _createSession),
      ],
    );
  }

  Widget _buildJoinForm() {
    final profile = ref.read(authProvider);
    return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      LanguageSelector(
        value: profile?.language ?? _language,
        onChanged: (v) async {
          setState(() => _language = v);
          if (profile != null) {
            await ref.read(authProvider.notifier).updateLanguage(v);
          }
        },
        label: 'Your Language',
      ),
      const SizedBox(height: 20),

      // Online users section
      Row(
        children: [
          Row(
            children: [
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  color: _lobbyConnected ? AppColors.green400 : AppColors.surface400,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                _lobbyConnected ? 'ONLINE NOW' : 'CONNECT TO SEE ONLINE USERS',
                style: const TextStyle(color: AppColors.surface400, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8),
              ),
            ],
          ),
          const Spacer(),
          if (!_lobbyConnected)
            GestureDetector(
              onTap: _maybeConnectLobby,
              child: const Text('Go Online', style: TextStyle(color: AppColors.brand400, fontSize: 12, fontWeight: FontWeight.w500)),
            ),
        ],
      ),
      const SizedBox(height: 8),

      if (!_lobbyConnected)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: AppColors.bg800,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.bg700),
          ),
          child: const Column(
            children: [
              Icon(Icons.wifi_off_rounded, color: AppColors.surface400, size: 24),
              SizedBox(height: 6),
              Text('Enter your name and tap "Go Online"', style: TextStyle(color: AppColors.surface400, fontSize: 12)),
            ],
          ),
        )
      else if (_onlineUsers.isEmpty)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: AppColors.bg800,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.bg700),
          ),
          child: const Column(
            children: [
              Icon(Icons.people_outline_rounded, color: AppColors.surface400, size: 24),
              SizedBox(height: 6),
              Text('No one else online right now', style: TextStyle(color: AppColors.surface400, fontSize: 12)),
            ],
          ),
        )
      else
        ..._onlineUsers.map((u) => _OnlineUserCard(
          user: u,
          onCall: _loading ? null : () => _callUser(u),
        )),

      const SizedBox(height: 16),
      const Divider(color: AppColors.bg700),
      const SizedBox(height: 12),

      // Join by session ID
      OutlinedButton.icon(
        onPressed: _openJoin,
        icon: const Icon(Icons.link_rounded, size: 16),
        label: const Text('Join by Session ID / Link'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.surface400,
          side: const BorderSide(color: AppColors.bg600),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          minimumSize: const Size(double.infinity, 44),
        ),
      ),
    ],
  );
  }

  Widget _nameField() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('YOUR NAME', style: TextStyle(color: AppColors.surface400, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8)),
      const SizedBox(height: 6),
      TextField(
        controller: _nameCtrl,
        style: const TextStyle(color: AppColors.white, fontSize: 14),
        decoration: const InputDecoration(hintText: 'Enter your name'),
        textInputAction: TextInputAction.next,
        inputFormatters: [LengthLimitingTextInputFormatter(40)],
      ),
    ],
  );

  Widget _domainGrid() => GridView.count(
    shrinkWrap: true,
    crossAxisCount: 3,
    mainAxisSpacing: 8,
    crossAxisSpacing: 8,
    childAspectRatio: 1.6,
    physics: const NeverScrollableScrollPhysics(),
    children: _domains.map((d) {
      final selected = _domain == d.$1;
      return GestureDetector(
        onTap: () => setState(() => _domain = d.$1),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: selected ? const Color(0x264C6EF5) : AppColors.bg800,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? AppColors.brand500 : AppColors.bg600),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(d.$3, style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 2),
              Text(
                d.$2,
                style: TextStyle(
                  fontSize: 10,
                  color: selected ? AppColors.brand300 : AppColors.surface400,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }).toList(),
  );

  Widget _primaryButton(String label, VoidCallback onTap) => SizedBox(
    width: double.infinity,
    child: ElevatedButton(
      onPressed: _loading ? null : onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.brand600,
        disabledBackgroundColor: AppColors.bg600,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: _loading
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
    ),
  );

  Widget _buildStats() => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      _stat('20+', 'Languages'),
      _divider(),
      _stat('< 2s', 'Avg Latency'),
      _divider(),
      _stat('98%+', 'Accuracy'),
    ],
  );

  Widget _stat(String val, String label) => Column(
    children: [
      Text(val, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.brand400)),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(fontSize: 11, color: AppColors.surface400)),
    ],
  );

  Widget _divider() => Container(
    width: 1, height: 36, margin: const EdgeInsets.symmetric(horizontal: 24),
    color: AppColors.bg700,
  );
}

class _OnlineUserCard extends StatelessWidget {
  final OnlineUser user;
  final VoidCallback? onCall;

  const _OnlineUserCard({required this.user, required this.onCall});

  @override
  Widget build(BuildContext context) {
    final flag = kLanguageFlags[user.language] ?? '🌐';
    final lang = languageName(user.language);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.bg800,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.green400.withOpacity(0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: AppColors.brand600.withOpacity(0.2),
                  child: Text(
                    user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                    style: const TextStyle(color: AppColors.brand400, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                Positioned(
                  bottom: 0, right: 0,
                  child: Container(
                    width: 10, height: 10,
                    decoration: BoxDecoration(
                      color: AppColors.green400,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.bg800, width: 1.5),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.name, style: const TextStyle(color: AppColors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                  Text('$flag $lang', style: const TextStyle(color: AppColors.surface400, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onCall,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.green400.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.green400.withOpacity(0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.call_rounded, color: AppColors.green400, size: 16),
                    SizedBox(width: 4),
                    Text('Call', style: TextStyle(color: AppColors.green400, fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IncomingCallOverlay extends StatefulWidget {
  final IncomingCall call;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const _IncomingCallOverlay({
    required this.call,
    required this.onAccept,
    required this.onReject,
  });

  @override
  State<_IncomingCallOverlay> createState() => _IncomingCallOverlayState();
}

class _IncomingCallOverlayState extends State<_IncomingCallOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ring;

  @override
  void initState() {
    super.initState();
    _ring = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
  }

  @override
  void dispose() {
    _ring.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final flag = kLanguageFlags[widget.call.callerLanguage] ?? '🌐';
    final lang = languageName(widget.call.callerLanguage);

    return Positioned.fill(
      child: Material(
        color: Colors.black.withOpacity(0.85),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Pulsing ring
              AnimatedBuilder(
                animation: _ring,
                builder: (_, child) => Stack(
                  alignment: Alignment.center,
                  children: [
                    Transform.scale(
                      scale: 1.0 + _ring.value * 0.5,
                      child: Opacity(
                        opacity: (1.0 - _ring.value) * 0.4,
                        child: Container(
                          width: 120, height: 120,
                          decoration: const BoxDecoration(
                            color: AppColors.green400,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                    child!,
                  ],
                ),
                child: CircleAvatar(
                  radius: 44,
                  backgroundColor: AppColors.green400.withOpacity(0.2),
                  child: Text(
                    widget.call.callerName.isNotEmpty
                        ? widget.call.callerName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: AppColors.white),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'Incoming Call',
                style: TextStyle(color: AppColors.surface400, fontSize: 14, letterSpacing: 1),
              ),
              const SizedBox(height: 8),
              Text(
                widget.call.callerName,
                style: const TextStyle(color: AppColors.white, fontSize: 28, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                '$flag $lang',
                style: const TextStyle(color: AppColors.surface400, fontSize: 15),
              ),
              const SizedBox(height: 60),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Reject
                  GestureDetector(
                    onTap: widget.onReject,
                    child: Column(
                      children: [
                        Container(
                          width: 64, height: 64,
                          decoration: const BoxDecoration(
                            color: Color(0xFFE53E3E),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 28),
                        ),
                        const SizedBox(height: 8),
                        const Text('Decline', style: TextStyle(color: AppColors.surface400, fontSize: 12)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 64),
                  // Accept
                  GestureDetector(
                    onTap: widget.onAccept,
                    child: Column(
                      children: [
                        Container(
                          width: 64, height: 64,
                          decoration: const BoxDecoration(
                            color: AppColors.green400,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.call_rounded, color: Colors.white, size: 28),
                        ),
                        const SizedBox(height: 8),
                        const Text('Accept', style: TextStyle(color: AppColors.surface400, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: 300.ms);
  }
}
