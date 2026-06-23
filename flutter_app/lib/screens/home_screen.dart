import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/session.dart';
import '../providers/auth_provider.dart';
import '../providers/call_provider.dart';
import '../services/api_service.dart';
import '../services/lobby_service.dart';
import '../services/notification_service.dart';
import '../utils/phone_utils.dart';
import '../theme/app_theme.dart';
import '../widgets/language_selector.dart';
import 'call_screen.dart';
import 'direct_chat_screen.dart';
import 'join_screen.dart';

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

class _HomeScreenState extends ConsumerState<HomeScreen> with WidgetsBindingObserver {
  int _navIndex = 0;
  late String _language;
  bool _loading = false;
  String _loadingMessage = '';

  // Lobby
  final _lobby = LobbyService();
  List<OnlineUser> _onlineUsers = [];
  bool _lobbyConnected = false;
  IncomingCall? _incomingCall;
  Timer? _callTimeoutTimer;

  // Chats tab state
  List<Map<String, dynamic>> _conversations = [];
  bool _convsLoading = true;
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  // Calls tab state
  final _phoneCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _language = widget.initialLanguage;
    _setupLobbyCallbacks();
    _setupFcmCallbacks();

    if (widget.initialName.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final profile = ref.read(authProvider);
        if (profile != null) {
          await ApiService.registerUser(
            phone: PhoneUtils.normalize(profile.phone),
            name: profile.name,
            language: profile.language,
          );
          await NotificationService.syncFcmToken(
            profile.phone,
            name: profile.name,
            language: profile.language,
          );
        }
        _connectLobby(widget.initialName, widget.initialLanguage, phone: profile?.phone);
        _loadConversations();
      });
    } else {
      _convsLoading = false;
    }

    _searchCtrl.addListener(() => setState(() => _searchQuery = _searchCtrl.text.toLowerCase()));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    NotificationService.onIncomingCallData = null;
    _searchCtrl.dispose();
    _phoneCtrl.dispose();
    _callTimeoutTimer?.cancel();
    _lobby.disconnect();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final profile = ref.read(authProvider);
    if (profile == null) return;
    NotificationService.syncFcmToken(
      profile.phone,
      name: profile.name,
      language: profile.language,
    );
    _connectLobby(profile.name, profile.language, phone: profile.phone);
  }

  // ── FCM ──────────────────────────────────────────────────────────────────

  void _setupFcmCallbacks() {
    NotificationService.onIncomingCallData = _handleFcmCallData;
    final pending = NotificationService.pendingCallData;
    if (pending != null) {
      NotificationService.pendingCallData = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _handleFcmCallData(pending));
    }
  }

  void _handleFcmCallData(Map<String, dynamic> data) {
    if (!mounted) return;
    NotificationService.showIncomingCallFromData(data);
    final call = IncomingCall(
      callerId: data['caller_id'] ?? '',
      callerName: data['caller_name'] ?? 'Unknown',
      callerLanguage: data['caller_language'] ?? 'en',
      sessionId: data['session_id'] ?? '',
    );
    final autoAccept = data['auto_accept'] == true || data['auto_accept'] == 'true';
    if (autoAccept) {
      _acceptCall(call);
      return;
    }
    setState(() => _incomingCall = call);
  }

  // ── Lobby ─────────────────────────────────────────────────────────────────

  void _setupLobbyCallbacks() {
    // Keep _lobbyConnected in sync with the actual socket state — without
    // this, a lobby drop mid-session (e.g. during a call) leaves the flag
    // stuck on true forever, so later call attempts get silently swallowed
    // by LobbyService._send()'s connected check with zero user feedback.
    _lobby.onConnected = () {
      if (mounted) setState(() => _lobbyConnected = true);
    };
    _lobby.onDisconnected = () {
      if (mounted) setState(() => _lobbyConnected = false);
    };

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
      if (!mounted) return;
      NotificationService.showIncomingCallFromData({
        'caller_id': call.callerId,
        'caller_name': call.callerName,
        'caller_language': call.callerLanguage,
        'session_id': call.sessionId,
        'type': 'incoming_call',
      });
      setState(() => _incomingCall = call);
    };

    _lobby.onCallInitiated = (call) async {
      if (!mounted) return;
      if (!call.targetFound) {
        _toast('User not found or unavailable');
        if (mounted) setState(() { _loading = false; _loadingMessage = ''; });
        return;
      }

      final _goCall = () async {
        try {
          await ref.read(callProvider.notifier).enterAsHost(
            sessionId: call.sessionId,
            participantId: call.participantId,
            name: ref.read(authProvider)?.name ?? '',
            language: ref.read(authProvider)?.language ?? _language,
          );
          if (!mounted) return;
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CallScreen()));
        } catch (e) {
          _toast(e.toString().replaceAll('Exception: ', ''));
        } finally {
          if (mounted) setState(() { _loading = false; _loadingMessage = ''; });
        }
      };

      if (call.targetUserId.isNotEmpty) {
        await _goCall();
      } else {
        if (mounted) setState(() => _loadingMessage = 'Ringing...');
        _callTimeoutTimer?.cancel();
        _callTimeoutTimer = Timer(const Duration(seconds: 30), () {
          if (mounted) {
            setState(() { _loading = false; _loadingMessage = ''; });
            _toast('No answer');
          }
        });
        await _goCall();
        _callTimeoutTimer?.cancel();
      }
    };

    _lobby.onCallRejected = (byName) {
      if (mounted) {
        setState(() => _loading = false);
        _toast('$byName declined the call');
      }
    };
  }

  Future<void> _connectLobby(String name, String language, {String? phone}) async {
    if (_lobbyConnected) await _lobby.disconnect();
    await _lobby.connect(name: name, language: language, phone: phone);
    if (mounted) setState(() => _lobbyConnected = _lobby.isConnected);
  }

  // ── Conversations ─────────────────────────────────────────────────────────

  Future<void> _loadConversations() async {
    final phone = ref.read(authProvider)?.phone;
    if (phone == null) { setState(() => _convsLoading = false); return; }
    try {
      final convs = await ApiService.getConversations(phone);
      if (mounted) setState(() { _conversations = convs; _convsLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _convsLoading = false);
    }
  }

  // ── Calling ───────────────────────────────────────────────────────────────

  Future<void> _callByPhone(String rawPhone) async {
    final profile = ref.read(authProvider);
    if (profile == null) return;
    final formatted = PhoneUtils.normalize(rawPhone);

    // Check the socket's live state, not just the cached flag — it can lag
    // behind a real disconnect that happened while this screen sat idle.
    if (!_lobby.isConnected) {
      setState(() => _loading = true);
      await _connectLobby(profile.name, profile.language, phone: profile.phone);
      if (!_lobby.isConnected) {
        setState(() => _loading = false);
        _toast('Could not connect to server');
        return;
      }
    }

    setState(() => _loading = true);
    _lobby.callByPhone(formatted);
  }

  Future<void> _callOnlineUser(OnlineUser target) async {
    if (!_lobby.isConnected) {
      final profile = ref.read(authProvider);
      if (profile == null) return;
      setState(() => _loading = true);
      await _connectLobby(profile.name, profile.language, phone: profile.phone);
      if (!_lobby.isConnected) {
        setState(() => _loading = false);
        _toast('Could not connect to server');
        return;
      }
    }
    setState(() => _loading = true);
    _lobby.callUser(target.userId);
  }

  Future<void> _acceptCall(IncomingCall call) async {
    NotificationService.cancelCallNotification();
    setState(() { _incomingCall = null; _loading = true; });
    final profile = ref.read(authProvider);
    try {
      await ref.read(callProvider.notifier).joinSession(
        sessionId: call.sessionId,
        name: profile?.name ?? '',
        language: profile?.language ?? _language,
        phone: profile?.phone,
      );
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CallScreen()));
    } catch (e) {
      _toast(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _rejectCall(IncomingCall call) {
    NotificationService.cancelCallNotification();
    _lobby.rejectCall(call.callerId);
    setState(() => _incomingCall = null);
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: AppColors.bg700,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: AppColors.bg950,
          appBar: _buildAppBar(),
          body: _navIndex == 0 ? _buildChatsTab() : _buildCallsTab(),
          bottomNavigationBar: _buildBottomNav(),
          floatingActionButton: _navIndex == 0 ? _buildFab() : null,
        ),
        if (_incomingCall != null)
          _IncomingCallOverlay(
            call: _incomingCall!,
            onAccept: () => _acceptCall(_incomingCall!),
            onReject: () => _rejectCall(_incomingCall!),
          ),
      ],
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final profile = ref.read(authProvider);
    final initial = (profile?.name ?? 'V').isNotEmpty ? (profile?.name ?? 'V')[0].toUpperCase() : 'V';

    return AppBar(
      backgroundColor: AppColors.bg900,
      elevation: 0,
      title: _navIndex == 0
          ? Text(_searchQuery.isEmpty ? 'VoiceTranslate' : 'Search',
              style: const TextStyle(color: AppColors.white, fontSize: 20, fontWeight: FontWeight.w700))
          : const Text('Calls', style: TextStyle(color: AppColors.white, fontSize: 20, fontWeight: FontWeight.w700)),
      actions: [
        if (_navIndex == 0) ...[
          IconButton(
            icon: const Icon(Icons.search_rounded, color: AppColors.surface400),
            onPressed: () => showSearch(context: context, delegate: _ChatSearchDelegate(_conversations, _openChat)),
          ),
        ],
        // Profile / sign-out
        GestureDetector(
          onTap: () => _showProfileMenu(),
          child: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.brand600.withOpacity(0.25),
              child: Text(initial, style: const TextStyle(color: AppColors.brand400, fontSize: 13, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      ],
      bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Container(height: 1, color: AppColors.bg700)),
    );
  }

  void _showProfileMenu() {
    final profile = ref.read(authProvider);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bg900,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: AppColors.brand600.withOpacity(0.2),
              child: Text(
                (profile?.name ?? 'V').isNotEmpty ? (profile?.name ?? 'V')[0].toUpperCase() : 'V',
                style: const TextStyle(color: AppColors.brand400, fontSize: 28, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 12),
            Text(profile?.name ?? '', style: const TextStyle(color: AppColors.white, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(profile?.phone ?? '', style: const TextStyle(color: AppColors.surface400, fontSize: 14)),
            const SizedBox(height: 4),
            Text('${languageFlag(profile?.language ?? 'en')} ${languageName(profile?.language ?? 'en')}',
                style: const TextStyle(color: AppColors.surface400, fontSize: 13)),
            const SizedBox(height: 24),
            // Language selector
            LanguageSelector(
              value: profile?.language ?? _language,
              onChanged: (v) async {
                setState(() => _language = v);
                if (profile != null) {
                  await ref.read(authProvider.notifier).updateLanguage(v);
                }
                if (mounted) Navigator.pop(context);
              },
              label: 'Your Language',
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  Navigator.pop(context);
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      backgroundColor: AppColors.bg800,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      title: const Text('Sign Out?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel', style: TextStyle(color: AppColors.surface400))),
                        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sign Out', style: TextStyle(color: AppColors.red500))),
                      ],
                    ),
                  );
                  if (confirm == true && mounted) await ref.read(authProvider.notifier).signOut();
                },
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: const Text('Sign Out'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.red500,
                  side: const BorderSide(color: AppColors.red500),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      currentIndex: _navIndex,
      onTap: (i) {
        setState(() => _navIndex = i);
        if (i == 0) _loadConversations();
        if (i == 1 && !_lobbyConnected) {
          final profile = ref.read(authProvider);
          if (profile != null) _connectLobby(profile.name, profile.language, phone: profile.phone);
        }
      },
      backgroundColor: AppColors.bg900,
      selectedItemColor: AppColors.brand400,
      unselectedItemColor: AppColors.surface400,
      selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
      type: BottomNavigationBarType.fixed,
      items: [
        BottomNavigationBarItem(
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.chat_bubble_rounded),
              if (_conversations.any((c) => (c['unread_count'] as num? ?? 0) > 0))
                Positioned(
                  right: -4, top: -2,
                  child: Container(
                    width: 8, height: 8,
                    decoration: const BoxDecoration(color: AppColors.brand500, shape: BoxShape.circle),
                  ),
                ),
            ],
          ),
          label: 'Chats',
        ),
        const BottomNavigationBarItem(
          icon: Icon(Icons.call_rounded),
          label: 'Calls',
        ),
      ],
    );
  }

  Widget _buildFab() {
    return FloatingActionButton(
      onPressed: _showNewChatDialog,
      backgroundColor: AppColors.brand600,
      child: const Icon(Icons.chat_rounded, color: Colors.white),
    );
  }

  // ── Chats Tab ─────────────────────────────────────────────────────────────

  Widget _buildChatsTab() {
    if (_convsLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final filtered = _searchQuery.isEmpty
        ? _conversations
        : _conversations.where((c) {
            final name = (c['other_name'] as String? ?? '').toLowerCase();
            final phone = (c['other_phone'] as String? ?? '').toLowerCase();
            return name.contains(_searchQuery) || phone.contains(_searchQuery);
          }).toList();

    if (_conversations.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.chat_bubble_outline_rounded, size: 64, color: AppColors.bg600),
            const SizedBox(height: 16),
            const Text('No chats yet', style: TextStyle(color: AppColors.white, fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            const Text('Tap the button below to start a conversation', style: TextStyle(color: AppColors.surface400, fontSize: 13)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadConversations,
      color: AppColors.brand400,
      backgroundColor: AppColors.bg800,
      child: ListView.builder(
        itemCount: filtered.length,
        itemBuilder: (_, i) => _ChatRow(
          conv: filtered[i],
          onTap: () => _openChat(filtered[i]),
        ),
      ),
    );
  }

  void _openChat(Map<String, dynamic> conv) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DirectChatScreen(
        otherPhone: conv['other_phone'] as String,
        otherName: conv['other_name'] as String? ?? conv['other_phone'] as String,
        otherLanguage: conv['other_language'] as String? ?? 'en',
        onCall: (phone) => _callByPhone(phone),
      ),
    )).then((_) => _loadConversations());
  }

  void _showNewChatDialog() {
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bg900,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('New Chat', style: TextStyle(color: AppColors.white, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.phone,
              autofocus: true,
              style: const TextStyle(color: AppColors.white),
              decoration: const InputDecoration(
                hintText: '03XX XXXXXXX or +92...',
                prefixIcon: Icon(Icons.dialpad_rounded, color: AppColors.bg500, size: 20),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brand600,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  final raw = ctrl.text.trim();
                  if (raw.isEmpty) return;
                  final formatted = PhoneUtils.normalize(raw);
                  Navigator.pop(context);
                  final user = await ApiService.findUserByPhone(formatted);
                  if (!mounted) return;
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => DirectChatScreen(
                      otherPhone: formatted,
                      otherName: user?['name'] as String? ?? formatted,
                      otherLanguage: user?['language'] as String? ?? 'en',
                      onCall: (phone) => _callByPhone(phone),
                    ),
                  )).then((_) => _loadConversations());
                },
                child: const Text('Open Chat', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Calls Tab ─────────────────────────────────────────────────────────────

  Widget _buildCallsTab() {
    final profile = ref.read(authProvider);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Call by number
          const Text('CALL NUMBER', style: TextStyle(color: AppColors.surface400, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(color: AppColors.white, fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: '03XX XXXXXXX',
                    prefixIcon: Icon(Icons.dialpad_rounded, color: AppColors.bg500, size: 20),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: _loading ? null : () {
                  final phone = _phoneCtrl.text.trim();
                  if (phone.isEmpty) { _toast('Enter a phone number'); return; }
                  _callByPhone(phone);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: _loading ? AppColors.bg600 : const Color(0xFF25D366),
                    shape: BoxShape.circle,
                    boxShadow: _loading ? null : [BoxShadow(color: const Color(0xFF25D366).withOpacity(0.35), blurRadius: 12)],
                  ),
                  child: _loading
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.call_rounded, color: Colors.white, size: 26),
                ),
              ),
            ],
          ),
          if (_loadingMessage.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const SizedBox(width: 4),
                Text(_loadingMessage, style: const TextStyle(color: AppColors.green400, fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () { _callTimeoutTimer?.cancel(); setState(() { _loading = false; _loadingMessage = ''; }); },
                  child: const Text('Cancel', style: TextStyle(color: AppColors.red500, fontSize: 12)),
                ),
              ],
            ),
          ],
          const SizedBox(height: 28),

          // Language
          if (profile != null)
            LanguageSelector(
              value: profile.language,
              onChanged: (v) async {
                setState(() => _language = v);
                await ref.read(authProvider.notifier).updateLanguage(v);
              },
              label: 'Your Language',
            ),
          const SizedBox(height: 28),

          // Online users
          Row(
            children: [
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  color: _lobbyConnected ? AppColors.green400 : AppColors.bg500,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _lobbyConnected ? 'ONLINE NOW (${_onlineUsers.length})' : 'NOT CONNECTED',
                style: const TextStyle(color: AppColors.surface400, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8),
              ),
            ],
          ),
          const SizedBox(height: 10),

          if (_onlineUsers.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(color: AppColors.bg800, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.bg700)),
              child: const Column(
                children: [
                  Icon(Icons.people_outline_rounded, color: AppColors.surface400, size: 28),
                  SizedBox(height: 8),
                  Text('No one else online right now', style: TextStyle(color: AppColors.surface400, fontSize: 13)),
                ],
              ),
            )
          else
            ..._onlineUsers.map((u) => _OnlineUserCard(
              user: u,
              onCall: _loading ? null : () => _callOnlineUser(u),
            )),

          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () {
              final p = ref.read(authProvider);
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => JoinScreen(name: p?.name ?? '', language: p?.language ?? _language),
              ));
            },
            icon: const Icon(Icons.link_rounded, size: 16),
            label: const Text('Join by Session ID'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.surface400,
              side: const BorderSide(color: AppColors.bg600),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              minimumSize: const Size(double.infinity, 44),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Chat Row ─────────────────────────────────────────────────────────────────

class _ChatRow extends StatelessWidget {
  final Map<String, dynamic> conv;
  final VoidCallback onTap;

  const _ChatRow({required this.conv, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = conv['other_name'] as String? ?? conv['other_phone'] as String;
    final lastMsg = conv['last_message'] as String? ?? '';
    final unread = (conv['unread_count'] as num?)?.toInt() ?? 0;
    final lang = conv['other_language'] as String? ?? 'en';
    final flag = kLanguageFlags[lang] ?? '🌐';
    final time = _fmt(conv['created_at'] as String?);
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.bg800))),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: AppColors.brand600.withOpacity(0.2),
                  child: Text(initial, style: const TextStyle(color: AppColors.brand400, fontSize: 20, fontWeight: FontWeight.bold)),
                ),
                Positioned(
                  bottom: -1, right: -1,
                  child: Container(
                    padding: const EdgeInsets.all(1.5),
                    decoration: const BoxDecoration(color: AppColors.bg950, shape: BoxShape.circle),
                    child: Text(flag, style: const TextStyle(fontSize: 10)),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(name,
                            style: TextStyle(color: AppColors.white, fontSize: 15, fontWeight: unread > 0 ? FontWeight.w700 : FontWeight.w500),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      Text(time, style: TextStyle(color: unread > 0 ? AppColors.brand400 : AppColors.surface400, fontSize: 11)),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(lastMsg,
                            style: TextStyle(color: unread > 0 ? AppColors.white : AppColors.surface400, fontSize: 13),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      if (unread > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: const BoxDecoration(color: AppColors.brand600, shape: BoxShape.circle),
                          child: Text('$unread', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      if (dt.day == now.day && dt.month == now.month && dt.year == now.year) {
        return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
      return '${dt.day}/${dt.month}';
    } catch (_) { return ''; }
  }
}

// ── Online User Card ──────────────────────────────────────────────────────────

class _OnlineUserCard extends StatelessWidget {
  final OnlineUser user;
  final VoidCallback? onCall;

  const _OnlineUserCard({required this.user, required this.onCall});

  @override
  Widget build(BuildContext context) {
    final flag = kLanguageFlags[user.language] ?? '🌐';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.bg800,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.green400.withOpacity(0.2)),
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
                  child: Text(user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                      style: const TextStyle(color: AppColors.brand400, fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                Positioned(
                  bottom: 0, right: 0,
                  child: Container(
                    width: 10, height: 10,
                    decoration: BoxDecoration(
                      color: AppColors.green400, shape: BoxShape.circle,
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
                  Text('$flag ${languageName(user.language)}', style: const TextStyle(color: AppColors.surface400, fontSize: 12)),
                ],
              ),
            ),
            GestureDetector(
              onTap: onCall,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.green400.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.green400.withOpacity(0.4)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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

// ── Search Delegate ───────────────────────────────────────────────────────────

class _ChatSearchDelegate extends SearchDelegate<void> {
  final List<Map<String, dynamic>> conversations;
  final void Function(Map<String, dynamic>) onOpen;

  _ChatSearchDelegate(this.conversations, this.onOpen);

  @override
  ThemeData appBarTheme(BuildContext context) => Theme.of(context).copyWith(
    inputDecorationTheme: const InputDecorationTheme(border: InputBorder.none),
    appBarTheme: const AppBarTheme(backgroundColor: AppColors.bg900, elevation: 0),
  );

  @override
  List<Widget> buildActions(BuildContext context) => [
    IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
  ];

  @override
  Widget buildLeading(BuildContext context) =>
      IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => close(context, null));

  @override
  Widget buildResults(BuildContext context) => _buildList(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildList(context);

  Widget _buildList(BuildContext context) {
    final q = query.toLowerCase();
    final results = q.isEmpty ? conversations : conversations.where((c) {
      final name = (c['other_name'] as String? ?? '').toLowerCase();
      final phone = (c['other_phone'] as String? ?? '').toLowerCase();
      return name.contains(q) || phone.contains(q);
    }).toList();

    return Container(
      color: AppColors.bg950,
      child: ListView.builder(
        itemCount: results.length,
        itemBuilder: (_, i) => _ChatRow(conv: results[i], onTap: () { close(context, null); onOpen(results[i]); }),
      ),
    );
  }
}

// ── Incoming Call Overlay ─────────────────────────────────────────────────────

class _IncomingCallOverlay extends StatefulWidget {
  final IncomingCall call;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const _IncomingCallOverlay({required this.call, required this.onAccept, required this.onReject});

  @override
  State<_IncomingCallOverlay> createState() => _IncomingCallOverlayState();
}

class _IncomingCallOverlayState extends State<_IncomingCallOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _ring;
  Timer? _vibrateTimer;

  @override
  void initState() {
    super.initState();
    _ring = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat();
    // Haptic pulse while overlay is visible (ringtone handled by NotificationService)
    HapticFeedback.vibrate();
    _vibrateTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) {
      HapticFeedback.vibrate();
    });
  }

  @override
  void dispose() {
    _vibrateTimer?.cancel();
    _ring.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final flag = kLanguageFlags[widget.call.callerLanguage] ?? '🌐';
    final lang = languageName(widget.call.callerLanguage);

    return Positioned.fill(
      child: Material(
        color: Colors.black.withOpacity(0.92),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedBuilder(
                animation: _ring,
                builder: (_, child) => Stack(
                  alignment: Alignment.center,
                  children: [
                    Transform.scale(
                      scale: 1.0 + _ring.value * 0.5,
                      child: Opacity(
                        opacity: (1.0 - _ring.value) * 0.35,
                        child: Container(width: 130, height: 130, decoration: const BoxDecoration(color: AppColors.green400, shape: BoxShape.circle)),
                      ),
                    ),
                    child!,
                  ],
                ),
                child: CircleAvatar(
                  radius: 48,
                  backgroundColor: AppColors.green400.withOpacity(0.2),
                  child: Text(
                    widget.call.callerName.isNotEmpty ? widget.call.callerName[0].toUpperCase() : '?',
                    style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: AppColors.white),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              const Text('Incoming Voice Call', style: TextStyle(color: AppColors.surface400, fontSize: 13, letterSpacing: 1)),
              const SizedBox(height: 10),
              Text(widget.call.callerName, style: const TextStyle(color: AppColors.white, fontSize: 30, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text('$flag $lang', style: const TextStyle(color: AppColors.surface400, fontSize: 15)),
              const SizedBox(height: 64),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _CallBtn(icon: Icons.call_end_rounded, color: AppColors.red500, label: 'Decline', onTap: widget.onReject),
                  const SizedBox(width: 72),
                  _CallBtn(icon: Icons.call_rounded, color: AppColors.green400, label: 'Accept', onTap: widget.onAccept),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CallBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _CallBtn({required this.icon, required this.color, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Column(
      children: [
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Icon(icon, color: Colors.white, size: 28),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: AppColors.surface400, fontSize: 12)),
      ],
    ),
  );
}
