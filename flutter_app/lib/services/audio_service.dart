import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';
import '../config/app_config.dart';

typedef AudioChunkCallback = void Function(Uint8List pcmBytes);
typedef VolumeCallback = void Function(double volume);

class _QueuedAudio {
  final String base64Audio;
  final String format;

  const _QueuedAudio(this.base64Audio, this.format);
}

class AudioService {
  static const _speakerChannel = MethodChannel('com.example.voice_translation/audio');

  final _recorder = AudioRecorder();
  final _player = AudioPlayer();
  final _uuid = const Uuid();
  final _playbackQueue = <_QueuedAudio>[];
  bool _isPlayingQueue = false;

  StreamSubscription<Uint8List>? _recordSub;
  StreamSubscription<PlayerState>? _playSub;
  bool _isRecording = false;
  bool _isMuted = false;
  bool _sessionReady = false;
  bool _resumeMicAfterPlayback = false;

  AudioChunkCallback? onChunk;
  VolumeCallback? onVolume;
  VoidCallback? onRecordingStopped;
  VoidCallback? onRecordingResumed;

  Future<void> initialize() async {
    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
      avAudioSessionCategoryOptions:
          AVAudioSessionCategoryOptions.allowBluetooth |
          AVAudioSessionCategoryOptions.defaultToSpeaker |
          AVAudioSessionCategoryOptions.mixWithOthers,
      avAudioSessionMode: AVAudioSessionMode.voiceChat,
      androidAudioAttributes: AndroidAudioAttributes(
        contentType: AndroidAudioContentType.speech,
        flags: AndroidAudioFlags.audibilityEnforced,
        usage: AndroidAudioUsage.voiceCommunication,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      androidWillPauseWhenDucked: false,
    ));
    await session.setActive(true);
    await _routeToSpeaker();
    _sessionReady = true;
  }

  Future<bool> hasPermission() async {
    final mic = await Permission.microphone.request();
    if (mic.isGranted) return true;
    return _recorder.hasPermission();
  }

  Future<void> startRecording() async {
    if (_isRecording) return;
    if (!await hasPermission()) throw Exception('Microphone permission denied');

    await _routeToSpeaker();

    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: AppConfig.audioSampleRate,
        numChannels: AppConfig.audioChannels,
        // Hardware AEC can silence the mic while translated TTS plays on speaker.
        echoCancel: false,
        noiseSuppress: true,
        autoGain: true,
      ),
    );

    _isRecording = true;
    _recordSub = stream.listen((chunk) {
      if (_isMuted) return;
      final bytes = Uint8List.fromList(chunk);
      onChunk?.call(bytes);
      _computeVolume(bytes);
    });
    onRecordingResumed?.call();
  }

  void _computeVolume(Uint8List bytes) {
    if (bytes.length < 2) return;
    final samples = bytes.buffer.asInt16List();
    double sum = 0;
    for (final s in samples) {
      sum += (s.abs() / 32768.0);
    }
    onVolume?.call((sum / samples.length).clamp(0.0, 1.0));
  }

  Future<void> stopRecording() async {
    if (!_isRecording) return;
    await _recordSub?.cancel();
    await _recorder.stop();
    _isRecording = false;
    onVolume?.call(0.0);
    onRecordingStopped?.call();
  }

  void mute() => _isMuted = true;
  void unmute() => _isMuted = false;

  Future<void> _routeToSpeaker() async {
    try {
      await _speakerChannel.invokeMethod('setSpeakerphoneOn', {'on': true});
    } catch (e) {
      debugPrint('[AudioService] speaker route failed: $e');
    }
  }

  Future<void> playAudioBase64(String base64Audio, {String format = 'mp3'}) async {
    if (base64Audio.isEmpty) return;
    _playbackQueue.add(_QueuedAudio(base64Audio, format));
    if (!_isPlayingQueue) {
      unawaited(_drainPlaybackQueue());
    }
  }

  Future<void> _drainPlaybackQueue() async {
    if (_isPlayingQueue) return;
    _isPlayingQueue = true;
    try {
      while (_playbackQueue.isNotEmpty) {
        final item = _playbackQueue.removeAt(0);
        await _playOne(item.base64Audio, format: item.format);
      }
    } finally {
      _isPlayingQueue = false;
      if (_playbackQueue.isNotEmpty) {
        unawaited(_drainPlaybackQueue());
      }
    }
  }

  Future<void> _playOne(String base64Audio, {String format = 'mp3'}) async {
    final wasRecording = _isRecording;
    try {
      if (!_sessionReady) await initialize();

      if (wasRecording) {
        _resumeMicAfterPlayback = true;
        await stopRecording();
      }

      final session = await AudioSession.instance;
      await session.setActive(true);
      await _routeToSpeaker();

      await _playSub?.cancel();
      if (_player.playing) await _player.stop();

      final bytes = base64Decode(base64Audio);
      if (bytes.isEmpty) return;

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${_uuid.v4()}.$format');
      await file.writeAsBytes(bytes, flush: true);
      await _player.setFilePath(file.path);
      _playSub = _player.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          file.delete().ignore();
        }
      });

      await _player.setVolume(1.0);
      await _player.play();
      await _player.processingStateStream
          .firstWhere((s) => s == ProcessingState.completed || s == ProcessingState.idle)
          .timeout(const Duration(seconds: 30), onTimeout: () => ProcessingState.completed);
      debugPrint('[AudioService] played translated audio ($format, ${bytes.length} bytes)');
    } catch (e, st) {
      debugPrint('[AudioService] playback failed: $e\n$st');
    } finally {
      if (_resumeMicAfterPlayback) {
        _resumeMicAfterPlayback = false;
        if (onChunk != null) {
          try {
            await startRecording();
          } catch (e) {
            debugPrint('[AudioService] mic resume after playback failed: $e');
          }
        }
      }
    }
  }

  bool get isRecording => _isRecording;
  bool get isMuted => _isMuted;

  Future<void> dispose() async {
    _playbackQueue.clear();
    _isPlayingQueue = false;
    await stopRecording();
    await _playSub?.cancel();
    await _player.dispose();
    await _recorder.dispose();
    _sessionReady = false;
  }
}
