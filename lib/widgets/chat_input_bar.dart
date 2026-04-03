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

class _ChatInputBarState extends State<ChatInputBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  bool _speechAvailable = false;

  // @ mention picker state
  bool _showAtPicker = false;
  String _atQuery = '';

  @override
  void initState() {
    super.initState();
    _initSpeech();
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final text = _controller.text;
    final cursor = _controller.selection.baseOffset;
    // Find if there's an unclosed @ before cursor
    if (cursor > 0 && cursor <= text.length) {
      final before = text.substring(0, cursor);
      final atIdx = before.lastIndexOf('@');
      if (atIdx >= 0) {
        final afterAt = before.substring(atIdx + 1);
        // Only show if no space after @
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
                    position: Tween<Offset>(
                      begin: const Offset(0, 1),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    )),
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
                leading: const Icon(Icons.image_rounded, color: Colors.purpleAccent),
                title: const Text("Image Generator", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: const Text("Powered autonomously by Arena.ai", style: TextStyle(color: JarvisColors.textMuted, fontSize: 12)),
              ),
              const Divider(height: 1, color: JarvisColors.border),
              ListTile(
                onTap: () {
                  Navigator.pop(context);
                  _controller.text = "@arena Generate a video of: ";
                  _focusNode.requestFocus();
                },
                leading: const Icon(Icons.movie_creation_rounded, color: Colors.blueAccent),
                title: const Text("Video Generator", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: const Text("Powered autonomously by Arena.ai", style: TextStyle(color: JarvisColors.textMuted, fontSize: 12)),
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
    
    // Explicitly drop focus if it's an integration command so InAppWebView gets native input
    if (text.startsWith('@')) {
      _focusNode.unfocus();
    }
    
    setState(() => _showAtPicker = false);
    widget.onSubmit(text);
  }

  /// Insert @integrationId into text at current cursor
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
          offset: atIdx + integration.id.length + 2),
    );
    setState(() => _showAtPicker = false);
    _focusNode.requestFocus();
  }

  /// Build the @ mention picker that appears above the input
  Widget _buildAtPicker(IntegrationsProvider intProv) {
    final connected = intProv.connectedIntegrations;
    final all = kAIIntegrations;
    // Show connected first, then all matching the query
    final filtered = [
      ...connected,
      ...all.where((a) => !connected.any((c) => c.id == a.id)),
    ].where((i) =>
            _atQuery.isEmpty ||
            i.id.contains(_atQuery) ||
            i.name.toLowerCase().contains(_atQuery))
        .toList();

    if (filtered.isEmpty) return const SizedBox.shrink();

    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: JarvisColors.accentPrimary.withValues(alpha: 0.25)),
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
                const Text('⚡',
                    style: TextStyle(fontSize: 11)),
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
                        horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: color.withValues(alpha: 0.2), width: 0.7),
                    ),
                    child: Row(
                      children: [
                        Text(item.emoji,
                            style: const TextStyle(fontSize: 16)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
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
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF22C55E)
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: const Color(0xFF22C55E)
                                      .withValues(alpha: 0.4)),
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

            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              decoration: BoxDecoration(
                color: Colors.transparent,
                border: const Border(
                  top: BorderSide(color: JarvisColors.border, width: 0.5),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    // File picker button
                    IconButton(
                      icon: const Icon(
                        Icons.add_rounded,
                        color: JarvisColors.textSecondary,
                      ),
                      onPressed: () => _showActionMenu(chatProvider),
                      tooltip: 'Actions',
                    ),
                    const SizedBox(width: 4),

                    // Voice input button
                    if (_speechAvailable)
                      GestureDetector(
                        onTap: _toggleListening,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isListening
                                ? JarvisColors.accentPrimary.withValues(
                                    alpha: 0.2,
                                  )
                                : JarvisColors.surfaceElevated,
                            border: Border.all(
                              color: _isListening
                                  ? JarvisColors.accentPrimary
                                  : JarvisColors.border,
                              width: 1,
                            ),
                          ),
                          child: Icon(
                            _isListening ? Icons.mic : Icons.mic_none_rounded,
                            color: _isListening
                                ? JarvisColors.accentPrimary
                                : JarvisColors.textMuted,
                            size: 20,
                          ),
                        ),
                      ),
                    const SizedBox(width: 10),

                    // Text field
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: _focusNode.hasFocus
                              ? JarvisColors.surfaceElevated
                              : Colors.black26,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: _focusNode.hasFocus
                                ? JarvisColors.accentPrimary.withValues(
                                    alpha: 0.5,
                                  )
                                : JarvisColors.border.withValues(alpha: 0.3),
                            width: 1,
                          ),
                        ),
                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          maxLines: 4,
                          minLines: 1,
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
                            filled: false,
                            fillColor: Colors.transparent,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                          ),
                          onSubmitted: (_) => _send(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),

                    // Send button
                    GestureDetector(
                      onTap: widget.isGenerating ? null : _send,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: widget.isGenerating
                              ? null
                              : JarvisColors.primaryGradient,
                          color: widget.isGenerating
                              ? JarvisColors.surfaceElevated
                              : null,
                          boxShadow: widget.isGenerating
                              ? null
                              : [
                                  BoxShadow(
                                    color: JarvisColors.accentPrimary
                                        .withValues(alpha: 0.4),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                        ),
                        child: widget.isGenerating
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation(
                                    JarvisColors.accentPrimary,
                                  ),
                                ),
                              )
                            : const Icon(
                                Icons.arrow_upward_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
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
            border: Border.all(color: JarvisColors.border, width: 0.5),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: JarvisColors.accentPrimary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: JarvisColors.accentPrimary, size: 24),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: JarvisColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              const Icon(
                Icons.chevron_right_rounded,
                color: JarvisColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
