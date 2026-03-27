import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../../theme/jarvis_theme.dart';
import '../features/chat/chat_provider.dart';
import '../features/vibecode/vibecode_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _initSpeech();
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
          child: SwitchListTile(
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
        ),
        const SizedBox(height: 12),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            "More tools coming soon...",
            style: TextStyle(color: JarvisColors.textMuted, fontSize: 12),
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
    widget.onSubmit(text);
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
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
