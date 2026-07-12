// yt_audio_handler.dart
//
// YouTube Premium-style background playback:
//  ✅ Audio plays when screen locks or user presses Home
//  ✅ Audio CONTINUES even when app is cleared from Recents
//  ✅ Notification with play/pause/seek controls on lock screen
//  ✅ Media session controls from headset buttons / earphones
//  ✅ LoudnessEnhancer auto-applied to real ExoPlayer session on play
// ignore_for_file: avoid_print

import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class YTAudioHandler extends BaseAudioHandler with SeekHandler {
  final _player = AudioPlayer();
  int? _currentAudioSessionId;
  static const _audioChannel = MethodChannel('jarvis.ai.os/audio');

  YTAudioHandler() {
    // Forward player state → AudioService state
    _player.playbackEventStream.listen((e) => _broadcastState(e));
    _player.playingStream.listen((_) => _broadcastState());

    // Keep the MediaItem in sync
    _player.currentIndexStream.listen((index) {
      if (index != null && index < queue.value.length) {
        mediaItem.add(queue.value[index]);
      }
    });

    // Track the real Android audio session ID and auto-apply boost
    try {
      _player.androidAudioSessionIdStream.listen((sessionId) {
        if (sessionId != null && sessionId > 0) {
          _currentAudioSessionId = sessionId;
          _applyStoredBoost(sessionId);
        }
      });
    } catch (_) {
      // Not on Android (web/desktop)
    }
  }

  // ── Public API ───────────────────────────────────────────────────────────
  AudioPlayer get player => _player;

  /// The real ExoPlayer audio session ID — use this for LoudnessEnhancer
  int? get audioSessionId => _currentAudioSessionId;

  // ── BaseAudioHandler overrides ───────────────────────────────────────────

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop(); // releases the foreground service / notification
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() => _player.seekToNext();

  @override
  Future<void> skipToPrevious() => _player.seekToPrevious();

  /// Load a URL and start playing with MediaItem metadata shown on notification.
  Future<void> playUrl(String url, MediaItem item) async {
    mediaItem.add(item);
    queue.add([item]);
    try {
      await _player.stop();
      await _player.setAudioSource(
        AudioSource.uri(
          Uri.parse(url),
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Linux; Android 12; Pixel 6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/112.0.0.0 Mobile Safari/537.36',
            'Origin': 'https://www.youtube.com',
          },
        ),
      );
      await _player.play();
    } catch (e) {
      print('YTAudioHandler.playUrl: $e');
    }
  }

  // ── Auto-apply stored audio boost when ExoPlayer session is ready ────────
  Future<void> _applyStoredBoost(int sessionId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final boost = prefs.getDouble('yt_audio_boost') ?? 1.0;
      if (boost > 1.0) {
        final gainMb = ((boost - 1.0) / 2.0 * 1500).toInt();
        await _audioChannel.invokeMethod('setLoudnessGain', {
          'gainMb': gainMb,
          'sessionId': sessionId,
        });
      }
    } catch (_) {}
  }

  // ── Apply boost manually (called from settings) ──────────────────────────
  Future<void> applyBoost(double boostLevel) async {
    final gainMb = boostLevel > 1.0
        ? ((boostLevel - 1.0) / 2.0 * 1500).toInt()
        : 0;
    try {
      // Always pass the real session ID if we have it
      final args = <String, dynamic>{'gainMb': gainMb};
      if (_currentAudioSessionId != null && _currentAudioSessionId! > 0) {
        args['sessionId'] = _currentAudioSessionId!;
      }
      await _audioChannel.invokeMethod('setLoudnessGain', args);
    } catch (_) {}
  }

  // ── KEY: audio continues when user swipes app from Recents ───────────────
  @override
  Future<void> onTaskRemoved() async {
    // Do NOT call stop() — keeps the foreground service alive
    // Audio only stops when user explicitly presses Stop in the notification.
  }

  @override
  Future<void> onNotificationDeleted() async {
    await stop();
  }

  // ── Build playback state for notification / lock-screen controls ─────────
  void _broadcastState([PlaybackEvent? event]) {
    final e = event ?? _player.playbackEvent;
    final isPlaying = _player.playing;

    final controls = [
      MediaControl.skipToPrevious,
      isPlaying ? MediaControl.pause : MediaControl.play,
      MediaControl.skipToNext,
      MediaControl.stop,
    ];

    playbackState.add(
      PlaybackState(
        controls: controls,
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.play,
          MediaAction.pause,
          MediaAction.playPause,
          MediaAction.stop,
          MediaAction.skipToNext,
          MediaAction.skipToPrevious,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: {
          ProcessingState.idle: AudioProcessingState.idle,
          ProcessingState.loading: AudioProcessingState.loading,
          ProcessingState.buffering: AudioProcessingState.buffering,
          ProcessingState.ready: AudioProcessingState.ready,
          ProcessingState.completed: AudioProcessingState.completed,
        }[_player.processingState]!,
        playing: isPlaying,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: e.currentIndex,
      ),
    );
  }
}
