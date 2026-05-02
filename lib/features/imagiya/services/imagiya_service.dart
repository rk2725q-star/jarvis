import 'dart:async';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import '../../../core/api/api_client.dart';
import '../models/image_models.dart';

class ImagiyaService {
  final ApiClient _client;
  static const _uuid = Uuid();

  ImagiyaService({ApiClient? client})
      : _client = client ?? ApiClient.instance;

  /// Stream-based generation — emits status updates
  Stream<GeneratedImage> generate(ImagiyaPrompt prompt) async* {
    final id = _uuid.v4();
    final url = prompt.toPollinationsUri().toString();

    // Emit generating state immediately
    yield GeneratedImage(
      id: id,
      imageUrl: url,
      sourcePrompt: prompt,
      createdAt: DateTime.now(),
      status: ImageStatus.generating,
    );

    try {
      // Pollinations: just hitting the URL triggers generation
      // First request may take 3-8s for cold start
      final cancelToken = CancelToken();
      final bytes = await _client.fetchImageBytes(url, cancelToken: cancelToken);

      if (bytes.isEmpty) throw ApiException('Empty image returned from Imagiya');

      yield GeneratedImage(
        id: id,
        imageUrl: url,
        sourcePrompt: prompt,
        createdAt: DateTime.now(),
        status: ImageStatus.success,
      );
    } on ApiException catch (e) {
      yield GeneratedImage(
        id: id,
        imageUrl: url,
        sourcePrompt: prompt,
        createdAt: DateTime.now(),
        status: ImageStatus.error,
        errorMessage: e.isCancelled ? 'Cancelled' : e.message,
      );
    }
  }

  /// Generate multiple variations at once
  Future<List<String>> generateVariations(
    String promptText, {
    int count = 4,
    ImageResolution resolution = ImageResolution.hd,
  }) async {
    return List.generate(count, (i) {
      final prompt = ImagiyaPrompt(
        text: promptText,
        resolution: resolution,
        seed: (DateTime.now().millisecondsSinceEpoch + i).toString(),
      );
      return prompt.toPollinationsUri().toString();
    });
  }

  /// Available free models on Pollinations
  static const availableModels = [
    'flux',          // Best quality (default)
    'flux-realism',  // Photorealistic
    'flux-anime',    // Anime style
    'flux-3d',       // 3D render style
    'turbo',         // Fastest generation
  ];
}
