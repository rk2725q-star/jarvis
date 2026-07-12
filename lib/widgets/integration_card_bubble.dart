import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../features/integrations/integrations_model.dart';
import '../features/integrations/integration_browser_screen.dart';

/// Parses and renders the special <!--JARVIS_INTEGRATION_CARD--> message format
class IntegrationCardBubble extends StatelessWidget {
  final String rawContent;
  const IntegrationCardBubble({super.key, required this.rawContent});

  static bool isIntegrationCard(String content) =>
      content.startsWith('<!--JARVIS_INTEGRATION_CARD-->');

  @override
  Widget build(BuildContext context) {
    // Parse the pipe-newline format:
    // <!--JARVIS_INTEGRATION_CARD-->
    // id
    // name
    // emoji
    // description
    // taskUrl
    // color1,color2
    final lines = rawContent
        .replaceFirst('<!--JARVIS_INTEGRATION_CARD-->', '')
        .trim()
        .split('\n');

    if (lines.length < 7) return const SizedBox.shrink();

    final id = lines[0].trim();
    final name = lines[1].trim();
    final emoji = lines[2].trim();
    final description = lines[3].trim();
    final taskUrl = lines[4].trim();
    final colorParts = lines[5].trim().split(',');
    final c1 = Color(int.tryParse(colorParts[0]) ?? 0xFF6C63FF);
    final c2 = Color(
      int.tryParse(colorParts.length > 1 ? colorParts[1] : '0') ?? 0xFF3A86FF,
    );

    // Find the full integration object (for the browser screen)
    final integration = kAIIntegrations.firstWhere(
      (i) => i.id == id,
      orElse: () => AIIntegration(
        id: id,
        name: name,
        description: description,
        url: taskUrl,
        category: 'AI',
        gradientColors: [c1.toARGB32(), c2.toARGB32()],
        emoji: emoji,
        features: [],
        keywords: [],
        searchUrlTemplate: taskUrl,
      ),
    );

    // Build the integration with the specific taskUrl pre-loaded
    final taskIntegration = AIIntegration(
      id: integration.id,
      name: integration.name,
      description: integration.description,
      url: taskUrl, // <- pre-built task URL
      category: integration.category,
      gradientColors: integration.gradientColors,
      emoji: integration.emoji,
      features: integration.features,
      keywords: integration.keywords,
      searchUrlTemplate: integration.searchUrlTemplate,
    );

    return Container(
          margin: const EdgeInsets.only(left: 0, right: 40, top: 4, bottom: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF0F0F1C),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: c1.withValues(alpha: 0.35), width: 1),
            boxShadow: [
              BoxShadow(
                color: c1.withValues(alpha: 0.12),
                blurRadius: 16,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Gradient header ──────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      c1.withValues(alpha: 0.2),
                      c2.withValues(alpha: 0.1),
                    ],
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(17),
                  ),
                ),
                child: Row(
                  children: [
                    // Live indicator
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF22C55E),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF22C55E,
                            ).withValues(alpha: 0.6),
                            blurRadius: 5,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 7),
                    ShaderMask(
                      shaderCallback: (b) =>
                          LinearGradient(colors: [c1, c2]).createShader(b),
                      child: const Text(
                        'JARVIS Agent',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.4,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'Integration Found',
                      style: TextStyle(
                        color: c1.withValues(alpha: 0.7),
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Card body ─────────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(emoji, style: const TextStyle(fontSize: 28)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                description,
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 11,
                                  height: 1.3,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // URL preview
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.07),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.link_rounded,
                            size: 12,
                            color: c1.withValues(alpha: 0.7),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              taskUrl
                                  .replaceAll('https://', '')
                                  .replaceAll('http://', ''),
                              style: const TextStyle(
                                color: Colors.white30,
                                fontSize: 10,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Open button
                    GestureDetector(
                      onTap: () => Navigator.of(context).push(
                        PageRouteBuilder(
                          pageBuilder: (_, _, _) => IntegrationBrowserScreen(
                            integration: taskIntegration,
                          ),
                          transitionsBuilder: (_, anim, _, child) =>
                              SlideTransition(
                                position:
                                    Tween<Offset>(
                                      begin: const Offset(0, 1),
                                      end: Offset.zero,
                                    ).animate(
                                      CurvedAnimation(
                                        parent: anim,
                                        curve: Curves.easeOutCubic,
                                      ),
                                    ),
                                child: child,
                              ),
                          transitionDuration: const Duration(milliseconds: 350),
                        ),
                      ),
                      child: Container(
                        width: double.infinity,
                        height: 40,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [c1, c2]),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: c1.withValues(alpha: 0.4),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(
                              Icons.open_in_new_rounded,
                              color: Colors.white,
                              size: 15,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Open in JARVIS Browser',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        )
        .animate()
        .fadeIn(duration: 400.ms)
        .slideY(begin: 0.3, end: 0, curve: Curves.easeOutCubic);
  }
}
