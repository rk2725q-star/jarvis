import 'package:uuid/uuid.dart';
import '../../../core/api/api_client.dart';
import '../../../core/router/ai_router.dart';
import '../models/codesign_models.dart';

class CodesignService {
  final AIRouter _router;
  static const _uuid = Uuid();

  CodesignService({required AIRouter router})
      : _router = router;

  static const _systemPrompt = '''
You are CoDesign, a senior visual product designer and elite front-end engineer.
Your job is to generate a single, self-contained HTML page that is stunning, interactive, and completely production-ready.

CRITICAL DESIGN RULES:
1. NO SLOP: Avoid generic templates, boring dark grids with a single purple glow card, center-aligned body text, or dummy data like "Lorem Ipsum" or "John Doe". Generate realistic, rich, domain-specific text and numbers.
2. AESTHETICS & CRAFT: Match the visual bar of a senior designer. Use harmony, typographic hierarchy, rich gradients, dynamic micro-interactions, hover states, and smooth CSS transitions.
3. DEPENDENCIES: You are allowed to load Tailwind CSS from CDN (`<script src="https://cdn.tailwindcss.com"></script>`), Font Awesome or Lucide Icons (from CDN), and Google Fonts. Do NOT load other external scripts/APIs.
4. RESPONSIVENESS: Ensure layouts look stunning and are fully responsive across mobile (375px), tablet (768px), and desktop viewports. Avoid fixed widths that clip content.

EDITMODE PROTOCOL (MANDATORY):
You MUST declare a visual parameters JSON block at the very top of your script tag. This block enables users to tweak styles instantly without regenerations:
```js
const TWEAK_DEFAULTS = /*EDITMODE-BEGIN*/{
  "accentColor": "#6366f1",
  "density": 1.0,
  "darkMode": false
}/*EDITMODE-END*/;
```
Rules for EDITMODE block:
- Must be a valid JSON block inside /*EDITMODE-BEGIN*/ and /*EDITMODE-END*/.
- Supported properties: color strings (e.g. hex codes), numbers (e.g. padding/font size scale), and booleans (e.g. darkMode).
- You MUST write a script that listens to `'message'` events from the parent frame, parses incoming tweaks, and dynamically updates style variables on `:root` as `--ocd-tweak-<kebab-key>`.
- Use those CSS variables inside your stylesheet/Tailwind styles. E.g. inline style `background-color: var(--ocd-tweak-accent-color);` or define custom styles:
  `:root { --ocd-tweak-accent-color: #6366f1; }`
- Example script to include in your HTML:
```html
<script>
  const TWEAK_DEFAULTS = /*EDITMODE-BEGIN*/{
    "accentColor": "#6366f1",
    "density": 1.0,
    "darkMode": false
  }/*EDITMODE-END*/;

  function applyTweaks(tokens) {
    if (!tokens) return;
    Object.entries(tokens).forEach(([key, value]) => {
      const kebab = key.replace(/([a-z0-9])([A-Z])/g, '\$1-\$2').toLowerCase();
      document.documentElement.style.setProperty('--ocd-tweak-' + kebab, value);
      
      // Special handler for darkMode
      if (key === 'darkMode') {
        if (value) {
          document.documentElement.classList.add('dark');
        } else {
          document.documentElement.classList.remove('dark');
        }
      }
    });
  }

  // Initial apply
  applyTweaks(TWEAK_DEFAULTS);

  // Listen for parent messages
  window.addEventListener('message', (e) => {
    if (e.data && e.data.type === 'codesign:tweaks:update') {
      applyTweaks(e.data.tokens);
    }
  });
</script>
```

OUTPUT REQUIREMENT:
Return ONLY the raw HTML code. Do NOT wrap it in explanations or extra chat. Wrap the HTML inside a markdown code block ````html ... ````.
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
Create a $typeLabel for: "${request.prompt}"
${request.brandColor != null ? 'Brand color: ${request.brandColor}' : ''}
${request.font != null ? 'Font preference: ${request.font}' : ''}
${request.darkMode ? 'Use dark theme.' : 'Use light theme.'}
''';

    try {
      final response = await _router.generateDirectResponse(
        prompt: fullPrompt,
        systemOverride: _systemPrompt,
        providerOverride: AIProvider.ollamaCloud,
        modelOverride: 'minimax-m3',
      );
      final html = _extractHtml(response);

      return CodesignArtifact(
        id: _uuid.v4(),
        htmlContent: html,
        request: request,
        createdAt: DateTime.now(),
      );
    } catch (e) {
      throw ApiException('Codesign generation failed: $e');
    }
  }

  /// Edit existing artifact with follow-up instruction
  Future<CodesignArtifact> edit(
    CodesignArtifact existing,
    String editInstruction,
  ) async {
    final prompt = '''
Here is an existing HTML design:
<existing>
${existing.htmlContent}
</existing>

Apply this change: "$editInstruction"
Return the complete updated HTML only.
''';

    try {
      final response = await _router.generateDirectResponse(
        prompt: prompt,
        systemOverride: _systemPrompt,
        providerOverride: AIProvider.ollamaCloud,
        modelOverride: 'minimax-m3',
      );
      final newHtml = _extractHtml(response);

      return CodesignArtifact(
        id: existing.id,
        htmlContent: newHtml,
        request: existing.request,
        createdAt: DateTime.now(),
        history: [...existing.history, existing.htmlContent], // version history
      );
    } catch (e) {
      throw ApiException('Codesign edit failed: $e');
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
