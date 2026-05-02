import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../../theme/jarvis_theme.dart';
import '../features/chat/chat_provider.dart';
import '../features/vibecode/vibecode_screen.dart';
import '../features/integrations/integrations_screen.dart';
import '../features/integrations/integrations_provider.dart';
import '../features/integrations/integrations_model.dart';
import '../services/netless_service.dart';
import '../core/router/ai_router.dart';

class ChatInputBar extends StatefulWidget {
  final Function(String) onSubmit;
  final bool isGenerating;

  const ChatInputBar({
    super.key,
    required this.onSubmit,
    required this.isGenerating,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  bool _speechAvailable = false;
  bool _hasText = false;

  // @ mention picker state
  bool _showAtPicker = false;
  String _atQuery = '';

  // — Netless / Infinity model selector —
  String _selectedMode = 'infinity'; // 'netless' | 'infinity'

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _initSpeech();
    _controller.addListener(_onTextChanged);
    _focusNode.addListener(() => setState(() {}));

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  void _onTextChanged() {
    final text = _controller.text;
    final hasText = text.trim().isNotEmpty;
    if (hasText != _hasText) setState(() => _hasText = hasText);

    final cursor = _controller.selection.baseOffset;
    if (cursor > 0 && cursor <= text.length) {
      final before = text.substring(0, cursor);
      final atIdx = before.lastIndexOf('@');
      if (atIdx >= 0) {
        final afterAt = before.substring(atIdx + 1);
        if (!afterAt.contains(' ')) {
          setState(() {
            _showAtPicker = true;
            _atQuery = afterAt.toLowerCase();
          });
          return;
        }
      }
    }
    setState(() => _showAtPicker = false);
  }

  Future<void> _initSpeech() async {
    _speechAvailable = await _speech.initialize();
    if (mounted) setState(() {});
  }

  Future<void> _toggleListening() async {
    if (!_speechAvailable) return;
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
    } else {
      setState(() => _isListening = true);
      await _speech.listen(
        onResult: (result) {
          setState(() {
            _controller.text = result.recognizedWords;
            _controller.selection = TextSelection.fromPosition(
              TextPosition(offset: _controller.text.length),
            );
          });
          if (result.finalResult) {
            setState(() => _isListening = false);
          }
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
        localeId: 'en_US',
      );
    }
  }

  // ── Model Picker Popup (Netless / Infinity) ───────────────────────────
  void _showModelPicker(BuildContext context, ChatProvider chatProvider) {
    final RenderBox button = context.findRenderObject()! as RenderBox;
    final RenderBox overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(
          button.size.bottomRight(Offset.zero),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );

    showMenu<String>(
      context: context,
      position: position.shift(const Offset(-80, -130)),
      color: const Color(0xFF1A1A2E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: JarvisColors.accentPrimary.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      elevation: 24,
      items: [
        // ── Header label ──
        PopupMenuItem<String>(
          enabled: false,
          height: 36,
          child: Text(
            'SELECT MODE',
            style: TextStyle(
              color: JarvisColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.4,
            ),
          ),
        ),
        // ── Netless ──
        PopupMenuItem<String>(
          value: 'netless',
          height: 64,
          child: _ModelOption(
            icon: Icons.wifi_off_rounded,
            iconColor: const Color(0xFF00E676),
            title: 'Netless',
            subtitle: 'Offline · Gemma 4 E2B-it',
            isSelected: _selectedMode == 'netless',
            badge: 'OFFLINE',
            badgeColor: const Color(0xFF00E676),
          ),
        ),
        // ── Infinity ──
        PopupMenuItem<String>(
          value: 'infinity',
          height: 64,
          child: _ModelOption(
            icon: Icons.all_inclusive_rounded,
            iconColor: JarvisColors.accentPrimary,
            title: 'Infinity',
            subtitle: 'All cloud providers',
            isSelected: _selectedMode == 'infinity',
            badge: 'ONLINE',
            badgeColor: JarvisColors.accentPrimary,
          ),
        ),
      ],
    ).then((value) {
      if (value == null) return;
      if (!mounted) return;
      setState(() => _selectedMode = value);

      if (value == 'netless') {
        // Switch router to netless provider
        chatProvider.router.setLastSelectedProvider(AIProvider.netless);
        final netless = NetlessService();
        if (!netless.isLoaded && !netless.isLoading && !netless.isDownloading) {
          // Schedule dialog after current frame to avoid BuildContext async-gap lint
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _showNetlessDownloadDialog(this.context, netless);
          });
        }
      } else {
        // Switch back to auto-select (clear netless preference)
        chatProvider.router.setLastSelectedProvider(null);
      }
    });
  }

  void _showNetlessDownloadDialog(
    BuildContext context,
    NetlessService netless,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF00E676).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.wifi_off_rounded,
                color: Color(0xFF00E676),
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Download Netless',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Netless runs Google Gemma 4 E2B-it entirely on your device — no internet needed.',
              style: TextStyle(color: Color(0xFFB0B0C8), fontSize: 14),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InfoRow(icon: Icons.storage_rounded, text: 'Size: ~1.5 GB'),
                  SizedBox(height: 6),
                  _InfoRow(icon: Icons.memory_rounded, text: 'Model: Gemma 4 E2B-it'),
                  SizedBox(height: 6),
                  _InfoRow(icon: Icons.wifi_off_rounded, text: 'Works 100% offline'),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Later', style: TextStyle(color: Color(0xFF7070A0))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00E676),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              netless.downloadAndLoad();
            },
            child: const Text('Download', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showActionMenu(ChatProvider provider) {
    bool showTools = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          decoration: const BoxDecoration(
            color: JarvisColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: showTools
                ? _buildToolsView(provider, () {
                    setModalState(() => showTools = false);
                  }, setModalState)
                : _buildMainView(provider, () {
                    setModalState(() => showTools = true);
                  }),
          ),
        ),
      ),
    );
  }

  Widget _buildMainView(ChatProvider provider, VoidCallback onToolsClick) {
    return Column(
      key: const ValueKey('main'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 8, bottom: 12),
          child: Text(
            "ATTACHMENTS",
            style: TextStyle(
              color: JarvisColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
        ),
        _ActionTile(
          icon: Icons.upload_file_rounded,
          title: 'Upload Files',
          subtitle: 'PDF, Images, Docs, etc.',
          onTap: () {
            Navigator.pop(context);
            provider.pickAndAttachFiles();
          },
        ),
        const SizedBox(height: 12),
        _ActionTile(
          icon: Icons.code_rounded,
          title: 'VibeCode AI Builder',
          subtitle: 'Build apps & websites with AI',
          onTap: () {
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const VibeCodeScreen()),
            );
          },
        ),
        const SizedBox(height: 12),
        const Padding(
          padding: EdgeInsets.only(left: 8, bottom: 12, top: 12),
          child: Text(
            "FEATURES",
            style: TextStyle(
              color: JarvisColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
        ),
        _ActionTile(
          icon: Icons.settings_suggest_rounded,
          title: 'JARVIS Tools',
          subtitle: 'Manage web search & AI powers',
          onTap: onToolsClick,
        ),
        const SizedBox(height: 12),
        _ActionTile(
          icon: Icons.extension_rounded,
          title: 'Integrations',
          subtitle: 'Connect & use external AI platforms',
          onTap: () {
            Navigator.pop(context);
            Navigator.push(
              context,
              PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) =>
                    const IntegrationsScreen(),
                transitionsBuilder:
                    (context, animation, secondaryAnimation, child) {
                      return SlideTransition(
                        position:
                            Tween<Offset>(
                              begin: const Offset(0, 1),
                              end: Offset.zero,
                            ).animate(
                              CurvedAnimation(
                                parent: animation,
                                curve: Curves.easeOutCubic,
                              ),
                            ),
                        child: child,
                      );
                    },
                transitionDuration: const Duration(milliseconds: 400),
              ),
            );
          },
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildToolsView(
    ChatProvider provider,
    VoidCallback onBack,
    StateSetter setModalState,
  ) {
    return Column(
      key: const ValueKey('tools'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white,
                size: 20,
              ),
              onPressed: onBack,
            ),
            const Text(
              "TOOLS & SETTINGS",
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: JarvisColors.surfaceElevated,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: JarvisColors.border, width: 0.5),
          ),
          child: Column(
            children: [
              SwitchListTile(
                value: provider.router.zeeraEnabled,
                onChanged: (val) {
                  provider.router.setZeeraEnabled(val);
                  setModalState(() {});
                },
                secondary: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.amber,
                ),
                title: const Text(
                  "ZEERA Mode",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: const Text(
                  "Dual-Model Collaborative Intelligence",
                  style: TextStyle(color: JarvisColors.textMuted, fontSize: 11),
                ),
                activeThumbColor: Colors.amber,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
              ),
              const Divider(height: 1, color: JarvisColors.border),
              SwitchListTile(
                value: provider.webSearchEnabled,
                onChanged: (val) {
                  provider.toggleWebSearch(val);
                  setModalState(() {});
                },
                secondary: const Icon(
                  Icons.public_rounded,
                  color: JarvisColors.accentPrimary,
                ),
                title: const Text(
                  "Web Search",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: const Text(
                  "Allow JARVIS to check real-time results",
                  style: TextStyle(color: JarvisColors.textMuted, fontSize: 12),
                ),
                activeThumbColor: JarvisColors.accentPrimary,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: JarvisColors.surfaceElevated,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: JarvisColors.border, width: 0.5),
          ),
          child: Column(
            children: [
              ListTile(
                onTap: () {
                  Navigator.pop(context);
                  _controller.text = "@arena Generate an image of: ";
                  _focusNode.requestFocus();
                },
                leading: const Icon(
                  Icons.image_rounded,
                  color: Colors.purpleAccent,
                ),
                title: const Text(
                  "Image Generator",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: const Text(
                  "Powered autonomously by Arena.ai",
                  style: TextStyle(color: JarvisColors.textMuted, fontSize: 12),
                ),
              ),
              const Divider(height: 1, color: JarvisColors.border),
              ListTile(
                onTap: () {
                  Navigator.pop(context);
                  _controller.text = "@arena Generate a video of: ";
                  _focusNode.requestFocus();
                },
                leading: const Icon(
                  Icons.movie_creation_rounded,
                  color: Colors.blueAccent,
                ),
                title: const Text(
                  "Video Generator",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: const Text(
                  "Powered autonomously by Arena.ai",
                  style: TextStyle(color: JarvisColors.textMuted, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  void _send() {
    final text = _controller.text.trim();
    final provider = context.read<ChatProvider>();
    if ((text.isEmpty && provider.attachedFilePaths.isEmpty) ||
        widget.isGenerating) {
      return;
    }
    _controller.clear();
    setState(() {
      _hasText = false;
      _showAtPicker = false;
    });
    if (text.startsWith('@')) {
      _focusNode.unfocus();
    }
    widget.onSubmit(text);
  }

  void _selectAtIntegration(AIIntegration integration) {
    final text = _controller.text;
    final cursor = _controller.selection.baseOffset;
    if (cursor < 0) return;
    final before = text.substring(0, cursor);
    final atIdx = before.lastIndexOf('@');
    final after = text.substring(cursor);
    final newText = '${text.substring(0, atIdx)}@${integration.id} $after';
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: atIdx + integration.id.length + 2,
      ),
    );
    setState(() => _showAtPicker = false);
    _focusNode.requestFocus();
  }

  Widget _buildAtPicker(IntegrationsProvider intProv) {
    final connected = intProv.connectedIntegrations;
    final all = kAIIntegrations;
    final filtered =
        [...connected, ...all.where((a) => !connected.any((c) => c.id == a.id))]
            .where(
              (i) =>
                  _atQuery.isEmpty ||
                  i.id.contains(_atQuery) ||
                  i.name.toLowerCase().contains(_atQuery),
            )
            .toList();

    if (filtered.isEmpty) return const SizedBox.shrink();

    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: JarvisColors.accentPrimary.withValues(alpha: 0.25),
        ),
        boxShadow: [
          BoxShadow(
            color: JarvisColors.accentPrimary.withValues(alpha: 0.12),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(
              children: [
                const Text('⚡', style: TextStyle(fontSize: 11)),
                const SizedBox(width: 4),
                const Text(
                  '@Integrations',
                  style: TextStyle(
                    color: JarvisColors.accentPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                Text(
                  'JARVIS routes task to integration',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.25),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              itemCount: filtered.length,
              itemBuilder: (_, i) {
                final item = filtered[i];
                final isConnected = intProv.isConnected(item.id);
                final color = Color(item.gradientColors[0]);
                return GestureDetector(
                  onTap: () => _selectAtIntegration(item),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: color.withValues(alpha: 0.2),
                        width: 0.7,
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(item.emoji, style: const TextStyle(fontSize: 16)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                item.category,
                                style: TextStyle(
                                  color: color.withValues(alpha: 0.7),
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isConnected)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF22C55E,
                              ).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: const Color(
                                  0xFF22C55E,
                                ).withValues(alpha: 0.4),
                              ),
                            ),
                            child: const Text(
                              'Connected',
                              style: TextStyle(
                                color: Color(0xFF22C55E),
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _speech.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatProvider>(
      builder: (context, chatProvider, _) {
        final intProv = context.watch<IntegrationsProvider>();
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // @ mention picker overlay
            if (_showAtPicker) _buildAtPicker(intProv),

            // Analysis indicator
            if (chatProvider.isAnalyzing)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 16,
                ),
                color: JarvisColors.accentPrimary.withValues(alpha: 0.1),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(
                          JarvisColors.accentPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      chatProvider.analysisStatus,
                      style: const TextStyle(
                        color: JarvisColors.accentPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

            // Attached files preview
            if (chatProvider.attachedFilePaths.isNotEmpty)
              Container(
                height: 50,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: chatProvider.attachedFilePaths.length,
                  itemBuilder: (context, index) {
                    final path = chatProvider.attachedFilePaths[index];
                    final fileName = path.split(Platform.pathSeparator).last;
                    return Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: JarvisColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: JarvisColors.border),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.description_rounded,
                            size: 14,
                            color: JarvisColors.textMuted,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            fileName,
                            style: const TextStyle(
                              color: JarvisColors.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: () => chatProvider.unattachFile(path),
                            child: const Icon(
                              Icons.close_rounded,
                              size: 14,
                              color: JarvisColors.error,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

            // ── Main full-width input bar ───────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: JarvisColors.border, width: 0.5),
                ),
              ),
              child: SafeArea(
                top: false,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color: _focusNode.hasFocus
                        ? const Color(0xFF1A1A2E)
                        : const Color(0xFF141420),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: _focusNode.hasFocus
                          ? JarvisColors.accentPrimary.withValues(alpha: 0.6)
                          : JarvisColors.border.withValues(alpha: 0.5),
                      width: 1.2,
                    ),
                    boxShadow: _focusNode.hasFocus
                        ? [
                            BoxShadow(
                              color: JarvisColors.accentPrimary.withValues(
                                alpha: 0.12,
                              ),
                              blurRadius: 20,
                              spreadRadius: 2,
                            ),
                          ]
                        : [],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // + button inside bar — premium accent circle
                      _InBarButton(
                        onTap: () => _showActionMenu(chatProvider),
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: JarvisColors.accentPrimary.withValues(alpha: 0.13),
                            border: Border.all(
                              color: JarvisColors.accentPrimary.withValues(alpha: 0.35),
                              width: 1.2,
                            ),
                          ),
                          child: const Icon(
                            Icons.add_rounded,
                            color: JarvisColors.accentPrimary,
                            size: 18,
                          ),
                        ),
                      ),

                      // Text field - takes remaining space
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          maxLines: 8,
                          minLines: 3,
                          style: const TextStyle(
                            color: JarvisColors.textPrimary,
                            fontSize: 15,
                            height: 1.4,
                          ),
                          cursorColor: JarvisColors.accentPrimary,
                          decoration: const InputDecoration(
                            hintText: 'Ask JARVIS...',
                            hintStyle: TextStyle(
                              color: JarvisColors.textMuted,
                              fontSize: 14,
                            ),
                            border: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            filled: false,
                            fillColor: Colors.transparent,
                            contentPadding: EdgeInsets.symmetric(vertical: 14),
                            isDense: true,
                          ),
                          onSubmitted: (_) => _send(),
                        ),
                      ),

                      // ── Model picker + Mic + Send ──────────────────────────
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6, right: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [

                            // ── Model picker button (\u221e / wifi-off) ─────────────
                            if (_speechAvailable)
                              Builder(
                                builder: (btnCtx) => GestureDetector(
                                  onTap: () => _showModelPicker(btnCtx, chatProvider),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 220),
                                    width: 34,
                                    height: 34,
                                    margin: const EdgeInsets.only(right: 6),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: _selectedMode == 'netless'
                                          ? const Color(0xFF00E676).withValues(alpha: 0.15)
                                          : JarvisColors.accentPrimary.withValues(alpha: 0.13),
                                      border: Border.all(
                                        color: _selectedMode == 'netless'
                                            ? const Color(0xFF00E676).withValues(alpha: 0.5)
                                            : JarvisColors.accentPrimary.withValues(alpha: 0.35),
                                        width: 1.2,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: _selectedMode == 'netless'
                                              ? const Color(0xFF00E676).withValues(alpha: 0.18)
                                              : JarvisColors.accentPrimary.withValues(alpha: 0.10),
                                          blurRadius: 10,
                                          spreadRadius: 0,
                                        ),
                                      ],
                                    ),
                                    child: Center(
                                      child: Icon(
                                        _selectedMode == 'netless'
                                            ? Icons.wifi_off_rounded
                                            : Icons.all_inclusive_rounded,
                                        color: _selectedMode == 'netless'
                                            ? const Color(0xFF00E676)
                                            : JarvisColors.accentPrimary,
                                        size: 16,
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                            // ── Mic button ────────────────────────────────────
                            if (_speechAvailable)
                              AnimatedBuilder(
                                animation: _pulseAnimation,
                                builder: (ctx, child) => GestureDetector(
                                  onTap: _toggleListening,
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    width: 36,
                                    height: 36,
                                    margin: const EdgeInsets.only(right: 8),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: _isListening
                                          ? RadialGradient(colors: [
                                              JarvisColors.accentPrimary.withValues(alpha: 0.35),
                                              JarvisColors.accentPrimary.withValues(alpha: 0.08),
                                            ])
                                          : null,
                                      color: _isListening
                                          ? null
                                          : JarvisColors.surfaceElevated,
                                      border: Border.all(
                                        color: _isListening
                                            ? JarvisColors.accentPrimary.withValues(alpha: 0.55 * _pulseAnimation.value)
                                            : JarvisColors.border.withValues(alpha: 0.4),
                                        width: 1.2,
                                      ),
                                      boxShadow: _isListening
                                          ? [
                                              BoxShadow(
                                                color: JarvisColors.accentPrimary.withValues(
                                                  alpha: 0.30 * _pulseAnimation.value,
                                                ),
                                                blurRadius: 14,
                                                spreadRadius: 2,
                                              ),
                                            ]
                                          : [],
                                    ),
                                    child: Center(
                                      child: Icon(
                                        _isListening
                                            ? Icons.mic_rounded
                                            : Icons.mic_none_rounded,
                                        color: _isListening
                                            ? JarvisColors.accentPrimary
                                            : JarvisColors.textMuted,
                                        size: 18,
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                            // ── Send button ───────────────────────────────────
                            GestureDetector(
                              onTap: widget.isGenerating ? null : _send,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: (!widget.isGenerating && _hasText)
                                      ? const LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [
                                            Color(0xFF7B5FFF),
                                            Color(0xFF9B88FF),
                                          ],
                                        )
                                      : null,
                                  color: (!widget.isGenerating && _hasText)
                                      ? null
                                      : JarvisColors.surfaceElevated,
                                  border: Border.all(
                                    color: (!widget.isGenerating && _hasText)
                                        ? Colors.transparent
                                        : JarvisColors.border.withValues(alpha: 0.4),
                                    width: 1,
                                  ),
                                  boxShadow: (!widget.isGenerating && _hasText)
                                      ? [
                                          BoxShadow(
                                            color: const Color(0xFF7B5FFF).withValues(alpha: 0.55),
                                            blurRadius: 16,
                                            offset: const Offset(0, 4),
                                          ),
                                        ]
                                      : null,
                                ),
                                child: widget.isGenerating
                                    ? Padding(
                                        padding: const EdgeInsets.all(9),
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation(
                                            JarvisColors.accentPrimary,
                                          ),
                                        ),
                                      )
                                    : Icon(
                                        Icons.arrow_upward_rounded,
                                        color: _hasText
                                            ? Colors.white
                                            : JarvisColors.textMuted,
                                        size: 19,
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}


// ── Small button inside the input bar ────────────────────────────────────────
class _InBarButton extends StatelessWidget {
  final VoidCallback onTap;
  final Widget child;

  const _InBarButton({required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: child,
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: JarvisColors.surfaceElevated,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: JarvisColors.border, width: 0.5),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: JarvisColors.accentPrimary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: JarvisColors.accentPrimary, size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: JarvisColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: JarvisColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: JarvisColors.textMuted,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Model Option Item (for Netless/Infinity picker) ───────────────────────────
class _ModelOption extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool isSelected;
  final String badge;
  final Color badgeColor;

  const _ModelOption({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.badge,
    required this.badgeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Icon circle
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: iconColor.withValues(alpha: 0.12),
            border: Border.all(
              color: iconColor.withValues(alpha: isSelected ? 0.6 : 0.25),
              width: 1.2,
            ),
          ),
          child: Icon(icon, color: iconColor, size: 18),
        ),
        const SizedBox(width: 12),
        // Labels
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: isSelected ? Colors.white : const Color(0xFFCCCCE8),
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Color(0xFF7070A0),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        // Badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: badgeColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: badgeColor.withValues(alpha: 0.4), width: 0.8),
          ),
          child: Text(
            badge,
            style: TextStyle(
              color: badgeColor,
              fontSize: 9,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
        ),
        // Selected checkmark
        if (isSelected) ...[
          const SizedBox(width: 6),
          Icon(Icons.check_circle_rounded, color: iconColor, size: 16),
        ],
      ],
    );
  }
}

// ── Info row for download dialog ──────────────────────────────────────────────
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF7B5FFF), size: 14),
        const SizedBox(width: 8),
        Text(text, style: const TextStyle(color: Color(0xFFB0B0C8), fontSize: 13)),
      ],
    );
  }
}
