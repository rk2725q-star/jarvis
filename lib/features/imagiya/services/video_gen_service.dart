import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

// ─── Models ──────────────────────────────────────────────────────────────────

class VideoScene {
  final double position; // 0.0 – 1.0 in timeline
  final String prompt;
  final int? seed;
  const VideoScene({required this.position, required this.prompt, this.seed});
}

class VideoConfig {
  final String title;
  final int durationSeconds; // e.g. 30, 60, 120
  final int secondsPerImage; // how long each frame is shown
  final int fps; // display fps for slideshow (not encoded)
  final int width;
  final int height;
  final String artStyle; // flux | turbo | flux-anime | flux-realism
  final int baseSeed;

  const VideoConfig({
    this.title = 'ARIA Video',
    this.durationSeconds = 30,
    this.secondsPerImage = 5,
    this.fps = 24,
    this.width = 1280,
    this.height = 720,
    this.artStyle = 'flux',
    this.baseSeed = 42,
  });

  int get imageCount => (durationSeconds / secondsPerImage).ceil();
}

class VideoGenProgress {
  final String stage; // 'images' | 'done' | 'error'
  final int current;
  final int total;
  final String message;
  final bool isDone;
  final bool isError;
  final String? errorMessage;

  /// List of fully-downloaded frame file paths when done.
  final List<String> framePaths;

  const VideoGenProgress({
    required this.stage,
    required this.current,
    required this.total,
    required this.message,
    this.isDone = false,
    this.isError = false,
    this.errorMessage,
    this.framePaths = const [],
  });

  double get progress => total > 0 ? (current / total).clamp(0.0, 1.0) : 0.0;
}

// ─── Default cinematic scene progression ─────────────────────────────────────

const List<VideoScene> kDefaultVideoScenes = [
  VideoScene(
    position: 0.00,
    prompt:
        'cinematic aerial shot, misty mountain valley at sunrise, golden hour, 8k, photorealistic',
  ),
  VideoScene(
    position: 0.07,
    prompt:
        'dramatic sunrise over a vast ocean, lens flare, orange and pink sky, cinematic, 8k',
  ),
  VideoScene(
    position: 0.13,
    prompt:
        'lush green forest path, morning light filtering through trees, volumetric fog, cinematic, 8k',
  ),
  VideoScene(
    position: 0.20,
    prompt:
        'ancient stone temple ruins in a jungle, vines and moss, dramatic light, cinematic, 8k',
  ),
  VideoScene(
    position: 0.27,
    prompt:
        'wide shot, golden wheat field, lone traveller, mid-morning light, cinematic, 8k',
  ),
  VideoScene(
    position: 0.33,
    prompt:
        'futuristic city skyline reflecting in a calm river, drone perspective, cinematic, 8k',
  ),
  VideoScene(
    position: 0.40,
    prompt:
        'vast desert with towering sandstone arches, midday sun, epic scale, cinematic, 8k',
  ),
  VideoScene(
    position: 0.47,
    prompt:
        'turquoise lagoon surrounded by white cliffs, tropical, aerial view, cinematic, 8k',
  ),
  VideoScene(
    position: 0.53,
    prompt:
        'thunderstorm over a flat prairie, lightning strike, dramatic clouds, cinematic, 8k',
  ),
  VideoScene(
    position: 0.60,
    prompt:
        'golden afternoon light, cobblestone streets of an old European village, warm tones, cinematic, 8k',
  ),
  VideoScene(
    position: 0.67,
    prompt:
        'volcanic eruption at dusk, glowing lava, dramatic sky, cinematic documentary, 8k',
  ),
  VideoScene(
    position: 0.73,
    prompt:
        'northern lights aurora borealis over a frozen lake, reflection in ice, cinematic, 8k',
  ),
  VideoScene(
    position: 0.80,
    prompt:
        'neon-lit rainy street at night, cyberpunk atmosphere, reflections on wet asphalt, 8k',
  ),
  VideoScene(
    position: 0.87,
    prompt:
        'starry night sky over a desert, milky way visible, long exposure style, cinematic, 8k',
  ),
  VideoScene(
    position: 0.93,
    prompt:
        'vast nebula in deep space, stars and gas clouds, ultra detailed, cinematic, 8k',
  ),
  VideoScene(
    position: 1.00,
    prompt:
        'aerial sunrise, mountain peaks emerging from clouds, golden hour, cinematic, 8k',
  ),
];

String _promptForT(double t, List<VideoScene> scenes) {
  VideoScene best = scenes.first;
  for (final s in scenes) {
    if (s.position <= t) best = s;
  }
  return best.prompt;
}

// ─── Service ──────────────────────────────────────────────────────────────────

class VideoGenService {
  static const String _baseUrl = 'https://image.pollinations.ai/prompt';
  static const int _delayMs = 700;

  /// Generates all frames and emits progress events.
  /// On [isDone], [framePaths] contains every downloaded image path.
  /// The caller (screen) is responsible for playing them as a slideshow.
  Stream<VideoGenProgress> generate(
    VideoConfig config,
    List<VideoScene> scenes,
  ) async* {
    final total = config.imageCount;

    yield VideoGenProgress(
      stage: 'images',
      current: 0,
      total: total,
      message: '🖼️ Preparing...',
    );

    final appDir = await getApplicationDocumentsDirectory();
    final runId = DateTime.now().millisecondsSinceEpoch;
    final framesDir = p.join(appDir.path, 'videogen', '$runId', 'frames');
    await Directory(framesDir).create(recursive: true);

    final framePaths = <String>[];

    for (int i = 0; i < total; i++) {
      final t = total == 1 ? 0.0 : i / (total - 1);
      final prompt = _promptForT(t, scenes);
      final seed = config.baseSeed + i;
      final filename = 'frame_${i.toString().padLeft(4, '0')}.jpg';
      final filePath = p.join(framesDir, filename);

      yield VideoGenProgress(
        stage: 'images',
        current: i + 1,
        total: total,
        message:
            '🖼️ Frame ${i + 1}/$total\n${prompt.length > 60 ? '${prompt.substring(0, 60)}…' : prompt}',
      );

      if (!File(filePath).existsSync()) {
        try {
          final bytes = await _fetchImage(
            prompt: prompt,
            seed: seed,
            config: config,
          );
          await File(filePath).writeAsBytes(bytes);
        } catch (e) {
          debugPrint('Frame $i download error: $e');
        }
      }

      if (File(filePath).existsSync()) framePaths.add(filePath);

      if (i < total - 1) {
        await Future.delayed(const Duration(milliseconds: _delayMs));
      }
    }

    if (framePaths.isEmpty) {
      yield VideoGenProgress(
        stage: 'error',
        current: 0,
        total: 1,
        message: '❌ No frames downloaded. Check internet.',
        isError: true,
        errorMessage: 'No frames.',
      );
      return;
    }

    yield VideoGenProgress(
      stage: 'done',
      current: framePaths.length,
      total: framePaths.length,
      message: '✅ ${framePaths.length} frames ready! Press ▶ to play.',
      isDone: true,
      framePaths: framePaths,
    );
  }

  Future<List<int>> _fetchImage({
    required String prompt,
    required int seed,
    required VideoConfig config,
    int retries = 3,
  }) async {
    final encoded = Uri.encodeComponent(prompt);
    final uri = Uri.parse(
      '$_baseUrl/$encoded'
      '?width=${config.width}'
      '&height=${config.height}'
      '&seed=$seed'
      '&model=${config.artStyle}'
      '&nologo=true'
      '&enhance=false',
    );
    for (int attempt = 1; attempt <= retries; attempt++) {
      try {
        final res = await http.get(uri).timeout(const Duration(seconds: 60));
        if (res.statusCode == 200) return res.bodyBytes;
      } catch (_) {}
      if (attempt < retries)
        await Future.delayed(Duration(seconds: attempt * 2));
    }
    throw Exception('Fetch failed after $retries retries.');
  }
}
