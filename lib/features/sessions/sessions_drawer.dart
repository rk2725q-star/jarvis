import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/jarvis_theme.dart';
import '../../models/session.dart';
import '../chat/chat_provider.dart';
import '../assignment/assignment_screen.dart';

class SessionsDrawer extends StatelessWidget {
  const SessionsDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatProvider>(
      builder: (context, chatProvider, _) {
        return Drawer(
          backgroundColor: JarvisColors.surface,
          width: 300,
          child: SafeArea(
            child: Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: JarvisColors.border, width: 0.5)),
                  ),
                  child: Row(
                    children: [
                      ShaderMask(
                        shaderCallback: (b) => JarvisColors.primaryGradient.createShader(b),
                        child: const Icon(Icons.forum_rounded, color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Conversations',
                        style: TextStyle(
                          color: JarvisColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.add_rounded, color: JarvisColors.textSecondary),
                        onPressed: () {
                          chatProvider.createNewSession();
                          Navigator.pop(context);
                        },
                        tooltip: 'New Chat',
                      ),
                    ],
                  ),
                ),
                // Sessions list
                Expanded(
                  child: chatProvider.sessions.isEmpty
                      ? const Center(
                          child: Text(
                            'No conversations yet',
                            style: TextStyle(color: JarvisColors.textMuted),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 8),
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

                // Features
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'FEATURES',
                        style: TextStyle(
                          color: JarvisColors.textMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _FeatureTile(
                        icon: Icons.school_rounded,
                        label: 'Assignment Hub',
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
                ),
                const Divider(color: JarvisColors.border, height: 1),

                // Footer
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: JarvisColors.border, width: 0.5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.memory_rounded, color: JarvisColors.textMuted, size: 14),
                      const SizedBox(width: 8),
                      Text(
                        '${chatProvider.sessions.length} conversations',
                        style: const TextStyle(
                          color: JarvisColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FeatureTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _FeatureTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: JarvisColors.border.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                color: JarvisColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            const Icon(Icons.chevron_right_rounded, color: JarvisColors.textMuted, size: 16),
          ],
        ),
      ),
    );
  }
}

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
        color: JarvisColors.error.withValues(alpha: 0.2),
        child: const Icon(Icons.delete_rounded, color: JarvisColors.error),
      ),
      confirmDismiss: (_) async {
        return await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: JarvisColors.surfaceElevated,
            title: const Text('Delete Conversation', style: TextStyle(color: JarvisColors.textPrimary)),
            content: const Text('This cannot be undone.', style: TextStyle(color: JarvisColors.textSecondary)),
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
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isActive
                ? JarvisColors.accentPrimary.withValues(alpha: 0.15)
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
                size: 16,
                color: isActive ? JarvisColors.accentPrimary : JarvisColors.textMuted,
              ),
              const SizedBox(width: 12),
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
                        session.lastMessage!,
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
