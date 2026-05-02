import 'package:uuid/uuid.dart';
import 'package:dio/dio.dart';
import '../../../core/api/api_client.dart';
import '../models/codesign_models.dart';

class CodesignService {
  final ApiClient _client;
  static const _uuid = Uuid();

  CodesignService({ApiClient? client})
      : _client = client ?? ApiClient.instance;

  static const _systemPrompt = '''
You are a world-class UI designer and front-end developer.
Generate a single, self-contained HTML file with inlined CSS and JS.
Requirements:
- Beautiful, modern design with animations
- Mobile-responsive
- No external dependencies except Google Fonts (CDN ok)
- Return ONLY the raw HTML — no markdown, no explanations
- Use CSS variables for theming
- Optimize for visual impact
''';

  Future<CodesignArtifact> generate(CodesignRequest request) async {
    final typeLabel = switch (request.type) {
      CodesignArtifactType.landingPage  => 'landing page',
      CodesignArtifactType.dashboard    => 'admin dashboard',
      CodesignArtifactType.slidesDeck   => 'presentation slides',
      CodesignArtifactType.mobileUI     => 'mobile app UI mockup',
      CodesignArtifactType.pricingPage  => 'pricing page',
    };

    final fullPrompt = '''
$_systemPrompt
Create a $typeLabel for: "${request.prompt}"
${request.brandColor != null ? 'Brand color: ${request.brandColor}' : ''}
${request.font != null ? 'Font preference: ${request.font}' : ''}
${request.darkMode ? 'Use dark theme.' : 'Use light theme.'}
''';

    final response = await _callPollinationsLlm(fullPrompt);
    final html = _extractHtml(response);

    return CodesignArtifact(
      id: _uuid.v4(),
      htmlContent: html,
      request: request,
      createdAt: DateTime.now(),
    );
  }

  /// Edit existing artifact with follow-up instruction
  Future<CodesignArtifact> edit(
    CodesignArtifact existing,
    String editInstruction,
  ) async {
    final prompt = '''
$_systemPrompt
Here is an existing HTML design:
<existing>
${existing.htmlContent}
</existing>

Apply this change: "$editInstruction"
Return the complete updated HTML only.
''';

    final response = await _callPollinationsLlm(prompt);
    final newHtml = _extractHtml(response);

    return CodesignArtifact(
      id: existing.id,
      htmlContent: newHtml,
      request: existing.request,
      createdAt: DateTime.now(),
      history: [...existing.history, existing.htmlContent], // version history
    );
  }

  Future<String> _callPollinationsLlm(String prompt) async {
    final url = 'https://text.pollinations.ai/${Uri.encodeComponent(prompt)}';
    try {
      final response = await _client.get<String>(
        url,
        responseType: ResponseType.plain,
      );
      return response.data ?? '';
    } catch (e) {
      throw ApiException('Codesign generation failed: $e');
    }
  }

  String _extractHtml(String raw) {
    // Strip markdown code fences if LLM wrapped the HTML
    final htmlRegex = RegExp(r'```html\n?([\s\S]*?)\n?```', caseSensitive: false);
    final match = htmlRegex.firstMatch(raw);
    if (match != null) return match.group(1)!.trim();
    
    // If it starts with <!DOCTYPE or <html, take as-is
    if (raw.trimLeft().startsWith('<!') || raw.trimLeft().startsWith('<html')) {
      return raw.trim();
    }
    return raw.trim();
  }
}
