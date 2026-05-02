enum CodesignArtifactType { landingPage, dashboard, slidesDeck, mobileUI, pricingPage }

class CodesignRequest {
  final String prompt;
  final CodesignArtifactType type;
  final String? brandColor;
  final String? font;
  final bool darkMode;

  const CodesignRequest({
    required this.prompt,
    this.type = CodesignArtifactType.landingPage,
    this.brandColor,
    this.font,
    this.darkMode = false,
  });
}

class CodesignArtifact {
  final String id;
  final String htmlContent;
  final CodesignRequest request;
  final DateTime createdAt;
  final List<String> history; // previous versions

  const CodesignArtifact({
    required this.id,
    required this.htmlContent,
    required this.request,
    required this.createdAt,
    this.history = const [],
  });
}
