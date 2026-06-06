import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import '../../theme/jarvis_theme.dart';
import '../../widgets/message_bubble.dart';
import '../../widgets/chat_input_bar.dart';
import '../settings/settings_screen.dart';
import '../voice/voice_conversation_screen.dart';
import '../sessions/sessions_drawer.dart';
import '../diagram/diagram_trigger.dart';
import 'package:flutter/services.dart';
import '../files/jarvis_file_viewer.dart';
import '../youtube/youtube_screen.dart';


import '../integrations/integrations_model.dart';
import '../integrations/integration_browser_screen.dart';
import 'chat_provider.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final _scrollController = ScrollController();
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  int _lastMessageCount = 0;
  // Throttle scroll-during-streaming so we never flood the UI thread
  Timer? _scrollThrottle;
  bool _isScrollThrottled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChatProvider>().checkPendingNotification();
      _initReceiveSharingIntent();
      _initFileOpenChannel();
      _initShortcutChannel();
    });
  }

  StreamSubscription? _intentDataStreamSubscription;
  static const _fileOpenChannel = MethodChannel('jarvis.ai.os/file_open');
  static const _shortcutChannel = MethodChannel('jarvis.ai.os/shortcuts');

  void _initShortcutChannel() {
    _shortcutChannel.invokeMethod<String>('getInitialIntegrationId').then((id) {
      if (id != null && id.isNotEmpty && mounted) {
        // Special handling for native integrations
        if (id == 'youtube') {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const YouTubeScreen()),
          );
          return;
        }
        final integration = kAIIntegrations.firstWhere(
          (i) => i.id == id,
          orElse: () => kAIIntegrations.first,
        );
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => IntegrationBrowserScreen(integration: integration)),
        );
      }
    }).catchError((_) {});
  }

  void _initReceiveSharingIntent() {
    // Listen to media/text shared while the app is in memory
    _intentDataStreamSubscription = ReceiveSharingIntent.instance.getMediaStream().listen((List<SharedMediaFile> value) {
      _processSharedFiles(value);
    }, onError: (err) {
      debugPrint("getIntentDataStream error: $err");
    });

    // Get the media/text shared while app was closed
    ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile> value) {
      if (value.isNotEmpty) {
        _processSharedFiles(value);
      }
    });
  }

  void _processSharedFiles(List<SharedMediaFile> files) {
    if (files.isEmpty) return;
    final provider = context.read<ChatProvider>();
    for (var file in files) {
      if (file.type == SharedMediaType.text) {
        final text = file.path;
        // Check if it's a YouTube link
        final isYtLink = text.contains('youtube.com/') || text.contains('youtu.be/');
        if (isYtLink) {
          // Extract ID using basic logic since youtube_explode_dart.VideoId can do it:
          final reg = RegExp(r'(?:v=|youtu\.be/|shorts/)([^&?\s]+)');
          final match = reg.firstMatch(text);
          final String vidId = match != null ? match.group(1) ?? '' : '';
          if (vidId.isNotEmpty) {
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => YouTubeScreen(initialVideoId: vidId),
            ));
            return; // Stop processing further for youtube share
          }
        }
        provider.sendMessage(text);
      } else {
        provider.attachFile(file.path);
      }
    }
  }

  /// Handles files opened from Android "Open With" – e.g., long-press a PDF → JARVIS
  void _initFileOpenChannel() {
    // Get the initial file if the app was launched via "Open With"
    _fileOpenChannel.invokeMethod<String>('getInitialFile').then((path) {
      if (path != null && path.isNotEmpty && mounted) {
        _openFileInViewer(path);
      }
    }).catchError((_) {});

    // Listen while app is already open (onNewIntent)
    _fileOpenChannel.setMethodCallHandler((call) async {
      if (call.method == 'openFile') {
        final path = call.arguments as String?;
        if (path != null && path.isNotEmpty && mounted) {
          _openFileInViewer(path);
        }
      }
    });
  }

  void _openFileInViewer(String path) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => JarvisFileViewer(filePath: path)),
    );
  }

  @override
  void dispose() {
    _intentDataStreamSubscription?.cancel();
    _scrollThrottle?.cancel();
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

  /// Throttled scroll-during-streaming: fires at most once per 400ms.
  void _throttledScrollToBottom() {
    if (_isScrollThrottled) return;
    _isScrollThrottled = true;
    _scrollThrottle?.cancel();
    _scrollThrottle = Timer(const Duration(milliseconds: 400), () {
      _isScrollThrottled = false;
      if (_scrollController.hasClients) {
        final pos = _scrollController.position;
        if (pos.maxScrollExtent - pos.pixels < 200) {
          pos.jumpTo(pos.maxScrollExtent);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatProvider>(
      builder: (context, chatProvider, child) {
        // Auto-scroll only when new messages arrive (not on every streaming tick)
        if (chatProvider.messages.length > _lastMessageCount) {
          _lastMessageCount = chatProvider.messages.length;
          _scrollToBottom();
        } else if (chatProvider.isGenerating) {
          // Use throttled scroll — never add postFrameCallback on every build
          _throttledScrollToBottom();
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
                      : Column(
                          children: [
                            Expanded(
                              child: ListView.builder(
                                controller: _scrollController,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
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
                ),
                // Provider status bar
                _ProviderStatusBar(),

                // Pending Notification Context Pill
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
        border: Border(bottom: BorderSide(color: JarvisColors.border, width: 0.5)),
      ),
      child: Row(
        children: [
          // Drawer button
          IconButton(
            icon: const Icon(Icons.menu_rounded, color: JarvisColors.textSecondary),
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            tooltip: 'Sessions',
          ),

          // Title
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ShaderMask(
                  shaderCallback: (b) => JarvisColors.primaryGradient.createShader(b),
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
            icon: const Icon(Icons.phone_in_talk_rounded, color: JarvisColors.accentPrimary, size: 22),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const VoiceConversationScreen()),
              );
            },
            tooltip: 'Voice Conversation',
          ),




          // Settings
          IconButton(
            icon: const Icon(Icons.settings_rounded, color: JarvisColors.textSecondary, size: 22),
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
              shaderCallback: (b) => JarvisColors.primaryGradient.createShader(b),
              child: const Text(
                'Hello, I\'m JARVIS.',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
              ),
            ).animate().fadeIn(delay: 200.ms, duration: 500.ms).slideY(begin: 0.2, end: 0),
            const SizedBox(height: 8),
            const Text(
              'Your multi-provider AI assistant.',
              style: TextStyle(color: JarvisColors.textSecondary, fontSize: 15),
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
      ('🗺️', 'Show AI Roadmap 2026'),
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
          onTap: () => context.read<ChatProvider>().sendMessage(e.value.$2),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
        ).animate(delay: Duration(milliseconds: 450 + e.key * 80))
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
              label: Text(s, style: const TextStyle(fontSize: 12, color: JarvisColors.textSecondary)),
              backgroundColor: JarvisColors.surfaceElevated,
              side: const BorderSide(color: JarvisColors.border, width: 0.5),
              onPressed: () => chatProvider.sendMessage(s),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPendingNotificationPill(ChatProvider chatProvider) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.only(left: 16, right: 8, top: 8, bottom: 8),
      decoration: BoxDecoration(
        color: JarvisColors.surfaceElevated.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: JarvisColors.accentPrimary.withValues(alpha: 0.5)),
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
          const Icon(Icons.notifications_active_rounded, color: JarvisColors.accentPrimary, size: 18),
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
            icon: const Icon(Icons.close_rounded, size: 18, color: JarvisColors.textMuted),
            onPressed: () => chatProvider.cancelPendingNotification(),
            constraints: const BoxConstraints(),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.5, end: 0);
  }
}

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
                          : JarvisColors.success).withValues(alpha: 0.6),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ).animate(onPlay: (c) => router.isGenerating ? c.repeat() : null)
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
