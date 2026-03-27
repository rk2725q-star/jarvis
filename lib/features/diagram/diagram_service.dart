import '../../core/router/ai_router.dart';

class DiagramService {
  Future<String> generateDiagram(AIRouter router, String userRequest) async {
    final systemPrompt = _buildPrompt(userRequest);
    
    // We use the existing fallback system so Gemini, NVIDIA, or Ollama can draw the diagram seamlessly!
    String html = await router.generate(userRequest, systemPrompt: systemPrompt);
    
    html = html
        .replaceAll('```html', '')
        .replaceAll('```', '')
        .trim();
        
    return html;
  }

  String _buildPrompt(String userRequest) {
    return '''
You are an expert diagram generator for Android mobile screens.
The user wants: "\$userRequest"

Generate a single self-contained HTML file. Follow ALL rules below exactly.

=== MOBILE LAYOUT RULES (CRITICAL) ===
- Viewport: <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0">
- html, body width: 100vw, NO overflow-x
- All containers: max-width 100%, box-sizing: border-box
- NO fixed pixel widths wider than 360px
- Flow direction: TOP to BOTTOM (vertical, not horizontal)
- Each node: full width row, centered
- Arrows point DOWNWARD between nodes (↓)
- Font sizes: title 15px, labels 11px, descriptions 10px
- Node padding: 12px 16px
- Gap between nodes: 16px
- Everything must fit within 360px wide screen

=== DESIGN RULES ===
- Background: #0a0a0f
- Grid overlay: subtle CSS grid lines rgba(0,255,180,0.04)
- Each node has a colored left border (4px) + dark card background
- Node colors (cycle through): #00ffb4, #7c6fff, #c77dff, #ffaa44, #44ccff, #ff6b6b, #ffd93d
- Each node has: colored icon (SVG, 24x24), bold title, small description text
- Arrows: centered vertical line + arrowhead SVG, with small label beside arrow
- Animations: nodes fade+slideUp with staggered delay (0.1s per node)
- Font: use Google Fonts — import Syne for titles, Space Mono for labels
- Node card: border-radius 12px, background rgba(255,255,255,0.03), border 1px solid rgba(255,255,255,0.07)
- Glow on left border: box-shadow with the node color at 0.2 opacity

=== OUTPUT RULES ===
- Output ONLY raw HTML — no markdown, no backticks, no explanation
- All CSS and JS inline in one file
- No external JS libraries
- Google Fonts via @import only

Generate now.
''';
  }
}
