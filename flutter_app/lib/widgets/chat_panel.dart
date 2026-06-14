import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

/// Input bar only — message list lives in the unified feed in CallScreen.
class ChatInputBar extends StatefulWidget {
  final String sessionId;
  final String participantId;
  final String participantName;

  const ChatInputBar({
    super.key,
    required this.sessionId,
    required this.participantId,
    required this.participantName,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final _textCtrl = TextEditingController();
  final _uuid = const Uuid();
  bool _sending = false;

  // Voice recording
  final _recorder = AudioRecorder();
  bool _recording = false;
  String? _recordPath;
  int _recSecs = 0;
  Timer? _recTimer;

  @override
  void initState() {
    super.initState();
    _textCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _recorder.dispose();
    _recTimer?.cancel();
    super.dispose();
  }

  // ── Text ────────────────────────────────────────────────────────────────────

  Future<void> _sendText() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    _textCtrl.clear();
    setState(() => _sending = true);
    try {
      await ApiService.sendTextMessage(
        sessionId: widget.sessionId,
        participantId: widget.participantId,
        participantName: widget.participantName,
        content: text,
      );
    } catch (_) {
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ── Voice recording (tap to start / tap send to stop) ───────────────────────

  Future<void> _startRecord() async {
    if (_recording) return;
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      _toast('Microphone permission required');
      return;
    }
    final dir = await getTemporaryDirectory();
    _recordPath = '${dir.path}/${_uuid.v4()}.m4a';
    await _recorder.start(
      const RecordConfig(
          encoder: AudioEncoder.aacLc, sampleRate: 44100, numChannels: 1),
      path: _recordPath!,
    );
    _recSecs = 0;
    _recTimer =
        Timer.periodic(const Duration(seconds: 1), (_) {
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
    setState(() => _sending = true);
    try {
      await ApiService.uploadFile(
        sessionId: widget.sessionId,
        participantId: widget.participantId,
        participantName: widget.participantName,
        file: file,
        messageType: 'voice',
        mimeType: 'audio/mp4',
        durationMs: _recSecs * 1000,
      );
    } catch (_) {
    } finally {
      file.delete().ignore();
      if (mounted) setState(() => _sending = false);
    }
  }

  // ── Image / File ─────────────────────────────────────────────────────────────

  Future<void> _pickImage() async {
    final xf = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (xf == null) return;
    await _uploadFile(File(xf.path), 'image', _mimeOf(xf.path));
  }

  Future<void> _pickFile() async {
    final res = await FilePicker.platform.pickFiles(withData: false);
    if (res == null || res.files.isEmpty || res.files.first.path == null) return;
    final f = res.files.first;
    await _uploadFile(File(f.path!), 'file', _mimeOf(f.path!));
  }

  Future<void> _uploadFile(File file, String type, String mime) async {
    setState(() => _sending = true);
    try {
      await ApiService.uploadFile(
        sessionId: widget.sessionId,
        participantId: widget.participantId,
        participantName: widget.participantName,
        file: file,
        messageType: type,
        mimeType: mime,
      );
    } catch (_) {
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _mimeOf(String path) {
    final ext = path.split('.').last.toLowerCase();
    const m = {
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'gif': 'image/gif',
      'webp': 'image/webp',
      'pdf': 'application/pdf',
      'txt': 'text/plain',
      'doc': 'application/msword',
      'docx':
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    };
    return m[ext] ?? 'application/octet-stream';
  }

  String _fmt(int s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: AppColors.bg700,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_recording) return _buildRecordingBar();
    return _buildNormalBar();
  }

  Widget _buildRecordingBar() {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 8,
        top: 10,
        bottom: MediaQuery.of(context).viewInsets.bottom + 10,
      ),
      decoration: const BoxDecoration(
        color: AppColors.bg900,
        border: Border(top: BorderSide(color: AppColors.bg700)),
      ),
      child: Row(
        children: [
          // Recording indicator + timer
          const Icon(Icons.fiber_manual_record, color: Colors.red, size: 14),
          const SizedBox(width: 6),
          Text(
            _fmt(_recSecs),
            style: const TextStyle(
                color: AppColors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.bg700,
                borderRadius: BorderRadius.circular(2),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: (_recSecs % 30) / 30.0,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Cancel
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
              child: const Icon(Icons.close_rounded,
                  color: Colors.red, size: 20),
            ),
          ),
          const SizedBox(width: 8),
          // Send
          GestureDetector(
            onTap: () => _stopRecord(),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.green400.withOpacity(0.15),
                shape: BoxShape.circle,
                border:
                    Border.all(color: AppColors.green400.withOpacity(0.5)),
              ),
              child: const Icon(Icons.send_rounded,
                  color: AppColors.green400, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNormalBar() {
    return Container(
      padding: EdgeInsets.only(
        left: 8,
        right: 6,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 8,
      ),
      decoration: const BoxDecoration(
        color: AppColors.bg900,
        border: Border(top: BorderSide(color: AppColors.bg700)),
      ),
      child: Row(
        children: [
          // Attach
          IconButton(
            icon: const Icon(Icons.attach_file_rounded,
                color: AppColors.surface400, size: 22),
            onPressed: _sending ? null : _showAttachSheet,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
          // Text field
          Expanded(
            child: TextField(
              controller: _textCtrl,
              style: const TextStyle(color: AppColors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Message…',
                hintStyle: const TextStyle(color: AppColors.bg500),
                filled: true,
                fillColor: AppColors.bg800,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
              maxLines: 4,
              minLines: 1,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendText(),
            ),
          ),
          const SizedBox(width: 6),
          // Send text OR start recording
          if (_textCtrl.text.trim().isNotEmpty)
            IconButton(
              icon: _sending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.brand400))
                  : const Icon(Icons.send_rounded,
                      color: AppColors.brand400, size: 24),
              onPressed: _sending ? null : _sendText,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            )
          else
            // Tap to start recording
            GestureDetector(
              onTap: _sending ? null : _startRecord,
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.brand600.withAlpha(38),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.mic_rounded,
                    color: AppColors.brand400, size: 22),
              ),
            ),
        ],
      ),
    );
  }

  void _showAttachSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bg900,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading:
                  const Icon(Icons.image_rounded, color: AppColors.brand400),
              title: const Text('Photo / Image'),
              onTap: () {
                Navigator.pop(context);
                _pickImage();
              },
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file_rounded,
                  color: AppColors.surface400),
              title: const Text('File / Document'),
              onTap: () {
                Navigator.pop(context);
                _pickFile();
              },
            ),
          ],
        ),
      ),
    );
  }
}

