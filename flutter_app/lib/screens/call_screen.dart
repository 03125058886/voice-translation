import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import '../config/app_config.dart';
import '../models/session.dart';
import '../providers/call_provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/chat_panel.dart';

// Keep screen on during calls
import 'package:flutter/services.dart' show SystemChrome;

class CallScreen extends ConsumerStatefulWidget {
  const CallScreen({super.key});

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  final _feedCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    // Keep screen on during call
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final st = ref.read(callProvider);
      if (!st.isCapturing) {
        try {
          await ref.read(callProvider.notifier).startCapture();
        } catch (_) {}
      }
      _loadChatHistory();
    });
  }

  @override
  void dispose() {
    _feedCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadChatHistory() async {
    final sessionId = ref.read(callProvider).sessionId;
    if (sessionId == null) return;
    try {
      final history = await ApiService.getChatMessages(sessionId);
      ref.read(callProvider.notifier).loadChatHistory(history);
    } catch (_) {}
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_feedCtrl.hasClients) {
        _feedCtrl.animateTo(
          _feedCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(callProvider);

    // Auto-navigate back when remote party ends the call
    if (state.remoteEnded) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await ref.read(callProvider.notifier).endCall();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Call ended by the other person'),
              backgroundColor: AppColors.bg700,
              behavior: SnackBarBehavior.floating,
            ),
          );
          Navigator.of(context).pop();
        }
      });
    }

    // Auto-scroll when new content arrives
    final feedLength = state.transcript.length + state.chatMessages.length;
    if (feedLength > 0) _scrollToBottom();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (_) => _EndCallDialog(),
          );
          if (confirmed == true) {
            await ref.read(callProvider.notifier).endCall();
            if (context.mounted) Navigator.of(context).pop();
          }
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.bg950,
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: Column(
            children: [
              _Header(state: state),
              _ParticipantsRow(state: state),
              Expanded(
                child: _UnifiedFeed(
                  state: state,
                  controller: _feedCtrl,
                ),
              ),
              // Chat input bar
              state.sessionId != null && state.participantId != null
                  ? ChatInputBar(
                      sessionId: state.sessionId!,
                      participantId: state.participantId!,
                      participantName: state.myName,
                    )
                  : const SizedBox.shrink(),
              _ControlBar(state: state),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Unified Feed ─────────────────────────────────────────────────────────────

class _FeedItem {
  final DateTime time;
  final TranscriptEntry? transcript;
  final ChatMessage? chat;

  _FeedItem.transcript(TranscriptEntry t)
      : time = t.timestamp,
        transcript = t,
        chat = null;

  _FeedItem.chat(ChatMessage c)
      : time = c.createdAt,
        transcript = null,
        chat = c;
}

class _UnifiedFeed extends StatelessWidget {
  final CallState state;
  final ScrollController controller;

  const _UnifiedFeed({required this.state, required this.controller});

  @override
  Widget build(BuildContext context) {
    final items = [
      ...state.transcript.map(_FeedItem.transcript),
      ...state.chatMessages.map(_FeedItem.chat),
    ]..sort((a, b) => a.time.compareTo(b.time));

    if (items.isEmpty && state.partialText.isEmpty) {
      return _EmptyFeed(status: state.status);
    }

    return ListView.builder(
      controller: controller,
      padding: const EdgeInsets.all(12),
      itemCount: items.length + (state.partialText.isNotEmpty ? 1 : 0),
      itemBuilder: (_, i) {
        if (i == items.length) {
          return _PartialTextTile(
            text: state.partialText,
            name: state.otherName ?? '…',
          );
        }
        final item = items[i];
        if (item.transcript != null) {
          return _TranslationTile(entry: item.transcript!);
        } else {
          return _ChatBubble(
            msg: item.chat!,
            apiBase: AppConfig.apiBaseUrl,
            sessionId: state.sessionId ?? '',
            myLanguage: state.myLanguage,
          );
        }
      },
    );
  }
}

class _EmptyFeed extends StatelessWidget {
  final SessionStatus status;
  const _EmptyFeed({required this.status});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            status == SessionStatus.waiting
                ? Icons.hourglass_top_rounded
                : Icons.chat_bubble_outline_rounded,
            color: AppColors.bg600,
            size: 40,
          ),
          const SizedBox(height: 12),
          Text(
            status == SessionStatus.waiting
                ? 'Waiting for the other person…'
                : 'Speak to start translating',
            style: const TextStyle(color: AppColors.surface400, fontSize: 13),
          ),
          const SizedBox(height: 4),
          const Text(
            'Translations and messages appear here',
            style: TextStyle(color: AppColors.bg600, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _PartialTextTile extends StatelessWidget {
  final String text;
  final String name;
  const _PartialTextTile({required this.text, required this.name});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, right: 48),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.hearing_rounded, color: AppColors.surface400, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(color: AppColors.surface400, fontSize: 11)),
                const SizedBox(height: 2),
                Text(
                  text,
                  style: const TextStyle(
                    color: AppColors.surface400,
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    )
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .fadeIn(duration: 600.ms)
        .then()
        .fadeOut(duration: 400.ms);
  }
}

class _TranslationTile extends StatelessWidget {
  final TranscriptEntry entry;
  const _TranslationTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final isLocal = entry.isLocal;
    return Padding(
      padding: EdgeInsets.only(
        bottom: 10,
        left: isLocal ? 32 : 0,
        right: isLocal ? 0 : 32,
      ),
      child: Column(
        crossAxisAlignment:
            isLocal ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // Speaker label
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.translate_rounded, size: 11, color: AppColors.brand400),
                const SizedBox(width: 4),
                Text(
                  isLocal ? 'You' : entry.speakerName,
                  style: const TextStyle(
                    color: AppColors.brand400,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: isLocal
                  ? AppColors.brand600.withOpacity(0.15)
                  : AppColors.bg800,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(14),
                topRight: const Radius.circular(14),
                bottomLeft: Radius.circular(isLocal ? 14 : 4),
                bottomRight: Radius.circular(isLocal ? 4 : 14),
              ),
              border: Border.all(
                color: isLocal
                    ? AppColors.brand600.withOpacity(0.3)
                    : AppColors.bg700,
              ),
            ),
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Translated text (prominent)
                Text(
                  entry.translatedText,
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 6),
                // Original text (subtle)
                Text(
                  entry.originalText,
                  style: const TextStyle(
                    color: AppColors.surface400,
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _timeStr(entry.timestamp),
            style: const TextStyle(color: AppColors.bg500, fontSize: 10),
          ),
        ],
      ),
    );
  }

  String _timeStr(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

class _ChatBubble extends StatefulWidget {
  final ChatMessage msg;
  final String apiBase;
  final String sessionId;
  final String myLanguage;

  const _ChatBubble({
    required this.msg,
    required this.apiBase,
    required this.sessionId,
    required this.myLanguage,
  });

  @override
  State<_ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<_ChatBubble> {
  final _player = AudioPlayer();
  bool _playing = false;
  bool _loading = false;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_loading) return;
    if (_playing) {
      await _player.stop();
      if (mounted) setState(() => _playing = false);
      return;
    }

    setState(() => _loading = true);
    try {
      String url;
      if (widget.msg.isLocal) {
        url = '${widget.apiBase}${widget.msg.fileUrl}';
      } else {
        url = await ApiService.getTranslatedVoice(
          sessionId: widget.sessionId,
          msgId: widget.msg.id,
          language: widget.myLanguage,
        );
      }
      await _player.setUrl(url);
      if (mounted) setState(() { _loading = false; _playing = true; });
      await _player.play();
    } catch (_) {
      // fall through — play original on error
      try {
        final url = '${widget.apiBase}${widget.msg.fileUrl}';
        await _player.setUrl(url);
        if (mounted) setState(() { _loading = false; _playing = true; });
        await _player.play();
      } catch (_) {
        if (mounted) setState(() { _loading = false; });
      }
    }
    if (mounted) setState(() => _playing = false);
  }

  @override
  Widget build(BuildContext context) {
    final me = widget.msg.isLocal;
    return Padding(
      padding: EdgeInsets.only(
        bottom: 6,
        left: me ? 48 : 0,
        right: me ? 0 : 48,
      ),
      child: Column(
        crossAxisAlignment:
            me ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!me)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 2),
              child: Text(
                widget.msg.participantName,
                style: const TextStyle(
                  color: AppColors.surface400,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          Container(
            decoration: BoxDecoration(
              color: me ? AppColors.brand600 : AppColors.bg800,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(me ? 16 : 4),
                bottomRight: Radius.circular(me ? 4 : 16),
              ),
            ),
            constraints: const BoxConstraints(maxWidth: 280),
            child: _content(me),
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              _timeStr(widget.msg.createdAt),
              style: const TextStyle(color: AppColors.bg500, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(bool me) {
    switch (widget.msg.type) {
      case ChatMessageType.text:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            widget.msg.content ?? '',
            style: TextStyle(
              color: me ? Colors.white : AppColors.white,
              fontSize: 14,
            ),
          ),
        );

      case ChatMessageType.image:
        final url = '${widget.apiBase}${widget.msg.fileUrl}';
        return ClipRRect(
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(me ? 16 : 4),
            bottomRight: Radius.circular(me ? 4 : 16),
          ),
          child: Image.network(
            url,
            width: 220,
            fit: BoxFit.cover,
            loadingBuilder: (_, child, p) => p == null
                ? child
                : const SizedBox(
                    width: 220,
                    height: 150,
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
            errorBuilder: (_, __, ___) => const Padding(
              padding: EdgeInsets.all(12),
              child: Icon(Icons.broken_image_rounded, color: AppColors.surface400),
            ),
          ),
        );

      case ChatMessageType.voice:
        final secs = (widget.msg.durationMs ?? 0) ~/ 1000;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: _togglePlay,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: me
                        ? Colors.white.withAlpha(50)
                        : AppColors.brand600.withAlpha(50),
                    shape: BoxShape.circle,
                  ),
                  child: _loading
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: me ? Colors.white : AppColors.brand400,
                          ),
                        )
                      : Icon(
                          _playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: me ? Colors.white : AppColors.brand400,
                          size: 22,
                        ),
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: List.generate(
                      12,
                      (i) => Container(
                        width: 3,
                        height: 4.0 + (i % 4) * 5.0,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(
                          color:
                              (me ? Colors.white : AppColors.brand400).withAlpha(180),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _fmt(secs),
                    style: TextStyle(
                      fontSize: 11,
                      color: me ? Colors.white70 : AppColors.surface400,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );

      case ChatMessageType.file:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.insert_drive_file_rounded,
                color: AppColors.surface400,
                size: 28,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  widget.msg.fileName ?? 'File',
                  style: TextStyle(
                    fontSize: 13,
                    color: me ? Colors.white : AppColors.white,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
    }
  }

  String _timeStr(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  String _fmt(int s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
}

// ─── Header ──────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final CallState state;
  const _Header({required this.state});

  void _showInviteDialog(BuildContext context, String sessionId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bg800,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Invite Someone',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 20),
            const Text('SESSION ID',
                style: TextStyle(
                    color: AppColors.surface400,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: sessionId));
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: const Text('Session ID copied! Share with contact.'),
                  backgroundColor: AppColors.bg700,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ));
              },
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.bg700,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.bg600),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(sessionId,
                          style: const TextStyle(
                              fontSize: 12,
                              fontFamily: 'monospace',
                              color: AppColors.brand300)),
                    ),
                    const Icon(Icons.copy_rounded,
                        size: 16, color: AppColors.surface400),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
                'Tap to copy • Other person pastes this in "Join Call" tab',
                style: TextStyle(color: AppColors.bg500, fontSize: 11)),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: AppColors.bg900,
        border: Border(bottom: BorderSide(color: AppColors.bg700)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
                color: AppColors.brand600,
                borderRadius: BorderRadius.circular(10)),
            child: const Center(
                child: Text('VT',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Voice Translation',
                  style:
                      TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              Text(
                state.sessionId?.substring(0, 8) ?? '...',
                style: const TextStyle(
                    color: AppColors.surface400,
                    fontSize: 11,
                    fontFamily: 'monospace'),
              ),
            ],
          ),
          const Spacer(),
          _StatusBadge(status: state.status),
          const SizedBox(width: 12),
          if (state.sessionId != null)
            GestureDetector(
              onTap: () => _showInviteDialog(context, state.sessionId!),
              child: const Row(
                children: [
                  Icon(Icons.share_rounded,
                      size: 14, color: AppColors.surface400),
                  SizedBox(width: 4),
                  Text('Invite',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.surface400)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final SessionStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      SessionStatus.active => (AppColors.green400, 'In Call'),
      SessionStatus.waiting => (AppColors.yellow400, 'Waiting'),
      _ => (AppColors.surface400, 'Ended'),
    };
    return Row(
      children: [
        Container(
                width: 7,
                height: 7,
                decoration:
                    BoxDecoration(shape: BoxShape.circle, color: color))
            .animate(onPlay: (c) => c.repeat())
            .fadeIn(duration: 600.ms)
            .then()
            .fadeOut(duration: 600.ms),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(
                fontSize: 12, color: color, fontWeight: FontWeight.w500)),
      ],
    );
  }
}

// ─── Participants ─────────────────────────────────────────────────────────────

class _ParticipantsRow extends ConsumerWidget {
  final CallState state;
  const _ParticipantsRow({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.bg700)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ParticipantCard(
              name: state.myName,
              language: state.myLanguage,
              isLocal: true,
              volume: state.volume,
              stage: state.pipelineStage,
              isCapturing: state.isCapturing && !state.isMuted,
            ),
          ),
          Container(
            width: 36,
            alignment: Alignment.center,
            child: const Icon(Icons.swap_horiz_rounded,
                color: AppColors.bg600, size: 18),
          ),
          Expanded(
            child: state.otherName != null
                ? _ParticipantCard(
                    name: state.otherName!,
                    language: state.otherLanguage ?? 'en',
                    isLocal: false,
                    volume: 0,
                    stage: state.otherPipelineStage,
                    isCapturing: false,
                  )
                : _WaitingCard(),
          ),
        ],
      ),
    );
  }
}

class _ParticipantCard extends StatelessWidget {
  final String name;
  final String language;
  final bool isLocal;
  final double volume;
  final PipelineStage stage;
  final bool isCapturing;

  const _ParticipantCard({
    required this.name,
    required this.language,
    required this.isLocal,
    required this.volume,
    required this.stage,
    required this.isCapturing,
  });

  @override
  Widget build(BuildContext context) {
    final color = isLocal ? AppColors.brand600 : const Color(0xFF7C3AED);
    final isSpeaking = isLocal
        ? (isCapturing && stage == PipelineStage.recording)
        : (stage == PipelineStage.recording);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.bg800,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.bg700),
      ),
      child: Row(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              if (isSpeaking)
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border:
                        Border.all(color: AppColors.green400, width: 1.5),
                  ),
                )
                    .animate(onPlay: (c) => c.repeat())
                    .scaleXY(
                        begin: 1.0,
                        end: 1.7,
                        duration: 700.ms,
                        curve: Curves.easeOut)
                    .fadeOut(begin: 0.6, duration: 700.ms),
              CircleAvatar(
                radius: 14,
                backgroundColor: color.withOpacity(0.2),
                child: Text(
                  name[0].toUpperCase(),
                  style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isLocal ? '${name.split(' ').first} (You)' : name.split(' ').first,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${languageFlag(language)} ${languageName(language)}',
                  style: const TextStyle(
                      fontSize: 10, color: AppColors.surface400),
                ),
              ],
            ),
          ),
          if (isLocal && isCapturing)
            const Text('●',
                    style: TextStyle(color: AppColors.green400, fontSize: 8))
                .animate(onPlay: (c) => c.repeat())
                .fadeIn(duration: 600.ms)
                .then()
                .fadeOut(duration: 600.ms),
        ],
      ),
    );
  }
}

class _WaitingCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.bg800.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.bg700),
      ),
      child: const Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: Color(0xFF2D2D3A),
            child: Icon(Icons.person_add_outlined,
                color: AppColors.bg500, size: 14),
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Waiting…',
              style: TextStyle(fontSize: 11, color: AppColors.surface400),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Control Bar ──────────────────────────────────────────────────────────────

class _ControlBar extends ConsumerWidget {
  final CallState state;
  const _ControlBar({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 40),
      decoration: const BoxDecoration(
        color: AppColors.bg900,
        border: Border(top: BorderSide(color: AppColors.bg700)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ControlButton(
            icon: state.isMuted
                ? Icons.mic_off_rounded
                : Icons.mic_rounded,
            label: state.isMuted ? 'Unmute' : 'Mute',
            active: !state.isMuted,
            activeColor: AppColors.green400,
            inactiveColor: AppColors.red500,
            onTap: () => ref.read(callProvider.notifier).toggleMute(),
          ),
          GestureDetector(
            onTap: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (_) => _EndCallDialog(),
              );
              if (confirmed == true) {
                await ref.read(callProvider.notifier).endCall();
                if (context.mounted) Navigator.of(context).pop();
              }
            },
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.red600,
                boxShadow: [
                  BoxShadow(
                      color: AppColors.red600.withOpacity(0.4),
                      blurRadius: 16)
                ],
              ),
              child: const Icon(Icons.call_end_rounded,
                  color: AppColors.white, size: 24),
            )
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .scaleXY(
                    begin: 1.0,
                    end: 1.03,
                    duration: 2000.ms,
                    curve: Curves.easeInOut),
          ),
          _PipelineIndicator(stage: state.pipelineStage),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color activeColor;
  final Color inactiveColor;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.activeColor,
    required this.inactiveColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? activeColor : inactiveColor;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(0.12),
              border: Border.all(color: color.withOpacity(0.4)),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 10, color: color)),
        ],
      ),
    );
  }
}

class _PipelineIndicator extends StatelessWidget {
  final PipelineStage stage;
  const _PipelineIndicator({required this.stage});

  Color _color() => switch (stage) {
        PipelineStage.idle => AppColors.bg600,
        PipelineStage.recording => AppColors.green400,
        PipelineStage.transcribing => AppColors.yellow400,
        PipelineStage.translating => AppColors.brand400,
        PipelineStage.synthesizing => AppColors.purple400,
        PipelineStage.playing => AppColors.cyan400,
      };

  String _label() => switch (stage) {
        PipelineStage.idle => 'Idle',
        PipelineStage.recording => 'STT',
        PipelineStage.transcribing => 'STT',
        PipelineStage.translating => 'GPT',
        PipelineStage.synthesizing => 'TTS',
        PipelineStage.playing => 'Play',
      };

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _color().withOpacity(0.12),
            border: Border.all(color: _color().withOpacity(0.4)),
          ),
          child: Icon(Icons.settings_input_component_rounded,
              color: _color(), size: 22),
        ),
        const SizedBox(height: 4),
        Text(_label(), style: TextStyle(fontSize: 10, color: _color())),
      ],
    );
  }
}

// ─── End Call Dialog ─────────────────────────────────────────────────────────

class _EndCallDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.bg800,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('End Call?',
          style: TextStyle(fontWeight: FontWeight.w700)),
      content: const Text(
        'This will disconnect you from the session.',
        style: TextStyle(color: AppColors.surface400, fontSize: 14),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel',
              style: TextStyle(color: AppColors.surface400)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.red600,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text('End Call'),
        ),
      ],
    );
  }
}
