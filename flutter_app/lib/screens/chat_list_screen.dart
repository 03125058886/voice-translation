import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/language_selector.dart';
import 'direct_chat_screen.dart';

class ChatListScreen extends ConsumerStatefulWidget {
  const ChatListScreen({super.key});

  @override
  ConsumerState<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends ConsumerState<ChatListScreen> {
  List<Map<String, dynamic>> _conversations = [];
  bool _loading = true;
  final _phoneCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final phone = ref.read(authProvider)?.phone;
    if (phone == null) return;
    try {
      final convs = await ApiService.getConversations(phone);
      if (mounted) setState(() { _conversations = convs; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openChat({required String otherPhone, required String otherName, required String otherLanguage}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DirectChatScreen(
          otherPhone: otherPhone,
          otherName: otherName,
          otherLanguage: otherLanguage,
        ),
      ),
    ).then((_) => _load());
  }

  void _startNewChat() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bg900,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('New Message', style: TextStyle(color: AppColors.white, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            TextField(
              controller: _phoneCtrl,
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
                  final raw = _phoneCtrl.text.trim();
                  if (raw.isEmpty) return;
                  final formatted = raw.startsWith('+') ? raw : '+92${raw.replaceFirst(RegExp(r'^0'), '')}';
                  Navigator.of(context).pop();
                  _phoneCtrl.clear();

                  // Try to find user name
                  final user = await ApiService.findUserByPhone(formatted);
                  if (!mounted) return;
                  _openChat(
                    otherPhone: formatted,
                    otherName: user?['name'] as String? ?? formatted,
                    otherLanguage: user?['language'] as String? ?? 'en',
                  );
                },
                child: const Text('Open Chat', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg950,
      appBar: AppBar(
        backgroundColor: AppColors.bg900,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.white, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Messages', style: TextStyle(color: AppColors.white, fontSize: 17, fontWeight: FontWeight.w700)),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.bg700),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _startNewChat,
        backgroundColor: AppColors.brand600,
        child: const Icon(Icons.edit_rounded, color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _conversations.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.chat_bubble_outline_rounded, size: 56, color: AppColors.bg600),
                      const SizedBox(height: 16),
                      const Text('No messages yet', style: TextStyle(color: AppColors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      const Text('Tap the pencil button to start a conversation',
                          style: TextStyle(color: AppColors.surface400, fontSize: 13)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    itemCount: _conversations.length,
                    itemBuilder: (_, i) {
                      final c = _conversations[i];
                      final name = c['other_name'] as String? ?? c['other_phone'] as String;
                      final phone = c['other_phone'] as String;
                      final lastMsg = c['last_message'] as String? ?? '';
                      final unread = (c['unread_count'] as num?)?.toInt() ?? 0;
                      final lang = c['other_language'] as String? ?? 'en';
                      final flag = kLanguageFlags[lang] ?? '🌐';
                      final time = _formatTime(c['created_at'] as String?);
                      return InkWell(
                        onTap: () => _openChat(otherPhone: phone, otherName: name, otherLanguage: lang),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: const BoxDecoration(
                            border: Border(bottom: BorderSide(color: AppColors.bg800)),
                          ),
                          child: Row(
                            children: [
                              Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  CircleAvatar(
                                    radius: 24,
                                    backgroundColor: AppColors.brand600.withOpacity(0.2),
                                    child: Text(
                                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                                      style: const TextStyle(color: AppColors.brand400, fontSize: 20, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: -2, right: -2,
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: const BoxDecoration(color: AppColors.bg950, shape: BoxShape.circle),
                                      child: Text(flag, style: const TextStyle(fontSize: 11)),
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
                                              style: TextStyle(
                                                  color: AppColors.white,
                                                  fontSize: 15,
                                                  fontWeight: unread > 0 ? FontWeight.w700 : FontWeight.w500),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis),
                                        ),
                                        Text(time, style: const TextStyle(color: AppColors.surface400, fontSize: 11)),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(lastMsg,
                                              style: TextStyle(
                                                  color: unread > 0 ? AppColors.white : AppColors.surface400,
                                                  fontSize: 13),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis),
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
                    },
                  ),
                ),
    );
  }

  String _formatTime(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      if (dt.day == now.day && dt.month == now.month && dt.year == now.year) {
        return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
      return '${dt.day}/${dt.month}';
    } catch (_) {
      return '';
    }
  }
}
