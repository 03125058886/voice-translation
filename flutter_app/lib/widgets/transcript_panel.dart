import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/session.dart';
import '../theme/app_theme.dart';

class TranscriptPanel extends StatefulWidget {
  final List<TranscriptEntry> entries;
  final String myLanguage;
  final String? otherLanguage;
  final String partialText;
  final String? otherName;

  const TranscriptPanel({
    super.key,
    required this.entries,
    required this.myLanguage,
    this.otherLanguage,
    this.partialText = '',
    this.otherName,
  });

  @override
  State<TranscriptPanel> createState() => _TranscriptPanelState();
}

class _TranscriptPanelState extends State<TranscriptPanel> {
  final _scrollController = ScrollController();

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void didUpdateWidget(TranscriptPanel old) {
    super.didUpdateWidget(old);
    if (widget.entries.length != old.entries.length ||
        widget.partialText != old.partialText) {
      _scrollToBottom();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasContent = widget.entries.isNotEmpty || widget.partialText.isNotEmpty;

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.bg700)),
          ),
          child: Row(
            children: [
              const Text('Live Transcript',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const Spacer(),
              if (widget.myLanguage.isNotEmpty)
                Text(
                  '${languageFlag(widget.myLanguage)} ${languageName(widget.myLanguage)}',
                  style: const TextStyle(fontSize: 11, color: AppColors.surface400),
                ),
              if (widget.otherLanguage != null) ...[
                const Text(' ↔ ', style: TextStyle(fontSize: 11, color: AppColors.surface400)),
                Text(
                  '${languageFlag(widget.otherLanguage!)} ${languageName(widget.otherLanguage!)}',
                  style: const TextStyle(fontSize: 11, color: AppColors.surface400),
                ),
              ],
            ],
          ),
        ),

        // Messages
        Expanded(
          child: !hasContent
              ? const _EmptyState()
              : ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(12),
                  children: [
                    ...widget.entries.map(
                      (e) => _TranscriptBubble(entry: e)
                          .animate()
                          .slideY(begin: 0.3, end: 0, duration: 250.ms, curve: Curves.easeOut)
                          .fadeIn(duration: 250.ms),
                    ),
                    if (widget.partialText.isNotEmpty && widget.otherName != null)
                      _PartialBubble(
                        text: widget.partialText,
                        name: widget.otherName!,
                      ).animate().fadeIn(duration: 150.ms),
                  ],
                ),
        ),
      ],
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('🎙', style: TextStyle(fontSize: 40)),
          SizedBox(height: 12),
          Text('Conversation transcript will appear here.',
              style: TextStyle(color: AppColors.surface400, fontSize: 13)),
          SizedBox(height: 4),
          Text('Start speaking — translations happen in real time.',
              style: TextStyle(color: AppColors.bg500, fontSize: 11)),
        ],
      ),
    );
  }
}

// ─── Partial (live) bubble ────────────────────────────────────────────────────

class _PartialBubble extends StatefulWidget {
  final String text;
  final String name;

  const _PartialBubble({required this.text, required this.name});

  @override
  State<_PartialBubble> createState() => _PartialBubbleState();
}

class _PartialBubbleState extends State<_PartialBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _cursor;

  @override
  void initState() {
    super.initState();
    _cursor = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _cursor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.name,
                    style: const TextStyle(fontSize: 11, color: AppColors.surface400)),
                const SizedBox(width: 6),
                AnimatedBuilder(
                  animation: _cursor,
                  builder: (_, __) => Opacity(
                    opacity: _cursor.value,
                    child: const Text('● live',
                        style: TextStyle(fontSize: 10, color: AppColors.green400)),
                  ),
                ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.82,
            ),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.bg700.withOpacity(0.5),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(4),
                  bottomRight: Radius.circular(16),
                ),
                border: Border.all(color: AppColors.bg600.withOpacity(0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Flexible(
                    child: Text(
                      widget.text,
                      style: const TextStyle(
                        color: AppColors.surface400,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  AnimatedBuilder(
                    animation: _cursor,
                    builder: (_, __) => Opacity(
                      opacity: _cursor.value,
                      child: Container(
                        width: 2,
                        height: 16,
                        color: AppColors.surface400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Completed transcript bubble ──────────────────────────────────────────────

class _TranscriptBubble extends StatelessWidget {
  final TranscriptEntry entry;

  const _TranscriptBubble({required this.entry});

  @override
  Widget build(BuildContext context) {
    final isLocal = entry.isLocal;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: isLocal ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${languageFlag(entry.sourceLang)} ${entry.speakerName}',
                  style: const TextStyle(fontSize: 11, color: AppColors.surface400),
                ),
                const SizedBox(width: 8),
                Text(
                  '${entry.timestamp.hour.toString().padLeft(2, '0')}:'
                  '${entry.timestamp.minute.toString().padLeft(2, '0')}:'
                  '${entry.timestamp.second.toString().padLeft(2, '0')}',
                  style: const TextStyle(fontSize: 10, color: AppColors.bg500),
                ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.82,
            ),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isLocal ? const Color(0x264C6EF5) : AppColors.bg700,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isLocal ? 16 : 4),
                  bottomRight: Radius.circular(isLocal ? 4 : 16),
                ),
                border: Border.all(
                  color: isLocal ? const Color(0x404C6EF5) : AppColors.bg600,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.originalText,
                      style: const TextStyle(color: AppColors.white, fontSize: 14, height: 1.5)),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Divider(height: 1, color: AppColors.bg600),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(languageFlag(entry.targetLang),
                          style: const TextStyle(fontSize: 14)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          entry.translatedText,
                          style: const TextStyle(
                            color: AppColors.brand300,
                            fontSize: 14,
                            height: 1.5,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
