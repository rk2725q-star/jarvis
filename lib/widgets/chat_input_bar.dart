import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../../theme/jarvis_theme.dart';
import '../features/chat/chat_provider.dart';
import '../features/vibecode/vibecode_screen.dart';
import '../features/agents/agentica_screen.dart';
import '../features/skills/skills_screen.dart';
import '../services/skill_service.dart';
import '../models/jarvis_skill.dart';

import '../features/integrations/integrations_screen.dart';
import '../features/integrations/integrations_provider.dart';
import '../features/integrations/integrations_model.dart';
import '../features/imagiya/screens/imagiya_screen.dart';

enum ChatInputMode { chat, imagiya, codesign }

// Value type for the input bar's Selector. We rebuild the input bar only
// when one of these changes — NOT on every streaming notify. The actual
// streaming text only flows through the MessageBubble subtree.
class _ChatInputBarStateSlice {
  final bool isAnalyzing;
  final String analysisStatus;
  final int attachedFileCount;

  const _ChatInputBarStateSlice({
    required this.isAnalyzing,
    required this.analysisStatus,
    required this.attachedFileCount,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! _ChatInputBarStateSlice) return false;
    return isAnalyzing == other.isAnalyzing &&
        analysisStatus == other.analysisStatus &&
        attachedFileCount == other.attachedFileCount;
  }

  @override
  int get hashCode => Object.hash(
        isAnalyzing,
        analysisStatus,
        attachedFileCount,
      );
}

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

  // / skill picker state
  bool _showSlashPicker = false;
  String _slashQuery = '';

  // — Infinity model selector —
  // (Netless / offline Gemma 4 2B removed)

  // — Input Mode —
  ChatInputMode _inputMode = ChatInputMode.chat;
  String _imagiyaQuality = 'hd';
  String _imagiyaStyle = 'realistic';
  String _codesignType = 'landing';

  bool get _isCreativeMode =>
      _inputMode == ChatInputMode.imagiya ||
      _inputMode == ChatInputMode.codesign;

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

      // ── @ mention picker ──
      final atIdx = before.lastIndexOf('@');
      if (atIdx >= 0) {
        final afterAt = before.substring(atIdx + 1);
        if (!afterAt.contains(' ')) {
          setState(() {
            _showAtPicker = true;
            _showSlashPicker = false;
            _atQuery = afterAt.toLowerCase();
          });
          return;
        }
      }

      // ── / skill picker ──
      final slashIdx = before.lastIndexOf('/');
      if (slashIdx == 0) {
        final afterSlash = before.substring(slashIdx + 1);
        if (!afterSlash.contains(' ')) {
          setState(() {
            _showSlashPicker = true;
            _showAtPicker = false;
            _slashQuery = afterSlash.toLowerCase();
          });
          return;
        }
      }
    }
    setState(() {
      _showAtPicker = false;
      _showSlashPicker = false;
    });
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

  // ── Model Picker Popup removed — Netless / offline Gemma 4 2B dropped ──

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

  void _showAddMcpDialog(ChatProvider provider) {
    final mcpUrlController = TextEditingController();
    final mcpTokenController = TextEditingController();
    bool isLoading = false;
    String? error;
    bool showCustom = false;
    String? selectedPreset;

    final presets = <String, Map<String, dynamic>>{
      'Pixelcut': {
        'url': 'https://mcp.pixelcut.ai/mcp',
        'icon': Icons.image_rounded,
        'auth': false,
      },
      'Vercel': {
        'url': 'https://mcp.vercel.com/',
        'icon': Icons.cloud_rounded,
        'auth': true,
      },
      'Canva': {
        'url': 'https://mcp.canva.com/mcp',
        'icon': Icons.brush_rounded,
        'auth': true,
      },
      'Copilot': {
        'url': 'https://api.githubcopilot.com/mcp/x/all',
        'icon': Icons.code_rounded,
        'auth': true,
      },
    };

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF15151F),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 40,
                  offset: const Offset(0, 20),
                ),
              ],
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: JarvisColors.accentPrimary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.electrical_services_rounded,
                          color: JarvisColors.accentPrimary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Connect MCP Server',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Padding(
                    padding: EdgeInsets.only(left: 52),
                    child: Text(
                      'Choose a tool provider',
                      style: TextStyle(color: Color(0xFF8888A0), fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Provider grid — card style, not chips
                  ...presets.entries.map((entry) {
                    final name = entry.key;
                    final data = entry.value;
                    final isSelected = selectedPreset == name && !showCustom;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => setDialogState(() {
                          selectedPreset = name;
                          showCustom = false;
                          error = null;
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? JarvisColors.accentPrimary.withValues(alpha: 0.12)
                                : Colors.white.withValues(alpha: 0.03),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected
                                  ? JarvisColors.accentPrimary
                                  : Colors.white.withValues(alpha: 0.06),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                data['icon'] as IconData,
                                color: isSelected
                                    ? JarvisColors.accentPrimary
                                    : Colors.white70,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  name,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: (data['auth'] as bool)
                                      ? Colors.orangeAccent.withValues(alpha: 0.12)
                                      : Colors.greenAccent.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  (data['auth'] as bool)
                                      ? 'Sign-in'
                                      : 'No login',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: (data['auth'] as bool)
                                        ? Colors.orangeAccent
                                        : Colors.greenAccent,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),

                  // Custom option
                  InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => setDialogState(() {
                      showCustom = true;
                      selectedPreset = null;
                      error = null;
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: showCustom
                            ? JarvisColors.accentPrimary.withValues(alpha: 0.12)
                            : Colors.white.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: showCustom
                              ? JarvisColors.accentPrimary
                              : Colors.white.withValues(alpha: 0.06),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.add_link_rounded,
                            color: showCustom
                                ? JarvisColors.accentPrimary
                                : Colors.white70,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'Custom URL',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  if (showCustom) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: mcpUrlController,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        labelText: 'MCP Server URL',
                        labelStyle: const TextStyle(
                          color: Color(0xFF8888A0),
                          fontSize: 13,
                        ),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.04),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: JarvisColors.accentPrimary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: mcpTokenController,
                      obscureText: true,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        labelText: 'Auth Token (optional)',
                        labelStyle: const TextStyle(
                          color: Color(0xFF8888A0),
                          fontSize: 13,
                        ),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.04),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: JarvisColors.accentPrimary,
                          ),
                        ),
                      ),
                    ),
                  ],

                  if (error != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.redAccent.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            color: Colors.redAccent,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              error!,
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: isLoading
                              ? null
                              : () => Navigator.pop(ctx),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(
                              color: Color(0xFF8888A0),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: JarvisColors.accentPrimary,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 0,
                          ),
                          onPressed:
                              (isLoading ||
                                  (!showCustom && selectedPreset == null))
                              ? null
                              : () async {
                                  setDialogState(() {
                                    isLoading = true;
                                    error = null;
                                  });
                                  final scaffoldMessenger =
                                      ScaffoldMessenger.of(context);
                                  final navigator = Navigator.of(ctx);
                                  try {
                                    final url = showCustom
                                        ? mcpUrlController.text.trim()
                                        : presets[selectedPreset]!['url']
                                              as String;
                                    final token =
                                        showCustom &&
                                            mcpTokenController.text
                                                .trim()
                                                .isNotEmpty
                                        ? mcpTokenController.text.trim()
                                        : null;
                                    await provider.connectMcpServer(
                                      url,
                                      token: token,
                                    );
                                    // Find the newly connected server to show tool count
                                    final server = provider.connectedMcpServers
                                        .where((s) => s.url == url)
                                        .lastOrNull;
                                    final toolCount = server?.tools.length ?? 0;
                                    final label = showCustom
                                        ? 'Server'
                                        : selectedPreset!;
                                    navigator.pop();
                                    scaffoldMessenger.showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          toolCount > 0
                                              ? '\u2705 $label connected · $toolCount tool${toolCount == 1 ? '' : 's'} available'
                                              : '\u2705 $label connected',
                                        ),
                                        backgroundColor:
                                            JarvisColors.accentPrimary,
                                        behavior: SnackBarBehavior.floating,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        duration: const Duration(seconds: 4),
                                      ),
                                    );
                                  } catch (e) {
                                    setDialogState(() {
                                      isLoading = false;
                                      final msg = e.toString().toLowerCase();
                                      if (msg.contains('cancel') || msg.contains('user_cancelled')) {
                                        error = 'Sign-in cancelled — try again';
                                      } else if (msg.contains('timeout')) {
                                        error = 'Connection timed out — check your internet';
                                      } else if (msg.contains('401') || msg.contains('unauthorized') || msg.contains('mcpauthError')) {
                                        error = 'Sign-in failed — please try again';
                                      } else if (msg.contains('oauth') || msg.contains('registration')) {
                                        error = 'This server requires manual setup — use Custom URL + token';
                                      } else {
                                        error = 'Could not connect — check the URL or try again';
                                      }
                                    });
                                  }
                                },
                          child: isLoading
                              ? Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.black,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      (presets[selectedPreset]?['auth'] as bool?) == true
                                          ? 'Opening browser...'
                                          : 'Connecting...',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                )
                              : Text(
                                  showCustom
                                      ? 'Connect'
                                      : ((presets[selectedPreset]?['auth']
                                                    as bool?) ==
                                                true
                                            ? '\uD83C\uDF10  Open Browser to Sign In'
                                            : 'Connect'),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
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
        const SizedBox(height: 12),
        _ActionTile(
          icon: Icons.bolt_rounded,
          title: 'Agentica OS',
          subtitle: 'Autonomous control of any Android app',
          iconColor: Colors.amber,
          onTap: () {
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AgenticaScreen()),
            );
          },
        ),
        const SizedBox(height: 12),
        _ActionTile(
          icon: Icons.auto_awesome,
          title: 'Imagiya Creative',
          subtitle: 'Generate images, eBooks & AI videos',
          iconColor: Colors.deepPurpleAccent,
          onTap: () {
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ImagiyaScreen()),
            );
          },
        ),
        const SizedBox(height: 12),
        _ActionTile(
          icon: Icons.videocam_rounded,
          title: 'Video Generator',
          subtitle: 'AI-generated 2-min cinematic video',
          iconColor: const Color(0xFF64FFDA),
          onTap: () {
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ImagiyaScreen(initialTabIndex: 3),
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
                  _showAddMcpDialog(provider);
                },
                leading: const Icon(
                  Icons.electrical_services_rounded,
                  color: Colors.blueAccent,
                ),
                title: const Text(
                  "Connect Remote MCP",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: const Text(
                  "Add external tools via Model Context Protocol",
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
    String finalText = text;
    if (_inputMode == ChatInputMode.imagiya && !text.startsWith('@')) {
      finalText = '[IMAGIYA] $_imagiyaQuality $_imagiyaStyle| $text';
    } else if (_inputMode == ChatInputMode.codesign && !text.startsWith('@')) {
      finalText = '[CODESIGN] $_codesignType| $text';
    }
    widget.onSubmit(finalText);
  }

  Widget _buildChip(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? JarvisColors.accentPrimary.withValues(alpha: 0.15)
              : JarvisColors.surfaceElevated,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? JarvisColors.accentPrimary
                : JarvisColors.border.withValues(alpha: 0.5),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : JarvisColors.textSecondary,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Widget _buildImagiyaOptions() {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Quality row
          Container(
            height: 36,
            margin: const EdgeInsets.only(bottom: 4),
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _buildChip(
                  '★ Standard',
                  _imagiyaQuality == 'standard',
                  () => setState(() => _imagiyaQuality = 'standard'),
                ),
                const SizedBox(width: 8),
                _buildChip(
                  '✨ HD',
                  _imagiyaQuality == 'hd',
                  () => setState(() => _imagiyaQuality = 'hd'),
                ),
                const SizedBox(width: 8),
                _buildChip(
                  '💎 Ultra HD',
                  _imagiyaQuality == 'uhd',
                  () => setState(() => _imagiyaQuality = 'uhd'),
                ),
              ],
            ),
          ),
          // Style row
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _buildChip(
                  '📷 Realistic',
                  _imagiyaStyle == 'realistic',
                  () => setState(() => _imagiyaStyle = 'realistic'),
                ),
                const SizedBox(width: 8),
                _buildChip(
                  '🎨 Artistic',
                  _imagiyaStyle == 'artistic',
                  () => setState(() => _imagiyaStyle = 'artistic'),
                ),
                const SizedBox(width: 8),
                _buildChip(
                  '🌟 Anime',
                  _imagiyaStyle == 'anime',
                  () => setState(() => _imagiyaStyle = 'anime'),
                ),
                const SizedBox(width: 8),
                _buildChip(
                  '🎥 Cinematic',
                  _imagiyaStyle == 'cinematic',
                  () => setState(() => _imagiyaStyle = 'cinematic'),
                ),
                const SizedBox(width: 8),
                _buildChip(
                  '🌀 Abstract',
                  _imagiyaStyle == 'abstract',
                  () => setState(() => _imagiyaStyle = 'abstract'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCodesignOptions() {
    const agents = [
      ('🚀', 'Landing', 'landing'),
      ('📊', 'Dashboard', 'dashboard'),
      ('📱', 'Mobile UI', 'mobile'),
      ('🧩', 'Component', 'component'),
      ('🛒', 'E-Commerce', 'ecommerce'),
      ('🎨', 'Portfolio', 'portfolio'),
      ('💰', 'SaaS Page', 'saas'),
      ('🔐', 'Auth Page', 'auth'),
      ('📝', 'Blog/Article', 'blog'),
      ('💬', 'Social App', 'social'),
      ('⚙️', 'Settings', 'settings'),
      ('📋', 'Admin Panel', 'admin'),
      ('💵', 'Pricing', 'pricing'),
      ('👤', 'Profile', 'profile'),
      ('📧', 'Email Template', 'email'),
      ('📈', 'Analytics', 'analytics'),
      ('🎮', 'Gaming UI', 'gaming'),
      ('🎓', 'EdTech UI', 'edtech'),
      ('🏥', 'Health App', 'health'),
      ('💳', 'Fintech App', 'fintech'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 4),
          child: Text(
            'CoDesign Agent · Pollinations AI',
            style: TextStyle(
              color: const Color(0xFF4DD0E1).withValues(alpha: 0.8),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ),
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: agents.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final (emoji, label, value) = agents[index];
              final isSelected = _codesignType == value;
              return GestureDetector(
                onTap: () => setState(() => _codesignType = value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF4DD0E1).withValues(alpha: 0.18)
                        : Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF4DD0E1).withValues(alpha: 0.6)
                          : Colors.white.withValues(alpha: 0.12),
                      width: isSelected ? 1.2 : 0.8,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: const Color(
                                0xFF4DD0E1,
                              ).withValues(alpha: 0.15),
                              blurRadius: 8,
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(emoji, style: const TextStyle(fontSize: 12)),
                      const SizedBox(width: 5),
                      Text(
                        label,
                        style: TextStyle(
                          color: isSelected
                              ? const Color(0xFF4DD0E1)
                              : Colors.white60,
                          fontSize: 12,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
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

  /// When user selects a skill from /picker, inject it as a [USE SKILL] tag in the text
  void _selectSlashSkill(JarvisSkill skill) {
    final text = _controller.text;
    final cursor = _controller.selection.baseOffset.clamp(0, text.length);
    final before = text.substring(0, cursor);
    final slashIdx = before.lastIndexOf('/');
    final after = text.substring(cursor);
    // Replace the /query with an invisible [SKILL:name] tag — the user message
    // reads naturally; JARVIS engine sees the tag and activates the skill.
    final tag = '[USE_SKILL:${skill.name}] ';
    final newText = '${text.substring(0, slashIdx)}$tag$after';
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: slashIdx + tag.length),
    );
    setState(() => _showSlashPicker = false);
    _focusNode.requestFocus();
  }

  /// Build the / skill picker overlay
  Widget _buildSlashPicker(SkillService skillService) {
    final allSkills = skillService.skills.where((s) => s.isActive).toList();
    final dnaSkills = allSkills
        .where((s) => s.id.startsWith('jarvis-dna-'))
        .toList();
    final otherSkills = allSkills
        .where((s) => !s.id.startsWith('jarvis-dna-'))
        .toList();

    // Filter by search query
    bool matchesQuery(JarvisSkill s) {
      if (_slashQuery.isEmpty) return true;
      return s.name.toLowerCase().contains(_slashQuery) ||
          s.description.toLowerCase().contains(_slashQuery);
    }

    final filteredDna = dnaSkills.where(matchesQuery).toList();
    final filteredOther = otherSkills.where(matchesQuery).take(30).toList();

    final dnaEmojis = {
      'claude-sonnet-4-6': '⚡',
      'claude-opus-4-6': '🧠',
      'claude-opus-4-7': '🔬',
      'claude-opus-4-8': '🏆',
      'gemini-3-5-flash': '⚡',
      'gpt-5-5': '🧩',
      'kimi-k2-6': '🌊',
    };

    String dnaEmoji(JarvisSkill s) {
      for (final entry in dnaEmojis.entries) {
        if (s.id.contains(entry.key)) return entry.value;
      }
      return '🧠';
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 340),
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A18),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF7C3AED).withValues(alpha: 0.4),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C3AED).withValues(alpha: 0.15),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C3AED).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: const Color(0xFF7C3AED).withValues(alpha: 0.4),
                    ),
                  ),
                  child: const Text(
                    '/ SKILLS',
                    style: TextStyle(
                      color: Color(0xFFA78BFA),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${allSkills.length} skills active',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.3),
                    fontSize: 10,
                  ),
                ),
                const Spacer(),
                // Open Skills Hub button
                GestureDetector(
                  onTap: () {
                    setState(() => _showSlashPicker = false);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SkillsScreen()),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Manage ›',
                      style: TextStyle(
                        color: Color(0xFFA78BFA),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Create new skill row
          GestureDetector(
            onTap: () {
              setState(() => _showSlashPicker = false);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SkillsScreen()),
              );
            },
            child: Container(
              margin: const EdgeInsets.fromLTRB(8, 0, 8, 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF7C3AED).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFF7C3AED).withValues(alpha: 0.25),
                  width: 0.8,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFF7C3AED).withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.add_rounded,
                      size: 16,
                      color: Color(0xFFA78BFA),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Create New Skill',
                          style: TextStyle(
                            color: Color(0xFFA78BFA),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Build a custom AI capability for JARVIS',
                          style: TextStyle(color: Colors.white38, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 12,
                    color: Color(0xFF7C3AED),
                  ),
                ],
              ),
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              children: [
                // ── Elite Model DNA section (always shown first) ──
                if (filteredDna.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(left: 4, top: 4, bottom: 4),
                    child: Row(
                      children: [
                        const Text('👑 ', style: TextStyle(fontSize: 10)),
                        const Text(
                          'ELITE MODEL DNA — Always Active',
                          style: TextStyle(
                            color: Color(0xFFFFD700),
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...filteredDna.map(
                    (skill) => _buildSkillTile(
                      skill,
                      emoji: dnaEmoji(skill),
                      accentColor: const Color(0xFFFFD700),
                      badge: 'ALWAYS ON',
                      badgeColor: const Color(0xFFFFD700),
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                // ── Contextual skills section ──
                if (filteredOther.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(left: 4, top: 4, bottom: 4),
                    child: Text(
                      '⚡ EXPERT SKILLS (${otherSkills.length} available)',
                      style: const TextStyle(
                        color: Color(0xFF7C3AED),
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                  ...filteredOther.map(
                    (skill) => _buildSkillTile(
                      skill,
                      emoji: '🧠',
                      accentColor: const Color(0xFF7C3AED),
                    ),
                  ),
                ],
                if (filteredDna.isEmpty && filteredOther.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'No skills match " $_slashQuery "',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkillTile(
    JarvisSkill skill, {
    required String emoji,
    required Color accentColor,
    String? badge,
    Color? badgeColor,
  }) {
    return GestureDetector(
      onTap: () => _selectSlashSkill(skill),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: accentColor.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: accentColor.withValues(alpha: 0.18),
            width: 0.7,
          ),
        ),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 15)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    skill.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    skill.description,
                    style: TextStyle(
                      color: accentColor.withValues(alpha: 0.7),
                      fontSize: 10,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (badge != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: (badgeColor ?? accentColor).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(
                    color: (badgeColor ?? accentColor).withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                    color: badgeColor ?? accentColor,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
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
    // Selector instead of Consumer: the input bar uses only a few slice of
    // the ChatProvider state (isAnalyzing, analysisStatus, attachedFilePaths).
    // Without this, the input bar's entire tree (model picker, mode toggle,
    // voice button, attachment row, text field) would rebuild on every
    // streaming notifyListeners() — even throttled, that's 60/s and the
    // text-field cursor jumps visibly.
    return Selector<ChatProvider, _ChatInputBarStateSlice>(
      selector: (_, cp) => _ChatInputBarStateSlice(
        isAnalyzing: cp.isAnalyzing,
        analysisStatus: cp.analysisStatus,
        attachedFileCount: cp.attachedFilePaths.length,
      ),
      builder: (context, slice, _) {
        // We need a real ChatProvider reference for the user-actions
        // (attach, unattach). context.read is fine because we don't
        // subscribe to its changes here.
        final chatProvider = context.read<ChatProvider>();
        final intProv = context.watch<IntegrationsProvider>();
        final skillService = context.watch<SkillService>();
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // / skill picker overlay
            if (_showSlashPicker) _buildSlashPicker(skillService),

            // @ mention picker overlay
            if (_showAtPicker) _buildAtPicker(intProv),

            // Creative Mode UI extensions
            if (_inputMode == ChatInputMode.imagiya) _buildImagiyaOptions(),
            if (_inputMode == ChatInputMode.codesign) _buildCodesignOptions(),

            // Analysis indicator
            if (slice.isAnalyzing)
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
                      slice.analysisStatus,
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
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF0A0A12).withValues(alpha: 0.0),
                    const Color(0xFF0A0A12),
                  ],
                ),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Mode selector above the input bar
                    Padding(
                      padding: const EdgeInsets.only(left: 6, bottom: 8),
                      child: PopupMenuButton<String>(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        color: const Color(0xFF1A1A2E),
                        offset: const Offset(0, -130),
                        tooltip: 'Switch Mode',
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: _inputMode == ChatInputMode.chat
                                ? Colors.white.withValues(alpha: 0.06)
                                : Colors.deepPurpleAccent.withValues(
                                    alpha: 0.15,
                                  ),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: _inputMode == ChatInputMode.chat
                                  ? Colors.white12
                                  : Colors.deepPurpleAccent.withValues(
                                      alpha: 0.45,
                                    ),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _inputMode == ChatInputMode.chat
                                    ? Icons.chat_bubble_outline_rounded
                                    : _inputMode == ChatInputMode.imagiya
                                    ? Icons.auto_awesome_rounded
                                    : Icons.design_services_rounded,
                                size: 14,
                                color: _inputMode == ChatInputMode.chat
                                    ? Colors.white54
                                    : Colors.deepPurpleAccent,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _inputMode == ChatInputMode.chat
                                    ? 'Chat'
                                    : _inputMode == ChatInputMode.imagiya
                                    ? 'Imagiya'
                                    : 'CoDesign',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _inputMode == ChatInputMode.chat
                                      ? Colors.white54
                                      : Colors.deepPurpleAccent,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.expand_less_rounded,
                                size: 14,
                                color: _inputMode == ChatInputMode.chat
                                    ? Colors.white30
                                    : Colors.deepPurpleAccent.withValues(
                                        alpha: 0.6,
                                      ),
                              ),
                            ],
                          ),
                        ),
                        onSelected: (value) {
                          if (value == 'agentica') {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const AgenticaScreen(),
                              ),
                            );
                          } else {
                            setState(
                              () =>
                                  _inputMode = ChatInputMode.values.firstWhere(
                                    (m) => m.name == value,
                                    orElse: () => ChatInputMode.chat,
                                  ),
                            );
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'chat',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.chat_bubble_outline_rounded,
                                  color: Colors.white70,
                                  size: 18,
                                ),
                                SizedBox(width: 12),
                                Text(
                                  'JARVIS Chat',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'imagiya',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.auto_awesome_rounded,
                                  color: Colors.deepPurpleAccent,
                                  size: 18,
                                ),
                                SizedBox(width: 12),
                                Text(
                                  'Imagiya · Image',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'codesign',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.design_services_rounded,
                                  color: Colors.indigoAccent,
                                  size: 18,
                                ),
                                SizedBox(width: 12),
                                Text(
                                  'CoDesign · UI',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'agentica',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.bolt_rounded,
                                  color: Colors.amber,
                                  size: 18,
                                ),
                                SizedBox(width: 12),
                                Text(
                                  'Agentica OS',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      decoration: BoxDecoration(
                        color: _focusNode.hasFocus
                            ? const Color(0xFF16162A)
                            : const Color(0xFF111120),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: _inputMode != ChatInputMode.chat
                              ? Colors.deepPurpleAccent.withValues(
                                  alpha: _focusNode.hasFocus ? 0.7 : 0.35,
                                )
                              : _focusNode.hasFocus
                              ? JarvisColors.accentPrimary.withValues(
                                  alpha: 0.55,
                                )
                              : JarvisColors.border.withValues(alpha: 0.4),
                          width: 1.2,
                        ),
                        boxShadow: _focusNode.hasFocus
                            ? [
                                BoxShadow(
                                  color:
                                      (_inputMode != ChatInputMode.chat
                                              ? Colors.deepPurpleAccent
                                              : JarvisColors.accentPrimary)
                                          .withValues(alpha: 0.14),
                                  blurRadius: 24,
                                  spreadRadius: 0,
                                ),
                              ]
                            : [],
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          // Left: + button
                          _InBarButton(
                            onTap: () => _showActionMenu(chatProvider),
                            child: Container(
                              width: 32,
                              height: 32,
                              margin: const EdgeInsets.only(left: 6, bottom: 6),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: JarvisColors.accentPrimary.withValues(
                                  alpha: 0.10,
                                ),
                                border: Border.all(
                                  color: JarvisColors.accentPrimary.withValues(
                                    alpha: 0.28,
                                  ),
                                  width: 1,
                                ),
                              ),
                              child: const Icon(
                                Icons.add_rounded,
                                color: JarvisColors.accentPrimary,
                                size: 18,
                              ),
                            ),
                          ),
                          // Text field — fills all available space
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              focusNode: _focusNode,
                              maxLines: 6,
                              minLines: 1,
                              style: const TextStyle(
                                color: JarvisColors.textPrimary,
                                fontSize: 15,
                                height: 1.45,
                              ),
                              cursorColor: JarvisColors.accentPrimary,
                              decoration: InputDecoration(
                                hintText: _inputMode == ChatInputMode.chat
                                    ? 'Message JARVIS...'
                                    : _inputMode == ChatInputMode.imagiya
                                    ? '✨ Describe your image...'
                                    : '🎨 Describe your UI...',
                                hintStyle: TextStyle(
                                  color: JarvisColors.textMuted.withValues(
                                    alpha: 0.55,
                                  ),
                                  fontSize: 14.5,
                                ),
                                border: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                filled: false,
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                  horizontal: 6,
                                ),
                                isDense: true,
                              ),
                              onSubmitted: (_) => _send(),
                            ),
                          ),
                          // Right cluster: model, mic, send
                          Padding(
                            padding: const EdgeInsets.only(right: 6, bottom: 6),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                // Mic button
                                if (_speechAvailable)
                                  AnimatedBuilder(
                                    animation: _pulseAnimation,
                                    builder: (ctx, child) => GestureDetector(
                                      onTap: _toggleListening,
                                      child: AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 200,
                                        ),
                                        width: 32,
                                        height: 32,
                                        margin: const EdgeInsets.only(right: 5),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: _isListening
                                              ? JarvisColors.accentPrimary
                                                    .withValues(alpha: 0.20)
                                              : JarvisColors.surfaceElevated,
                                          border: Border.all(
                                            color: _isListening
                                                ? JarvisColors.accentPrimary
                                                      .withValues(
                                                        alpha:
                                                            0.6 *
                                                            _pulseAnimation
                                                                .value,
                                                      )
                                                : JarvisColors.border
                                                      .withValues(alpha: 0.3),
                                            width: 1,
                                          ),
                                        ),
                                        child: Center(
                                          child: Icon(
                                            _isListening
                                                ? Icons.mic_rounded
                                                : Icons.mic_none_rounded,
                                            color: _isListening
                                                ? JarvisColors.accentPrimary
                                                : JarvisColors.textMuted,
                                            size: 16,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                // Send button
                                GestureDetector(
                                  onTap:
                                      (widget.isGenerating && !_isCreativeMode)
                                      ? null
                                      : _send,
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient:
                                          (!(widget.isGenerating &&
                                                  !_isCreativeMode) &&
                                              _hasText)
                                          ? const LinearGradient(
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                              colors: [
                                                Color(0xFF7B5FFF),
                                                Color(0xFF9B88FF),
                                              ],
                                            )
                                          : null,
                                      color:
                                          (!(widget.isGenerating &&
                                                  !_isCreativeMode) &&
                                              _hasText)
                                          ? null
                                          : JarvisColors.surfaceElevated,
                                      border: Border.all(
                                        color:
                                            (!(widget.isGenerating &&
                                                    !_isCreativeMode) &&
                                                _hasText)
                                            ? Colors.transparent
                                            : JarvisColors.border.withValues(
                                                alpha: 0.4,
                                              ),
                                        width: 1,
                                      ),
                                      boxShadow:
                                          (!(widget.isGenerating &&
                                                  !_isCreativeMode) &&
                                              _hasText)
                                          ? [
                                              BoxShadow(
                                                color: const Color(
                                                  0xFF7B5FFF,
                                                ).withValues(alpha: 0.5),
                                                blurRadius: 14,
                                                offset: const Offset(0, 3),
                                              ),
                                            ]
                                          : null,
                                    ),
                                    child:
                                        (widget.isGenerating &&
                                            !_isCreativeMode)
                                        ? const Padding(
                                            padding: EdgeInsets.all(10),
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor:
                                                  AlwaysStoppedAnimation(
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
                  ],
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
  final Color? iconColor; // optional tint override

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = iconColor ?? JarvisColors.accentPrimary;
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
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 20),
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

// _ModelOption removed — Netless / Infinity picker dropped
