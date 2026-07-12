enum ImageResolution { standard, hd, fullhd }

enum ImageStatus { idle, generating, success, error }

class ImagiyaPrompt {
  final String text;
  final ImageResolution resolution;
  final String? negativePrompt;
  final String? seed;
  final String model; // default: 'flux'

  const ImagiyaPrompt({
    required this.text,
    this.resolution = ImageResolution.hd,
    this.negativePrompt,
    this.seed,
    this.model = 'flux',
  });

  /// Builds full Pollinations URL — NO API KEY NEEDED
  Uri toPollinationsUri() {
    final encoded = Uri.encodeComponent(text);
    final (w, h) = switch (resolution) {
      ImageResolution.standard => (512, 512),
      ImageResolution.hd => (1024, 1024),
      ImageResolution.fullhd => (1920, 1080),
    };
    final params = {
      'width': w.toString(),
      'height': h.toString(),
      'model': model,
      'nologo': 'true',
      'enhance': 'true',
      // ignore: use_null_aware_elements
      if (negativePrompt != null)
        'negative': Uri.encodeComponent(negativePrompt!),
      // ignore: use_null_aware_elements
      if (seed != null) 'seed': seed!,
    };
    final query = params.entries.map((e) => '${e.key}=${e.value}').join('&');
    return Uri.parse('https://image.pollinations.ai/prompt/$encoded?$query');
  }
}

class GeneratedImage {
  final String id;
  final String imageUrl;
  final ImagiyaPrompt sourcePrompt;
  final DateTime createdAt;
  final ImageStatus status;
  final String? localPath; // after download
  final String? errorMessage;

  const GeneratedImage({
    required this.id,
    required this.imageUrl,
    required this.sourcePrompt,
    required this.createdAt,
    this.status = ImageStatus.idle,
    this.localPath,
    this.errorMessage,
  });

  GeneratedImage copyWith({
    ImageStatus? status,
    String? localPath,
    String? errorMessage,
  }) => GeneratedImage(
    id: id,
    imageUrl: imageUrl,
    sourcePrompt: sourcePrompt,
    createdAt: createdAt,
    status: status ?? this.status,
    localPath: localPath ?? this.localPath,
    errorMessage: errorMessage ?? this.errorMessage,
  );
}
