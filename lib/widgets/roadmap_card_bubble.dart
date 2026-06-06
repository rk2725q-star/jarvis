import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/jarvis_theme.dart';
import '../features/roadmap/roadmap_screen.dart';

/// Renders the special <!--JARVIS_ROADMAP_CARD--> message format as a dashboard launcher card
class RoadmapCardBubble extends StatelessWidget {
  final String rawContent;
  const RoadmapCardBubble({super.key, required this.rawContent});

  static bool isRoadmapCard(String content) =>
      content.startsWith('<!--JARVIS_ROADMAP_CARD-->');

  @override
  Widget build(BuildContext context) {
    const accentCol = JarvisColors.accentGlow;
    const secondaryCol = JarvisColors.accentSecondary;

    return Container(
      margin: const EdgeInsets.only(left: 16, right: 16, top: 4, bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F1D),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accentCol.withValues(alpha: 0.35), width: 1.0),
        boxShadow: [
          BoxShadow(
            color: accentCol.withValues(alpha: 0.12),
            blurRadius: 16,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [accentCol.withValues(alpha: 0.2), secondaryCol.withValues(alpha: 0.1)],
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(17)),
            ),
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF00D4FF),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00D4FF).withValues(alpha: 0.6),
                        blurRadius: 5,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 7),
                ShaderMask(
                  shaderCallback: (b) =>
                      const LinearGradient(colors: [accentCol, secondaryCol]).createShader(b),
                  child: const Text(
                    'JARVIS STRATEGY',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.4,
                    ),
                  ),
                ),
                const Spacer(),
                const Text(
                  'Roadmap Active',
                  style: TextStyle(
                    color: secondaryCol,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          // Body
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('📅', style: TextStyle(fontSize: 28)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'Strategic AI Roadmap',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'A 10-year phased research plan (Years 1-12) covering causal models, Theory of Mind, provable safety boundaries, and collaborative deferral.',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                              height: 1.3,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Timeline summary tags
                Row(
                  children: [
                    _buildPill('Timeline: Years 1 - 12 (10-Year Plan)', accentCol),
                    const SizedBox(width: 8),
                    _buildPill('9 Active Simulators', secondaryCol),
                  ],
                ),

                const SizedBox(height: 16),

                // Button to open
                GestureDetector(
                  onTap: () {
                    Navigator.of(context).push(
                      PageRouteBuilder(
                        pageBuilder: (_, _, _) => const RoadmapScreen(),
                        transitionsBuilder: (_, anim, _, child) =>
                            SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 1),
                            end: Offset.zero,
                          ).animate(CurvedAnimation(
                            parent: anim,
                            curve: Curves.easeOutCubic,
                          )),
                          child: child,
                        ),
                        transitionDuration: const Duration(milliseconds: 350),
                      ),
                    );
                  },
                  child: Container(
                    width: double.infinity,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [accentCol, secondaryCol]),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: accentCol.withValues(alpha: 0.4),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.map_rounded, color: Colors.white, size: 15),
                        SizedBox(width: 8),
                        Text(
                          'Launch Interactive Roadmap Hub',
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

  Widget _buildPill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold),
      ),
    );
  }
}
