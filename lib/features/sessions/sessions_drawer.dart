import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/jarvis_theme.dart';
import '../../models/session.dart';
import '../chat/chat_provider.dart';
import '../assignment/assignment_screen.dart';
import '../files/jarvis_file_hub.dart';
import '../agents/agentica_screen.dart';
import '../roadmap/roadmap_screen.dart';
import '../skills/skills_screen.dart';

class SessionsDrawer extends StatefulWidget {
  const SessionsDrawer({super.key});

  @override
  State<SessionsDrawer> createState() => _SessionsDrawerState();
}

class _SessionsDrawerState extends State<SessionsDrawer> {
  late final TextEditingController _searchController;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Map<String, List<Session>> _groupSessions(List<Session> sessions) {
    final Map<String, List<Session>> groups = {
      'Today': [],
      'Yesterday': [],
      'Previous 7 Days': [],
      'Older': [],
    };

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));
    final sevenDaysAgoStart = todayStart.subtract(const Duration(days: 7));

    for (final session in sessions) {
      final date = session.updatedAt;
      if (date.isAfter(todayStart)) {
        groups['Today']!.add(session);
      } else if (date.isAfter(yesterdayStart)) {
        groups['Yesterday']!.add(session);
      } else if (date.isAfter(sevenDaysAgoStart)) {
        groups['Previous 7 Days']!.add(session);
      } else {
        groups['Older']!.add(session);
      }
    }

    groups.removeWhere((key, value) => value.isEmpty);
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatProvider>(
      builder: (context, chatProvider, _) {
        final filteredSessions = chatProvider.sessions.where((s) {
          if (_searchQuery.isEmpty) return true;
          return s.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              (s.lastMessage != null && s.lastMessage!.toLowerCase().contains(_searchQuery.toLowerCase()));
        }).toList();

        final grouped = _groupSessions(filteredSessions);
        final List<Widget> listItems = [];

        grouped.forEach((groupName, groupSessions) {
          listItems.add(
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                groupName.toUpperCase(),
                style: TextStyle(
                  color: JarvisColors.textMuted.withValues(alpha: 0.8),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          );

          for (final session in groupSessions) {
            listItems.add(
              _SessionTile(
                session: session,
                isActive: session.id == chatProvider.currentSessionId,
                onTap: () {
                  chatProvider.switchSession(session.id);
                  Navigator.pop(context);
                },
                onDelete: () => chatProvider.deleteSession(session.id),
                onRename: (newTitle) => chatProvider.renameSession(session.id, newTitle),
              ),
            );
          }
        });

        return Drawer(
          backgroundColor: const Color(0xFF0E0E1A),
          width: 300,
          child: SafeArea(
            child: Column(
              children: [
                // ── Premium Header ─────────────────────────────
                _DrawerHeader(sessionCount: chatProvider.sessions.length),

                // ── Search Bar ────────────────────────────────
                _buildSearchBar(),

                // ── Sessions List ──────────────────────────────
                Expanded(
                  child: filteredSessions.isEmpty
                      ? (_searchQuery.isNotEmpty ? _buildNoSearchResults() : _buildEmptySessions())
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                          itemCount: listItems.length,
                          itemBuilder: (ctx, i) => listItems[i],
                        ),
                ),

                // ── Features Section ───────────────────────────
                _FeaturesSection(chatProvider: chatProvider),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        controller: _searchController,
        onChanged: (val) {
          setState(() {
            _searchQuery = val;
          });
        },
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Search conversations...',
          hintStyle: TextStyle(color: JarvisColors.textMuted.withValues(alpha: 0.8), fontSize: 13),
          prefixIcon: const Icon(Icons.search_rounded, color: JarvisColors.textSecondary, size: 16),
          suffixIcon: _searchQuery.isNotEmpty
              ? GestureDetector(
                  onTap: () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                    });
                  },
                  child: const Icon(Icons.close_rounded, color: JarvisColors.textSecondary, size: 16),
                )
              : null,
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.03),
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: JarvisColors.border, width: 0.5),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: JarvisColors.border.withValues(alpha: 0.5), width: 0.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: JarvisColors.accentPrimary.withValues(alpha: 0.5), width: 1),
          ),
        ),
      ),
    );
  }

  Widget _buildNoSearchResults() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 36, color: JarvisColors.textMuted.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            const Text(
              'No matches found',
              style: TextStyle(color: JarvisColors.textSecondary, fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Try adjusting your search query',
              style: TextStyle(color: JarvisColors.textMuted, fontSize: 11),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                _searchController.clear();
                setState(() {
                  _searchQuery = '';
                });
              },
              child: const Text('Clear Search', style: TextStyle(color: JarvisColors.accentPrimary, fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptySessions() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chat_bubble_outline_rounded,
              size: 40, color: JarvisColors.textMuted.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          const Text(
            'No conversations yet',
            style: TextStyle(color: JarvisColors.textMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ── Premium Gradient Header ───────────────────────────────────────────────────
class _DrawerHeader extends StatelessWidget {
  final int sessionCount;
  const _DrawerHeader({required this.sessionCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 12, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            JarvisColors.accentPrimary.withValues(alpha: 0.15),
            const Color(0xFF0E0E1A),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: const Border(
          bottom: BorderSide(color: JarvisColors.border, width: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // JARVIS icon
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: JarvisColors.primaryGradient,
              boxShadow: [
                BoxShadow(
                  color: JarvisColors.accentPrimary.withValues(alpha: 0.35),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShaderMask(
                  shaderCallback: (b) => JarvisColors.primaryGradient.createShader(b),
                  child: const Text(
                    'JARVIS',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2.5,
                    ),
                  ),
                ),
                Text(
                  '$sessionCount chats',
                  style: const TextStyle(
                    color: JarvisColors.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          // New chat button
          Consumer<ChatProvider>(
            builder: (ctx, cp, _) => IconButton(
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: JarvisColors.accentPrimary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: JarvisColors.accentPrimary.withValues(alpha: 0.3)),
                ),
                child: const Icon(Icons.add_rounded, color: JarvisColors.accentPrimary, size: 16),
              ),
              onPressed: () {
                cp.createNewSession();
                Navigator.pop(ctx);
              },
              tooltip: 'New Chat',
            ),
          ),
        ],
      ),
    );
  }
}

// ── Features Section ──────────────────────────────────────────────────────────
class _FeaturesSection extends StatelessWidget {
  final ChatProvider chatProvider;
  const _FeaturesSection({required this.chatProvider});

  void _showAllFeaturesDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Dialog(
          backgroundColor: const Color(0xFF0F0F1A).withValues(alpha: 0.85),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(
              color: JarvisColors.accentPrimary.withValues(alpha: 0.3),
              width: 1.5,
            ),
          ),
          child: Container(
            padding: const EdgeInsets.all(24),
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: JarvisColors.accentPrimary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.apps_rounded,
                        color: JarvisColors.accentPrimary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'JARVIS OS',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0,
                          ),
                        ),
                        Text(
                          'Interactive AI Capabilities',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 20),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.95,
                  children: [
                    _FeatureCard(
                      icon: Icons.folder_special_rounded,
                      label: 'File Hub',
                      description: 'Extract & analyze documents, images, and audio',
                      color: JarvisColors.accentSecondary,
                      onTap: () {
                        Navigator.pop(ctx);
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const JarvisFileHub()));
                      },
                    ),
                    _FeatureCard(
                      icon: Icons.bolt_rounded,
                      label: 'Agentica OS',
                      description: 'Autonomous multi-step Android operation plans',
                      color: Colors.amber,
                      onTap: () {
                        Navigator.pop(ctx);
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const AgenticaScreen()));
                      },
                    ),
                    _FeatureCard(
                      icon: Icons.map_rounded,
                      label: 'AI Roadmap Hub',
                      description: '10-Year Phased strategic research plan & dashboard',
                      color: JarvisColors.accentGlow,
                      onTap: () {
                        Navigator.pop(ctx);
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const RoadmapScreen()));
                      },
                    ),
                    _FeatureCard(
                      icon: Icons.psychology_rounded,
                      label: 'AI Skill Hub',
                      description: 'Inject and deploy custom reasoning skills',
                      color: Colors.cyanAccent,
                      onTap: () {
                        Navigator.pop(ctx);
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const SkillsScreen()));
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: JarvisColors.border, width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              'FEATURES',
              style: TextStyle(
                color: JarvisColors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
          ),
          // Assignment Hub tile
          _FeatureTile(
            icon: Icons.school_rounded,
            label: 'Assignment Hub',
            subtitle: 'Academic AI tools',
            color: JarvisColors.accentPrimary,
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AssignmentScreen()),
              );
            },
          ),
          const SizedBox(height: 8),
          // Explore Features (all remaining features presented separately in popup)
          _FeatureTile(
            icon: Icons.grid_view_rounded,
            label: 'Explore Features',
            subtitle: 'More Jarvis tools',
            color: const Color(0xFF4ADE80),
            onTap: () => _showAllFeaturesDialog(context),
          ),
        ],
      ),
    );
  }
}

// ── Feature Card ─────────────────────────────────────────────────────────────
class _FeatureCard extends StatefulWidget {
  final IconData icon;
  final String label;
  final String description;
  final Color color;
  final VoidCallback onTap;

  const _FeatureCard({
    required this.icon,
    required this.label,
    required this.description,
    required this.color,
    required this.onTap,
  });

  @override
  State<_FeatureCard> createState() => _FeatureCardState();
}

class _FeatureCardState extends State<_FeatureCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedScale(
        scale: _isHovered ? 1.03 : 1.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutBack,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: _isHovered ? 0.08 : 0.04),
            border: Border.all(
              color: widget.color.withValues(alpha: _isHovered ? 0.4 : 0.15),
              width: _isHovered ? 1.5 : 1.0,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: _isHovered
                ? [
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.15),
                      blurRadius: 16,
                      spreadRadius: 2,
                    )
                  ]
                : [],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: widget.color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(widget.icon, color: widget.color, size: 16),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      widget.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.description,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 9,
                        height: 1.3,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Feature Tile ─────────────────────────────────────────────────────────────
class _FeatureTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _FeatureTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  State<_FeatureTile> createState() => _FeatureTileState();
}

class _FeatureTileState extends State<_FeatureTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedScale(
        scale: _isHovered ? 1.02 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: _isHovered ? 0.12 : 0.06),
            border: Border.all(
              color: widget.color.withValues(alpha: _isHovered ? 0.4 : 0.2),
              width: _isHovered ? 1.2 : 1.0,
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: _isHovered
                ? [
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.1),
                      blurRadius: 10,
                      spreadRadius: 1,
                    )
                  ]
                : [],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: widget.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(widget.icon, color: widget.color, size: 16),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.label,
                            style: const TextStyle(
                              color: JarvisColors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            widget.subtitle,
                            style: const TextStyle(
                              color: JarvisColors.textMuted,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: widget.color.withValues(alpha: _isHovered ? 0.8 : 0.5),
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Session Tile ──────────────────────────────────────────────────────────────
class _SessionTile extends StatefulWidget {
  final Session session;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final ValueChanged<String> onRename;

  const _SessionTile({
    required this.session,
    required this.isActive,
    required this.onTap,
    required this.onDelete,
    required this.onRename,
  });

  @override
  State<_SessionTile> createState() => _SessionTileState();
}

class _SessionTileState extends State<_SessionTile> {
  bool _isHovered = false;

  String _formatSessionTime(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      final hour = dt.hour;
      final minute = dt.minute.toString().padLeft(2, '0');
      final period = hour >= 12 ? 'PM' : 'AM';
      final hour12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
      return '$hour12:$minute $period';
    } else {
      final diff = now.difference(dt).inDays;
      if (diff == 1) return 'Yesterday';
      
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${months[dt.month - 1]} ${dt.day}';
    }
  }

  void _showRenameDialog(BuildContext context) {
    final controller = TextEditingController(text: widget.session.title);
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF0F0F1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: JarvisColors.accentPrimary.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(20),
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Rename Chat',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Enter new title...',
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.03),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: JarvisColors.border, width: 0.5),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: JarvisColors.accentPrimary, width: 1),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: JarvisColors.textMuted, fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      final text = controller.text.trim();
                      if (text.isNotEmpty) {
                        widget.onRename(text);
                      }
                      Navigator.pop(ctx);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: JarvisColors.accentPrimary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    child: const Text('Rename', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDeleteDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF0F0F1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(
            color: JarvisColors.error,
            width: 0.5,
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(20),
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Delete Chat',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Are you sure you want to delete this chat session? This action cannot be undone.',
                style: TextStyle(
                  color: JarvisColors.textSecondary,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: JarvisColors.textMuted, fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      widget.onDelete();
                      Navigator.pop(ctx);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: JarvisColors.error,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    child: const Text('Delete', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(widget.session.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: JarvisColors.error.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_rounded, color: JarvisColors.error, size: 18),
      ),
      confirmDismiss: (_) async {
        bool confirm = false;
        await showDialog(
          context: context,
          builder: (ctx) => Dialog(
            backgroundColor: const Color(0xFF0F0F1A),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: JarvisColors.error, width: 0.5),
            ),
            child: Container(
              padding: const EdgeInsets.all(20),
              constraints: const BoxConstraints(maxWidth: 320),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Delete Chat',
                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Are you sure you want to delete this chat session? This action cannot be undone.',
                    style: TextStyle(color: JarvisColors.textSecondary, fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {
                          confirm = false;
                          Navigator.pop(ctx);
                        },
                        child: const Text('Cancel', style: TextStyle(color: JarvisColors.textMuted, fontSize: 13)),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () {
                          confirm = true;
                          Navigator.pop(ctx);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: JarvisColors.error,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                        child: const Text('Delete', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
        return confirm;
      },
      onDismissed: (_) => widget.onDelete(),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(vertical: 3),
            decoration: BoxDecoration(
              gradient: widget.isActive
                  ? LinearGradient(
                      colors: [
                        JarvisColors.accentPrimary.withValues(alpha: 0.15),
                        JarvisColors.accentSecondary.withValues(alpha: 0.04),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : (_isHovered
                      ? LinearGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0.04),
                            Colors.white.withValues(alpha: 0.01),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null),
              color: widget.isActive ? null : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: widget.isActive
                    ? JarvisColors.accentPrimary.withValues(alpha: 0.3)
                    : (_isHovered
                        ? Colors.white.withValues(alpha: 0.1)
                        : Colors.white.withValues(alpha: 0.03)),
              ),
              boxShadow: widget.isActive
                  ? [
                      BoxShadow(
                        color: JarvisColors.accentPrimary.withValues(alpha: 0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      )
                    ]
                  : [],
            ),
            child: Stack(
              children: [
                // Active line indicator
                if (widget.isActive)
                  Positioned(
                    left: 0,
                    top: 12,
                    bottom: 12,
                    child: Container(
                      width: 3.5,
                      decoration: BoxDecoration(
                        color: JarvisColors.accentPrimary,
                        borderRadius: BorderRadius.circular(2),
                        boxShadow: [
                          BoxShadow(
                            color: JarvisColors.accentPrimary.withValues(alpha: 0.5),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 14,
                        color: widget.isActive ? JarvisColors.accentPrimary : JarvisColors.textSecondary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.session.title,
                              style: TextStyle(
                                color: widget.isActive ? JarvisColors.textPrimary : JarvisColors.textSecondary,
                                fontSize: 13,
                                fontWeight: widget.isActive ? FontWeight.w600 : FontWeight.w400,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _formatSessionTime(widget.session.updatedAt),
                              style: TextStyle(
                                color: widget.isActive
                                    ? JarvisColors.accentPrimary.withValues(alpha: 0.8)
                                    : JarvisColors.textMuted,
                                fontSize: 9,
                                fontWeight: widget.isActive ? FontWeight.w500 : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Action options (more icon menu)
                      if (widget.isActive || _isHovered)
                        PopupMenuButton<String>(
                          icon: Icon(
                            Icons.more_horiz_rounded,
                            size: 18,
                            color: widget.isActive ? JarvisColors.accentPrimary : JarvisColors.textSecondary,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 100),
                          color: const Color(0xFF12121E),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.08),
                              width: 0.5,
                            ),
                          ),
                          onSelected: (val) {
                            if (val == 'rename') {
                              _showRenameDialog(context);
                            } else if (val == 'delete') {
                              _showDeleteDialog(context);
                            }
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: 'rename',
                              height: 36,
                              child: Row(
                                children: const [
                                  Icon(Icons.edit_rounded, size: 14, color: JarvisColors.textSecondary),
                                  SizedBox(width: 8),
                                  Text('Rename', style: TextStyle(color: Colors.white, fontSize: 13)),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              height: 36,
                              child: Row(
                                children: const [
                                  Icon(Icons.delete_outline_rounded, size: 14, color: JarvisColors.error),
                                  SizedBox(width: 8),
                                  Text('Delete', style: TextStyle(color: JarvisColors.error, fontSize: 13)),
                                ],
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
