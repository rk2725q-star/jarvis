import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../vibecode_controller.dart';

class ChatPanel extends StatefulWidget {
  const ChatPanel({super.key});

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _sendMessage(VibeCodeController vc) {
    final text = _controller.text.trim();
    if (text.isEmpty || vc.isGenerating) return;
    _controller.clear();

    vc.processChat(text);

    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final vc = context.watch<VibeCodeController>();

    return Container(
      color: const Color(0xFF0A0A0F),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFF1E1E2E))),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.auto_awesome,
                  color: Color(0xFF7C3AED),
                  size: 18,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Jarvis Chat',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const Spacer(),
                if (vc.isGenerating)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF7C3AED),
                    ),
                  ),
              ],
            ),
          ),

          // Messages
          Expanded(
            child: vc.chatHistory.isEmpty && !vc.isThinking
                ? _buildEmptyState()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    itemCount: vc.chatHistory.length + (vc.isThinking ? 1 : 0),
                    itemBuilder: (ctx, i) {
                      if (i == vc.chatHistory.length && vc.isThinking) {
                        return _buildThinkingIndicator();
                      }
                      return _ChatBubble(msg: vc.chatHistory[i]);
                    },
                  ),
          ),

          // Quick prompts (shown when no project)
          if (!vc.hasProject) _buildQuickPrompts(vc),

          // Input area
          _buildInputArea(vc),
        ],
      ),
    );
  }

  Widget _buildThinkingIndicator() {
    final vc = context.read<VibeCodeController>();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF7C3AED),
                ),
              ),
              const SizedBox(width: 12),
              Animate(
                onPlay: (c) => c.repeat(),
                child: Text(
                  'JARIVS ANTIGRAVITY ENGINE IS ACTIVE',
                  style: TextStyle(
                    color: const Color(0xFF7C3AED).withValues(alpha: 0.8),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.0,
                  ),
                ),
              ).shimmer(duration: const Duration(seconds: 2)),
            ],
          ),
          const SizedBox(height: 16),
          // Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: vc.buildProgress,
              backgroundColor: const Color(0xFF1E1E2E),
              color: const Color(0xFF7C3AED),
              minHeight: 4,
            ),
          ),
          const SizedBox(height: 16),
          // Current Action Box
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0A0F),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFF7C3AED).withValues(alpha: 0.2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  vc.thinkingMessage,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 1.5,
                  ),
                ),
                if (vc.buildLogs.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Divider(color: Colors.white10),
                  const SizedBox(height: 8),
                  ...vc.buildLogs.reversed.take(3).map((log) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_outline, size: 12, color: Colors.greenAccent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            log.message,
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  )),
                ],
              ],
            ),
          ).animate().fadeIn().slideY(begin: 0.1, end: 0),
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
            // Icon
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E2E),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF7C3AED).withValues(alpha: 0.2),
                    blurRadius: 40,
                    spreadRadius: 10,
                  ),
                ],
                border: Border.all(
                  color: const Color(0xFF7C3AED).withValues(alpha: 0.3),
                ),
              ),
              child: const Icon(
                Icons.flash_on_rounded,
                size: 48,
                color: Color(0xFF7C3AED),
              ),
            ),
            const SizedBox(height: 32),

            // Text
            const Text(
              'Tell VibeCode what to build',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 24,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                'Describe your app or website in natural language,\nand Jarvis will generate all the code for you.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickPrompts(VibeCodeController vc) {
    final prompts = [
      '🛒 E-commerce landing page',
      '📊 Admin dashboard with charts',
      '💬 Real-time chat interface',
      '🎵 Music player app',
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: prompts.map((p) {
          return GestureDetector(
            onTap: () => vc.generateProject(p),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E2E),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF7C3AED), width: 0.5),
              ),
              child: Text(
                p,
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildInputArea(VibeCodeController vc) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF1E1E2E))),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              maxLines: 4,
              minLines: 1,
              decoration: InputDecoration(
                hintText: vc.hasProject
                    ? 'Ask me to modify, fix bugs, add features...'
                    : 'Describe your app or website...',
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3),
                  fontSize: 12,
                ),
                filled: true,
                fillColor: const Color(0xFF1E1E2E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
              ),
              onSubmitted: (_) => _sendMessage(vc),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF7C3AED), Color(0xFF2563EB)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: vc.isGenerating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(
                      Icons.send_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
              onPressed: vc.isGenerating ? null : () => _sendMessage(vc),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final ChatMessage msg;

  const _ChatBubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    final isUser = msg.role == 'user';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!isUser)
            Container(
              width: 28,
              height: 28,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF7C3AED), Color(0xFF2563EB)],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Text(
                  'J',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isUser
                    ? const Color(0xFF7C3AED)
                    : const Color(0xFF1E1E2E),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                msg.content,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
