import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../../../core/router/ai_router.dart';
import '../models/image_models.dart';

class ImagiyaService {
  final AIRouter _router;
  static const _uuid = Uuid();

  ImagiyaService({required AIRouter router}) : _router = router;

  /// Stream-based generation — emits status updates
  Stream<GeneratedImage> generate(ImagiyaPrompt prompt) async* {
    final id = _uuid.v4();

    // Emit generating state immediately
    yield GeneratedImage(
      id: id,
      imageUrl: '',
      sourcePrompt: prompt,
      createdAt: DateTime.now(),
      status: ImageStatus.generating,
    );

    try {
      final imageUrl = await _router.generateImage(
        prompt.text,
        modelOverride: prompt.model,
      );

      yield GeneratedImage(
        id: id,
        imageUrl: imageUrl,
        sourcePrompt: prompt,
        createdAt: DateTime.now(),
        status: ImageStatus.success,
      );
    } catch (e) {
      yield GeneratedImage(
        id: id,
        imageUrl: '',
        sourcePrompt: prompt,
        createdAt: DateTime.now(),
        status: ImageStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  /// Generate multiple variations at once
  Future<List<String>> generateVariations(
    String promptText, {
    int count = 4,
    ImageResolution resolution = ImageResolution.hd,
  }) async {
    final urls = <String>[];
    for (int i = 0; i < count; i++) {
      try {
        final url = await _router.generateImage(promptText);
        urls.add(url);
      } catch (e) {
        debugPrint('[ImagiyaService] Variation gen failed: $e');
      }
    }
    return urls;
  }

  /// Available free models
  static const availableModels = ['minimax-m3', 'imagen-3.0-generate-002'];
}
