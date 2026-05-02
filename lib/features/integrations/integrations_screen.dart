import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../theme/jarvis_theme.dart';
import 'integrations_model.dart';
import 'integrations_provider.dart';
import 'integration_browser_screen.dart';
import '../youtube/youtube_screen.dart';

class IntegrationsScreen extends StatefulWidget {
  const IntegrationsScreen({super.key});

  @override
  State<IntegrationsScreen> createState() => _IntegrationsScreenState();
}

class _IntegrationsScreenState extends State<IntegrationsScreen> {
  String _selectedCategory = 'All';
  final _searchController = TextEditingController();
  String _search = '';

  final List<String> _categories = [
    'All',
    'AI Assistant',
    'Multi-Model',
    'Design AI',
    'Search AI',
    'Google',
    'Browser',
    'Developer',
    'Productivity',
    'Enterprise',
    'Social',
    'Open Source',
  ];


  List<AIIntegration> get _filtered {
    var list = kAIIntegrations;
    if (_selectedCategory != 'All') {
      list = list.where((e) => e.category == _selectedCategory).toList();
    }
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list
          .where((e) =>
              e.name.toLowerCase().contains(q) ||
              e.description.toLowerCase().contains(q))
          .toList();
    }
    return list;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07070F),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0A0A18), Color(0xFF07070F)],
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              _buildSearch(),
              _buildCategoryChips(),
              Expanded(child: _buildGrid()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Row(
        children: [
          // Back button
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white70,
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShaderMask(
                  shaderCallback: (bounds) =>
                      JarvisColors.primaryGradient.createShader(bounds),
                  child: const Text(
                    'Integrations',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                const Text(
                  'Embed any AI platform inside JARVIS',
                  style: TextStyle(
                    color: JarvisColors.textMuted,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          // Count badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: JarvisColors.accentPrimary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: JarvisColors.accentPrimary.withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              '${kAIIntegrations.length} apps',
              style: const TextStyle(
                color: JarvisColors.accentPrimary,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.2, end: 0),
    );
  }

  Widget _buildSearch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: TextField(
          controller: _searchController,
          onChanged: (v) => setState(() => _search = v),
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: const InputDecoration(
            hintText: 'Search integrations...',
            hintStyle: TextStyle(color: Colors.white30, fontSize: 14),
            prefixIcon: Icon(
              Icons.search_rounded,
              color: Colors.white30,
              size: 20,
            ),
            border: InputBorder.none,
            contentPadding:
                EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ).animate().fadeIn(delay: 100.ms, duration: 400.ms),
    );
  }

  Widget _buildCategoryChips() {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        itemCount: _categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final cat = _categories[i];
          final selected = cat == _selectedCategory;
          return GestureDetector(
            onTap: () => setState(() => _selectedCategory = cat),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                gradient: selected ? JarvisColors.primaryGradient : null,
                color: selected ? null : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected
                      ? Colors.transparent
                      : Colors.white.withValues(alpha: 0.08),
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: JarvisColors.accentPrimary.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        )
                      ]
                    : null,
              ),
              child: Center(
                child: Text(
                  cat,
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.white38,
                    fontSize: 12,
                    fontWeight:
                        selected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ).animate().fadeIn(delay: 150.ms, duration: 400.ms);
  }

  Widget _buildGrid() {
    final items = _filtered;
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🔍', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            const Text(
              'No integrations found',
              style: TextStyle(color: Colors.white54, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        mainAxisExtent: 260,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        return _IntegrationCard(
          integration: items[index],
          index: index,
          onTap: () => _openIntegration(items[index]),
        );
      },
    );
  }

  void _openIntegration(AIIntegration integration) {
    // ── YouTube → native clone app ─────────────────────────────────────────
    if (integration.id == 'youtube') {
      Navigator.of(context).push(PageRouteBuilder(
        pageBuilder: (_, a1, a2) => const YouTubeScreen(),
        transitionsBuilder: (_, anim, a2, child) => SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
              .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 350),
      ));
      return;
    }
    // ── All others → Aria browser ─────────────────────────────────────────
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            IntegrationBrowserScreen(integration: integration),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Integration card with live connect / disconnect state
// ─────────────────────────────────────────────────────────────────────────────
class _IntegrationCard extends StatefulWidget {
  final AIIntegration integration;
  final int index;
  final VoidCallback onTap;

  const _IntegrationCard({
    required this.integration,
    required this.index,
    required this.onTap,
  });

  @override
  State<_IntegrationCard> createState() => _IntegrationCardState();
}

class _IntegrationCardState extends State<_IntegrationCard> {
  bool _pressed = false;

  Color get _primary => Color(widget.integration.gradientColors[0]);
  Color get _secondary => Color(widget.integration.gradientColors[1]);

  @override
  Widget build(BuildContext context) {
    final intProv = context.watch<IntegrationsProvider>();
    final isConnected = intProv.isConnected(widget.integration.id);

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      onLongPress: () async {
        setState(() => _pressed = false);
        if (widget.integration.url.isEmpty) return;
        final confirm = await showModalBottomSheet<bool>(
          context: context,
          backgroundColor: const Color(0xFF1E1E2A),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          builder: (ctx) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 60, height: 60,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [_primary, _secondary]),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(child: Text(widget.integration.emoji, style: const TextStyle(fontSize: 30))),
                  ),
                  const SizedBox(height: 16),
                  Text('Add ${widget.integration.name} to Homescreen?', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('Create a quick access shortcut on your device homescreen.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 14)),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: _primary, foregroundColor: Colors.white),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Add'),
                        ),
                      ),
                    ],
                  )
                ],
              ),
            ),
          ),
        );
        if (confirm == true) {
          try {
            await const MethodChannel('jarvis.ai.os/shortcuts').invokeMethod('pinShortcut', {
              'id': widget.integration.id,
              'label': widget.integration.name,
              'url': widget.integration.url,
            });
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Adding ${widget.integration.name} to homescreen...')));
          } catch (e) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to add shortcut: $e')));
          }
        }
      },
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          decoration: BoxDecoration(
            color: isConnected
                ? _primary.withValues(alpha: 0.08)
                : const Color(0xFF0F0F1C),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isConnected
                  ? _primary.withValues(alpha: 0.55)
                  : _primary.withValues(alpha: 0.2),
              width: isConnected ? 1.2 : 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: _primary.withValues(alpha: isConnected ? 0.18 : 0.08),
                blurRadius: isConnected ? 24 : 16,
                spreadRadius: isConnected ? 2 : 1,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Top gradient header ──
              Container(
                height: 80,
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      _primary.withValues(alpha: isConnected ? 0.45 : 0.3),
                      _secondary.withValues(alpha: isConnected ? 0.25 : 0.15),
                    ],
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      top: -15,
                      right: -15,
                      child: Container(
                        width: 70,
                        height: 70,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _primary.withValues(alpha: 0.1),
                        ),
                      ),
                    ),
                    Center(
                      child: Text(
                        widget.integration.emoji,
                        style: const TextStyle(fontSize: 34),
                      ),
                    ),
                    Positioned(
                      bottom: 8,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          widget.integration.category,
                          style: TextStyle(
                            color: _primary,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    // ── Connected badge ──
                    if (isConnected)
                      Positioned(
                        top: 8,
                        left: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF22C55E),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.bolt_rounded,
                                  color: Colors.white, size: 9),
                              SizedBox(width: 2),
                              Text(
                                'ACTIVE',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 8,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ).animate().fadeIn(duration: 300.ms).scale(),
                      ),
                  ],
                ),
              ),

              // ── Content body ──
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.integration.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.integration.description,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 10.5,
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Spacer(),
                      // Feature chips
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: widget.integration.features
                            .take(2)
                            .map((f) => Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _primary.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    f,
                                    style: TextStyle(
                                      color: _primary.withValues(alpha: 0.8),
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ))
                            .toList(),
                      ),
                      const SizedBox(height: 10),

                      // ── Connect / Disconnect button ──
                      GestureDetector(
                        onTap: () {
                          context
                              .read<IntegrationsProvider>()
                              .toggle(widget.integration.id);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 350),
                          curve: Curves.easeOutCubic,
                          width: double.infinity,
                          height: 32,
                          decoration: BoxDecoration(
                            gradient: isConnected
                                ? const LinearGradient(
                                    colors: [
                                      Color(0xFF16A34A),
                                      Color(0xFF22C55E),
                                    ],
                                  )
                                : LinearGradient(
                                    colors: [_primary, _secondary],
                                  ),
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: (isConnected
                                        ? const Color(0xFF22C55E)
                                        : _primary)
                                    .withValues(alpha: 0.4),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                isConnected
                                    ? Icons.check_circle_rounded
                                    : Icons.link_rounded,
                                color: Colors.white,
                                size: 13,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                isConnected ? 'Connected ✓' : 'Connect',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
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
              ),
            ],
          ),
        )
            .animate(delay: Duration(milliseconds: 200 + widget.index * 60))
            .fadeIn(duration: 350.ms)
            .slideY(begin: 0.3, end: 0),
      ),
    );
  }
}
