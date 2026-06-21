import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';
import '../config/app_config.dart';

typedef AudioChunkCallback = void Function(Uint8List pcmBytes);
typedef VolumeCallback = void Function(double volume);

class AudioService {
  static const _speakerChannel = MethodChannel('com.example.voice_translation/audio');

  /// Clears Android call audio mode so mic/file recording works again after a call.
  static Future<void> resetAndroidAudioMode() async {
    if (!Platform.isAndroid) return;
    try {
      await _speakerChannel.invokeMethod('resetAudioMode');
    } catch (_) {}
  }

  final _recorder = AudioRecorder();
  final _player = AudioPlayer();
  final _uuid = const Uuid();

  StreamSubscription<Uint8List>? _recordSub;
  StreamSubscription<PlayerState>? _playSub;
  bool _isRecording = false;
  bool _isMuted = false;

  AudioChunkCallback? onChunk;
  VolumeCallback? onVolume;

  Future<void> initialize() async {
    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
      avAudioSessionCategoryOptions:
          AVAudioSessionCategoryOptions.allowBluetooth |
          AVAudioSessionCategoryOptions.defaultToSpeaker,
      avAudioSessionMode: AVAudioSessionMode.voiceChat,
      androidAudioAttributes: AndroidAudioAttributes(
        contentType: AndroidAudioContentType.speech,
        flags: AndroidAudioFlags.none,
        usage: AndroidAudioUsage.voiceCommunication,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      androidWillPauseWhenDucked: false,
    ));
  }

  Future<bool> hasPermission() async => _recorder.hasPermission();

  Future<void> startRecording() async {
    if (_isRecording) return;
    if (!await hasPermission()) throw Exception('Microphone permission denied');

    await resetAndroidAudioMode();

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
    _recordSub = stream.listen((chunk) {
      if (_isMuted) return;
      final bytes = Uint8List.fromList(chunk);
      onChunk?.call(bytes);
      _computeVolume(bytes);
    });
    debugPrint('[AudioService] recording started');
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
    await resetAndroidAudioMode();
  }

  void mute() => _isMuted = true;
  void unmute() => _isMuted = false;

  Future<void> playAudioBase64(String base64Audio, {String format = 'mp3'}) async {
    if (base64Audio.isEmpty) return;
    try {
      final bytes = base64Decode(base64Audio);
      if (bytes.isEmpty) return;

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${_uuid.v4()}.$format');
      await file.writeAsBytes(bytes, flush: true);

      await _playSub?.cancel();
      if (_player.playing) await _player.stop();
      await _player.setFilePath(file.path);
      _playSub = _player.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          file.delete().ignore();
        }
      });
      await _player.setVolume(1.0);
      await _player.play();
    } catch (e) {
      debugPrint('[AudioService] playback failed: $e');
    }
  }

  bool get isRecording => _isRecording;
  bool get isMuted => _isMuted;

  Future<void> dispose() async {
    await stopRecording();
    await _playSub?.cancel();
    await _player.dispose();
    await _recorder.dispose();
  }
}
