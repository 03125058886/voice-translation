import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
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
  Timer? _silenceWatchdog;
  bool _isRecording = false;
  bool _isStartingRecorder = false;
  bool _isMuted = false;
  bool _sessionReady = false;
  bool _resumeMicAfterPlayback = false;
  double _maxVolumeSinceStart = 0;

  AudioChunkCallback? onChunk;
  VolumeCallback? onVolume;
  VoidCallback? onSilentMic;

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
    if (_isRecording || _isStartingRecorder) return;
    if (!await hasPermission()) throw Exception('Microphone permission denied');

    // Guards the gap between this check and _isRecording flipping true below.
    // Without it, two near-simultaneous startRecording() calls (e.g. two call
    // sites both reacting to the call becoming active) can both pass the
    // _isRecording check and open a second native AudioRecord stream before
    // the first finishes initializing — on Android this silently corrupts
    // that side's capture (looks like it's recording, but produces no usable
    // audio) instead of throwing, so the failure is invisible without this.
    _isStartingRecorder = true;
    try {
      await _routeToSpeaker();
      // Give Android time to settle MODE_IN_COMMUNICATION before opening the
      // AudioRecord stream — starting it immediately after a mode switch can
      // silently capture near-silence on some devices (no error, just no audio).
      await Future.delayed(const Duration(milliseconds: 350));
      if (_isRecording) return; // a concurrent call already finished starting

      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: AppConfig.audioSampleRate,
          numChannels: AppConfig.audioChannels,
          echoCancel: true,
          noiseSuppress: true,
          autoGain: true,
        ),
      );

      _isRecording = true;
      _maxVolumeSinceStart = 0;
      _recordSub = stream.listen((chunk) {
        if (_isMuted) return;
        final bytes = Uint8List.fromList(chunk);
        onChunk?.call(bytes);
        _computeVolume(bytes);
      });

      // If the mic stays dead silent for several seconds while actively
      // recording, the hardware/OS audio routing is likely stuck — surface it
      // instead of failing silently forever.
      _silenceWatchdog?.cancel();
      _silenceWatchdog = Timer(const Duration(seconds: 6), () {
        if (_isRecording && !_isMuted && _maxVolumeSinceStart < 0.01) {
          onSilentMic?.call();
        }
      });
    } finally {
      _isStartingRecorder = false;
    }
  }

  void _computeVolume(Uint8List bytes) {
    if (bytes.length < 2) return;
    final samples = bytes.buffer.asInt16List();
    double sum = 0;
    for (final s in samples) {
      sum += (s.abs() / 32768.0);
    }
    final volume = (sum / samples.length).clamp(0.0, 1.0);
    if (volume > _maxVolumeSinceStart) _maxVolumeSinceStart = volume;
    onVolume?.call(volume);
  }

  Future<void> stopRecording() async {
    if (!_isRecording) return;
    _silenceWatchdog?.cancel();
    await _recordSub?.cancel();
    await _recorder.stop();
    _isRecording = false;
    onVolume?.call(0.0);
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
