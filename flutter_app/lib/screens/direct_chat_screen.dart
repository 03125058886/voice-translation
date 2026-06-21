import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';
import '../config/app_config.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/mic_helper.dart';
import '../theme/app_theme.dart';

class DirectChatScreen extends ConsumerStatefulWidget {
  final String otherPhone;
  final String otherName;
  final String otherLanguage;
  final void Function(String phone)? onCall;

  const DirectChatScreen({
    super.key,
    required this.otherPhone,
    required this.otherName,
    required this.otherLanguage,
    this.onCall,
  });

  @override
  ConsumerState<DirectChatScreen> createState() => _DirectChatScreenState();
}

class _DirectChatScreenState extends ConsumerState<DirectChatScreen> {
  final _msgCtrl = TextEditingController();
  final _scroll = ScrollController();
  final _recorder = AudioRecorder();
  final _uuid = const Uuid();
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _sending = false;
  Timer? _pollTimer;

  // Voice recording
  bool _recording = false;
  String? _recordPath;
  int _recSecs = 0;
  Timer? _recTimer;

  String get _myPhone => ref.read(authProvider)?.phone ?? '';

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _loadMessages());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _recTimer?.cancel();
    _recorder.dispose();
    _msgCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    try {
      final msgs = await ApiService.getDirectMessages(me: _myPhone, other: widget.otherPhone);
      if (!mounted) return;
      setState(() {
        _messages = msgs;
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _msgCtrl.clear();
    try {
      final msg = await ApiService.sendDirectMessage(
        senderPhone: _myPhone,
        receiverPhone: widget.otherPhone,
        content: text,
      );
      if (mounted) {
        setState(() => _messages = [..._messages, msg]);
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
    } catch (e) {
      if (mounted) {
        _msgCtrl.text = text;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: AppColors.red500),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _startRecord() async {
    if (_recording) return;
    if (!await MicHelper.ensurePermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission required'), backgroundColor: AppColors.red500),
        );
      }
      return;
    }
    await MicHelper.prepareForRecording();
    final dir = await getTemporaryDirectory();
    _recordPath = '${dir.path}/${_uuid.v4()}.m4a';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, sampleRate: 44100, numChannels: 1),
      path: _recordPath!,
    );
    _recSecs = 0;
    _recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _recSecs++);
    });
    setState(() => _recording = true);
  }

  Future<void> _stopRecord({bool cancel = false}) async {
    if (!_recording) return;
    _recTimer?.cancel();
    final path = await _recorder.stop();
    setState(() => _recording = false);
    if (cancel || path == null) return;
    final file = File(path);
    if (!await file.exists()) return;
    final durationMs = _recSecs * 1000;
    setState(() => _sending = true);
    try {
      final msg = await ApiService.uploadDirectFile(
        senderPhone: _myPhone,
        receiverPhone: widget.otherPhone,
        file: file,
        messageType: 'voice',
        mimeType: 'audio/mp4',
        durationMs: durationMs,
      );
      if (mounted) {
        setState(() => _messages = [..._messages, msg]);
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: AppColors.red500),
        );
      }
    } finally {
      file.delete().ignore();
      if (mounted) setState(() => _sending = false);
    }
  }

  String _fmtRecTime(int s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  void _scrollToBottom() {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
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
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.brand600.withOpacity(0.2),
              child: Text(
                widget.otherName.isNotEmpty ? widget.otherName[0].toUpperCase() : '?',
                style: const TextStyle(color: AppColors.brand400, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.otherName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.white)),
                Text(widget.otherPhone, style: const TextStyle(fontSize: 11, color: AppColors.surface400)),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.call_rounded, color: Color(0xFF4ADE80), size: 22),
            onPressed: () => widget.onCall?.call(widget.otherPhone),
          ),
        ],
        titleSpacing: 0,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.bg700),
        ),
      ),
      resizeToAvoidBottomInset: true,
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.chat_bubble_outline_rounded, size: 48, color: AppColors.bg600),
                            const SizedBox(height: 12),
                            Text('No messages yet\nSay hi to ${widget.otherName}!',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: AppColors.surface400, fontSize: 14)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                        itemCount: _messages.length,
                        itemBuilder: (_, i) => _MessageBubble(
                          msg: _messages[i],
                          isMe: _messages[i]['sender_phone'] == _myPhone,
                        ),
                      ),
          ),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    if (_recording) return _buildRecordingBar();
    final hasText = _msgCtrl.text.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        color: AppColors.bg900,
        border: Border(top: BorderSide(color: AppColors.bg700)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _msgCtrl,
              style: const TextStyle(color: AppColors.white, fontSize: 14),
              maxLines: 4,
              minLines: 1,
              textInputAction: TextInputAction.send,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                hintText: 'Type a message...',
                hintStyle: const TextStyle(color: AppColors.bg500),
                filled: true,
                fillColor: AppColors.bg800,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _sending ? null : (hasText ? _send : _startRecord),
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: AppColors.brand600,
                shape: BoxShape.circle,
              ),
              child: _sending
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Icon(
                      hasText ? Icons.send_rounded : Icons.mic_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: AppColors.bg900,
        border: Border(top: BorderSide(color: AppColors.bg700)),
      ),
      child: Row(
        children: [
          const Icon(Icons.fiber_manual_record, color: Colors.red, size: 14),
          const SizedBox(width: 6),
          Text(
            _fmtRecTime(_recSecs),
            style: const TextStyle(color: AppColors.white, fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => _stopRecord(cancel: true),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.15),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.red.withOpacity(0.4)),
              ),
              child: const Icon(Icons.close_rounded, color: Colors.red, size: 20),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => _stopRecord(),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.brand600.withOpacity(0.15),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.brand600.withOpacity(0.5)),
              ),
              child: const Icon(Icons.send_rounded, color: AppColors.brand400, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatefulWidget {
  final Map<String, dynamic> msg;
  final bool isMe;

  const _MessageBubble({required this.msg, required this.isMe});

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
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
      final url = '${AppConfig.apiBaseUrl}${widget.msg['file_url']}';
      await _player.setUrl(url);
      if (mounted) setState(() { _loading = false; _playing = true; });
      await _player.play();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (mounted) setState(() => _playing = false);
  }

  String _fmtSecs(int s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final isMe = widget.isMe;
    final msg = widget.msg;
    final time = _formatTime(msg['created_at'] as String?);
    final isVoice = msg['message_type'] == 'voice';
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
              padding: EdgeInsets.symmetric(horizontal: isVoice ? 10 : 14, vertical: isVoice ? 8 : 9),
              decoration: BoxDecoration(
                color: isMe ? AppColors.brand600 : AppColors.bg800,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isMe ? 18 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 18),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  isVoice ? _voiceContent(isMe) : Text(
                    msg['content'] as String? ?? '',
                    style: const TextStyle(color: AppColors.white, fontSize: 14, height: 1.4),
                  ),
                  const SizedBox(height: 3),
                  Text(time, style: TextStyle(fontSize: 10, color: isMe ? Colors.white54 : AppColors.surface400)),
                ],
              ),
            ),
          ),
          if (isMe) ...[
            const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }

  Widget _voiceContent(bool isMe) {
    final secs = ((widget.msg['duration_ms'] as int?) ?? 0) ~/ 1000;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: _togglePlay,
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: isMe ? Colors.white.withOpacity(0.2) : AppColors.brand600.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: _loading
                ? SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: isMe ? Colors.white : AppColors.brand400,
                    ),
                  )
                : Icon(
                    _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: isMe ? Colors.white : AppColors.brand400,
                    size: 20,
                  ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _fmtSecs(secs),
          style: TextStyle(fontSize: 12, color: isMe ? Colors.white70 : AppColors.surface400),
        ),
      ],
    );
  }

  String _formatTime(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m';
    } catch (_) {
      return '';
    }
  }
}
