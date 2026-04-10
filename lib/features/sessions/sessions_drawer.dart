import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/jarvis_theme.dart';
import '../../models/session.dart';
import '../chat/chat_provider.dart';
import '../assignment/assignment_screen.dart';
import '../files/jarvis_file_hub.dart';

class SessionsDrawer extends StatelessWidget {
  const SessionsDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatProvider>(
      builder: (context, chatProvider, _) {
        return Drawer(
          backgroundColor: const Color(0xFF0E0E1A),
          width: 300,
          child: SafeArea(
            child: Column(
              children: [
                // ── Premium Header ─────────────────────────────
                _DrawerHeader(sessionCount: chatProvider.sessions.length),

                // ── Sessions list ──────────────────────────────
                Expanded(
                  child: chatProvider.sessions.isEmpty
                      ? _buildEmptySessions()
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                          itemCount: chatProvider.sessions.length,
                          itemBuilder: (ctx, i) {
                            final session = chatProvider.sessions[i];
                            final isActive = session.id == chatProvider.currentSessionId;
                            return _SessionTile(
                              session: session,
                              isActive: isActive,
                              onTap: () {
                                chatProvider.switchSession(session.id);
                                Navigator.pop(context);
                              },
                              onDelete: () => chatProvider.deleteSession(session.id),
                            );
                          },
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
          // File Hub tile
          _FeatureTile(
            icon: Icons.folder_special_rounded,
            label: 'File Hub',
            subtitle: 'Open & analyze files',
            color: JarvisColors.accentSecondary,
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const JarvisFileHub()),
              );
            },
          ),
          const SizedBox(height: 8),
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
        ],
      ),
    );
  }
}

// ── Feature Tile ─────────────────────────────────────────────────────────────
class _FeatureTile extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.06),
            border: Border.all(color: color.withValues(alpha: 0.2)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: JarvisColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: JarvisColors.textMuted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: color.withValues(alpha: 0.5), size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Session Tile ──────────────────────────────────────────────────────────────
class _SessionTile extends StatelessWidget {
  final Session session;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _SessionTile({
    required this.session,
    required this.isActive,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(session.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: JarvisColors.error.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_rounded, color: JarvisColors.error, size: 18),
      ),
      confirmDismiss: (_) async {
        return await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: JarvisColors.surfaceElevated,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Delete Chat?', style: TextStyle(color: JarvisColors.textPrimary, fontSize: 16)),
            content: const Text('This cannot be undone.', style: TextStyle(color: JarvisColors.textSecondary, fontSize: 13)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel', style: TextStyle(color: JarvisColors.textMuted)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete', style: TextStyle(color: JarvisColors.error)),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) => onDelete(),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isActive
                ? JarvisColors.accentPrimary.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isActive
                  ? JarvisColors.accentPrimary.withValues(alpha: 0.3)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.chat_bubble_outline_rounded,
                size: 15,
                color: isActive ? JarvisColors.accentPrimary : JarvisColors.textMuted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.title,
                      style: TextStyle(
                        color: isActive ? JarvisColors.textPrimary : JarvisColors.textSecondary,
                        fontSize: 13,
                        fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (session.lastMessage != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        // Strip markdown/special chars from preview
                        session.lastMessage!
                            .replaceAll(RegExp(r'\*+|#{1,6}\s|`+'), '')
                            .replaceAll(RegExp(r'\[RECENT CHAT HISTORY\].*\[CURRENT USER QUERY\]', dotAll: true), '')
                            .trim(),
                        style: const TextStyle(
                          color: JarvisColors.textMuted,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
