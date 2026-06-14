import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/session.dart';
import '../theme/app_theme.dart';

class AudioVisualizer extends StatefulWidget {
  final double volume;
  final PipelineStage stage;
  final bool isActive;

  const AudioVisualizer({
    super.key,
    required this.volume,
    required this.stage,
    required this.isActive,
  });

  @override
  State<AudioVisualizer> createState() => _AudioVisualizerState();
}

class _AudioVisualizerState extends State<AudioVisualizer>
    with TickerProviderStateMixin {
  late AnimationController _idleController;
  static const _barCount = 18;
  final _rand = Random();

  @override
  void initState() {
    super.initState();
    _idleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _idleController.dispose();
    super.dispose();
  }

  Color _stageColor(PipelineStage s) {
    return switch (s) {
      PipelineStage.idle => AppColors.bg600,
      PipelineStage.recording => AppColors.green400,
      PipelineStage.transcribing => AppColors.yellow400,
      PipelineStage.translating => AppColors.brand400,
      PipelineStage.synthesizing => AppColors.purple400,
      PipelineStage.playing => AppColors.cyan400,
    };
  }

  String _stageLabel(PipelineStage s) {
    return switch (s) {
      PipelineStage.idle => 'Ready',
      PipelineStage.recording => 'Listening...',
      PipelineStage.transcribing => 'Transcribing...',
      PipelineStage.translating => 'Translating...',
      PipelineStage.synthesizing => 'Generating voice...',
      PipelineStage.playing => 'Playing...',
    };
  }

  @override
  Widget build(BuildContext context) {
    final color = _stageColor(widget.stage);
    final isRecording = widget.isActive && widget.stage == PipelineStage.recording;

    return Column(
      children: [
        AnimatedBuilder(
          animation: _idleController,
          builder: (_, __) {
            return SizedBox(
              height: 56,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(_barCount, (i) {
                  final center = _barCount / 2;
                  final distance = (i - center).abs() / center;
                  final base = 0.12 + (1 - distance) * 0.2;

                  double height;
                  if (isRecording) {
                    height = base +
                        widget.volume * (1 - distance * 0.4) * 0.7 +
                        _idleController.value * (1 - distance) * 0.1;
                  } else if (widget.stage != PipelineStage.idle) {
                    height = base + sin(_idleController.value * pi + i * 0.4) * 0.3 + 0.1;
                  } else {
                    height = base + sin(_idleController.value * pi * 0.5 + i * 0.3) * 0.05;
                  }

                  height = height.clamp(0.05, 1.0);

                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 80),
                    width: 5,
                    height: 56 * height,
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    decoration: BoxDecoration(
                      color: widget.isActive ? color : AppColors.bg600,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.isActive ? color : AppColors.bg600,
              ),
            ).animate(onPlay: (c) => c.repeat())
              .fadeIn(duration: 600.ms)
              .then()
              .fadeOut(duration: 600.ms),
            const SizedBox(width: 6),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(
                _stageLabel(widget.stage),
                key: ValueKey(widget.stage),
                style: const TextStyle(
                  color: AppColors.surface400,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
