import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../theme/jarvis_theme.dart';
import '../../widgets/message_bubble.dart';
import '../../widgets/chat_input_bar.dart';
import '../settings/settings_screen.dart';
import '../voice/voice_conversation_screen.dart';
import '../sessions/sessions_drawer.dart';
import '../diagram/diagram_trigger.dart';
import 'chat_provider.dart';
import '../../models/message.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final _scrollController = ScrollController();
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  int _lastMessageCount = 0;
  // Track which user-message we're currently viewing (for up/down nav)
  int _currentUserMsgIdx = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChatProvider>().checkPendingNotification();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<ChatProvider>().checkPendingNotification();
    }
  }

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        if (animated) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        } else {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      }
    });
  }

  /// Get the list indices of all USER messages
  List<int> _getUserMessageIndices(List<Message> messages) {
    final indices = <int>[];
    for (int i = 0; i < messages.length; i++) {
      if (messages[i].isUser) indices.add(i);
    }
    return indices;
  }

  /// Proportional scroll to a given list item index
  void _scrollToIndex(int index, int totalItems) {
    if (!_scrollController.hasClients || totalItems <= 1) return;
    final maxExt = _scrollController.position.maxScrollExtent;
    final estimated = (index / (totalItems - 1)) * maxExt;
    _scrollController.animateTo(
      estimated,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  void _navigateUp(List<Message> messages) {
    final userIdxs = _getUserMessageIndices(messages);
    if (userIdxs.isEmpty) return;
    if (_currentUserMsgIdx <= 0) {
      _scrollController.animateTo(0,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      setState(() => _currentUserMsgIdx = 0);
      return;
    }
    setState(() => _currentUserMsgIdx--);
    _scrollToIndex(userIdxs[_currentUserMsgIdx], messages.length);
  }

  void _navigateDown(List<Message> messages) {
    final userIdxs = _getUserMessageIndices(messages);
    if (userIdxs.isEmpty) return;
    if (_currentUserMsgIdx >= userIdxs.length - 1) {
      _scrollToBottom();
      return;
    }
    setState(() => _currentUserMsgIdx++);
    _scrollToIndex(userIdxs[_currentUserMsgIdx], messages.length);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatProvider>(
      builder: (context, chatProvider, child) {
        // Auto-scroll and sync navigator on new messages
        if (chatProvider.isGenerating ||
            chatProvider.messages.length > _lastMessageCount) {
          _lastMessageCount = chatProvider.messages.length;
          final userIdxs = _getUserMessageIndices(chatProvider.messages);
          if (userIdxs.isNotEmpty &&
              _currentUserMsgIdx < userIdxs.length - 1) {
            _currentUserMsgIdx = userIdxs.length - 1;
          }
          _scrollToBottom();
        }

        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: JarvisColors.bg,
          drawer: const SessionsDrawer(),
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF0A0A0F), Color(0xFF0B0B14)],
              ),
            ),
            child: Column(
              children: [
                _buildAppBar(context, chatProvider),
                Expanded(
                  child: chatProvider.messages.isEmpty
                      ? _buildEmptyState()
                      : Stack(
                          children: [
                            Column(
                              children: [
                                Expanded(
                                  child: ListView.builder(
                                    controller: _scrollController,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16),
                                    itemCount: chatProvider.messages.length,
                                    itemBuilder: (ctx, i) {
                                      return MessageBubble(
                                        message: chatProvider.messages[i],
                                      );
                                    },
                                  ),
                                ),
                                if (chatProvider.currentSuggestions.isNotEmpty &&
                                    !chatProvider.isGenerating)
                                  _buildFollowUps(chatProvider),
                              ],
                            ),
                            // ── Floating scroll navigation arrows ──
                            _buildScrollNavigation(chatProvider),
                          ],
                        ),
                ),
                _ProviderStatusBar(),
                if (chatProvider.pendingNotificationReply != null)
                  _buildPendingNotificationPill(chatProvider),
                ChatInputBar(
                  onSubmit: (text) {
                    if (DiagramTrigger.isDiagramRequest(text)) {
                      chatProvider.sendDiagramMessage(text);
                    } else {
                      chatProvider.sendMessage(text);
                    }
                  },
                  isGenerating: chatProvider.isGenerating,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Floating up/down pill to jump between user messages
  Widget _buildScrollNavigation(ChatProvider chatProvider) {
    final messages = chatProvider.messages;
    final userIdxs = _getUserMessageIndices(messages);
    if (userIdxs.length < 2) return const SizedBox.shrink();

    final canUp = _currentUserMsgIdx > 0;
    final canDown = _currentUserMsgIdx < userIdxs.length - 1;
    final isLive = chatProvider.isGenerating && !canDown;

    return Positioned(
      right: 10,
      bottom: chatProvider.currentSuggestions.isNotEmpty &&
              !chatProvider.isGenerating
          ? 56
          : 8,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ▲ Up arrow
          _NavArrowButton(
            icon: Icons.keyboard_arrow_up_rounded,
            enabled: canUp,
            tooltip: 'Previous question',
            onTap: canUp ? () => _navigateUp(messages) : null,
          ),
          const SizedBox(height: 3),
          // Position counter pill
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: JarvisColors.surface.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: JarvisColors.border),
            ),
            child: Text(
              '${_currentUserMsgIdx + 1}/${userIdxs.length}',
              style: const TextStyle(
                fontSize: 10,
                color: JarvisColors.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 3),
          // ▼ Down arrow (pulses when live-following generation)
          _NavArrowButton(
            icon: Icons.keyboard_arrow_down_rounded,
            enabled: canDown || isLive,
            tooltip: isLive ? 'Following live...' : 'Next question',
            onTap: () => isLive
                ? _scrollToBottom()
                : _navigateDown(messages),
            pulsing: isLive,
          ),
        ],
      ).animate().fadeIn(duration: 250.ms).slideX(begin: 0.6, end: 0),
    );
  }

  Widget _buildAppBar(BuildContext context, ChatProvider chatProvider) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        left: 8,
        right: 12,
        bottom: 8,
      ),
      decoration: const BoxDecoration(
        color: Colors.transparent,
        border:
            Border(bottom: BorderSide(color: JarvisColors.border, width: 0.5)),
      ),
      child: Row(
        children: [
          // Drawer button
          IconButton(
            icon: const Icon(Icons.menu_rounded,
                color: JarvisColors.textSecondary),
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            tooltip: 'Sessions',
          ),

          // Title
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ShaderMask(
                  shaderCallback: (b) =>
                      JarvisColors.primaryGradient.createShader(b),
                  child: const Text(
                    'JARVIS',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 3,
                    ),
                  ),
                ),
                const Text(
                  'Multi-Provider AI OS',
                  style: TextStyle(
                    fontSize: 10,
                    color: JarvisColors.textMuted,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),

          // Phone Conversation
          IconButton(
            icon: const Icon(Icons.phone_in_talk_rounded,
                color: JarvisColors.accentPrimary, size: 22),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const VoiceConversationScreen()),
              );
            },
            tooltip: 'Voice Conversation',
          ),

          // Settings
          IconButton(
            icon: const Icon(Icons.settings_rounded,
                color: JarvisColors.textSecondary, size: 22),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
            tooltip: 'Settings',
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: JarvisColors.primaryGradient,
                boxShadow: [
                  BoxShadow(
                    color: JarvisColors.accentPrimary.withValues(alpha: 0.4),
                    blurRadius: 30,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                size: 36,
                color: Colors.white,
              ),
            ).animate().scale(
                  begin: const Offset(0.5, 0.5),
                  end: const Offset(1.0, 1.0),
                  duration: 600.ms,
                  curve: Curves.elasticOut,
                ),
            const SizedBox(height: 24),
            ShaderMask(
              shaderCallback: (b) =>
                  JarvisColors.primaryGradient.createShader(b),
              child: const Text(
                'Hello, I\'m JARVIS.',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
              ),
            ).animate().fadeIn(delay: 200.ms, duration: 500.ms).slideY(
                begin: 0.2, end: 0),
            const SizedBox(height: 8),
            const Text(
              'Your multi-provider AI assistant.',
              style:
                  TextStyle(color: JarvisColors.textSecondary, fontSize: 15),
            ).animate().fadeIn(delay: 350.ms, duration: 500.ms),
            const SizedBox(height: 40),
            _buildSuggestions(),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestions() {
    final suggestions = [
      ('💡', 'What can you do?'),
      ('🚀', 'Explain quantum computing'),
      ('🎨', 'Write a creative story'),
      ('📊', 'Help me plan my day'),
    ];

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.center,
      children: suggestions.asMap().entries.map((e) {
        return GestureDetector(
          onTap: () =>
              context.read<ChatProvider>().sendMessage(e.value.$2),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: JarvisColors.surfaceElevated,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: JarvisColors.border),
            ),
            child: Text(
              '${e.value.$1} ${e.value.$2}',
              style: const TextStyle(
                color: JarvisColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
        )
            .animate(delay: Duration(milliseconds: 450 + e.key * 80))
            .fadeIn(duration: 300.ms)
            .slideY(begin: 0.3, end: 0);
      }).toList(),
    );
  }

  Widget _buildFollowUps(ChatProvider chatProvider) {
    return Container(
      height: 48,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: chatProvider.currentSuggestions.length,
        itemBuilder: (context, index) {
          final s = chatProvider.currentSuggestions[index];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ActionChip(
              label: Text(s,
                  style: const TextStyle(
                      fontSize: 12, color: JarvisColors.textSecondary)),
              backgroundColor: JarvisColors.surfaceElevated,
              side:
                  const BorderSide(color: JarvisColors.border, width: 0.5),
              onPressed: () => chatProvider.sendMessage(s),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPendingNotificationPill(ChatProvider chatProvider) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding:
          const EdgeInsets.only(left: 16, right: 8, top: 8, bottom: 8),
      decoration: BoxDecoration(
        color: JarvisColors.surfaceElevated.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: JarvisColors.accentPrimary.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: JarvisColors.accentPrimary.withValues(alpha: 0.1),
            blurRadius: 10,
            spreadRadius: 1,
          )
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.notifications_active_rounded,
              color: JarvisColors.accentPrimary, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Replying to: "${chatProvider.pendingNotificationReply}"',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded,
                size: 18, color: JarvisColors.textMuted),
            onPressed: () => chatProvider.cancelPendingNotification(),
            constraints: const BoxConstraints(),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.5, end: 0);
  }
}

// ── Floating navigation arrow button ────────────────────────────────────────
class _NavArrowButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final String tooltip;
  final VoidCallback? onTap;
  final bool pulsing;

  const _NavArrowButton({
    required this.icon,
    required this.enabled,
    required this.tooltip,
    this.onTap,
    this.pulsing = false,
  });

  @override
  Widget build(BuildContext context) {
    Widget btn = GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: enabled
              ? JarvisColors.surface.withValues(alpha: 0.95)
              : JarvisColors.surface.withValues(alpha: 0.4),
          border: Border.all(
            color: enabled
                ? JarvisColors.accentPrimary.withValues(alpha: 0.6)
                : JarvisColors.border,
          ),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: JarvisColors.accentPrimary.withValues(alpha: 0.2),
                    blurRadius: 8,
                  )
                ]
              : null,
        ),
        child: Icon(
          icon,
          size: 20,
          color: enabled
              ? JarvisColors.accentPrimary
              : JarvisColors.textMuted,
        ),
      ),
    );

    if (pulsing) {
      btn = btn
          .animate(onPlay: (c) => c.repeat())
          .fadeOut(duration: 700.ms)
          .then()
          .fadeIn(duration: 700.ms);
    }

    return Tooltip(message: tooltip, child: btn);
  }
}

// ── Provider status bar widget ───────────────────────────────────────────────
class _ProviderStatusBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<ChatProvider>(
      builder: (context, chat, _) {
        final router = chat.router;
        if (!router.isGenerating && router.activeProvider == null) {
          return const SizedBox.shrink();
        }
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.transparent,
          child: Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: router.isGenerating
                      ? JarvisColors.accentPrimary
                      : JarvisColors.success,
                  boxShadow: [
                    BoxShadow(
                      color: (router.isGenerating
                              ? JarvisColors.accentPrimary
                              : JarvisColors.success)
                          .withValues(alpha: 0.6),
                      blurRadius: 8,
                    ),
                  ],
                ),
              )
                  .animate(
                      onPlay: (c) =>
                          router.isGenerating ? c.repeat() : null)
                  .fadeOut(duration: 500.ms)
                  .then()
                  .fadeIn(duration: 500.ms),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  router.statusMessage,
                  style: const TextStyle(
                    color: JarvisColors.textMuted,
                    fontSize: 11,
                    letterSpacing: 0.3,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
