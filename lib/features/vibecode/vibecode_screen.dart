import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:ui';
import '../../core/router/ai_router.dart';
import 'vibecode_controller.dart';
import 'widgets/chat_panel.dart';
import 'widgets/preview_panel.dart';
import 'widgets/file_explorer.dart';

class VibeCodeScreen extends StatefulWidget {
  const VibeCodeScreen({super.key});

  @override
  State<VibeCodeScreen> createState() => _VibeCodeScreenState();
}

class _VibeCodeScreenState extends State<VibeCodeScreen> {
  int _selectedIndex = 0; // 0: Chat, 1: Workspace
  bool _showLogs = false;

  @override
  Widget build(BuildContext context) {
    final vc = context.watch<VibeCodeController>();

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: Stack(
        children: [
          // ── MAIN CONTENT ──────────────────────────────────
          Column(
            children: [
              _buildAppBar(vc),
              _buildTabNavigator(),
              Expanded(
                child: IndexedStack(
                  index: _selectedIndex,
                  children: [
                    const ChatPanel(),
                    _buildWorkspaceView(vc),
                  ],
                ),
              ),
            ],
          ),

          // ── BUILD PROGRESS OVERLAY ────────────────────────
          if (vc.isGenerating) _buildProgressOverlay(vc),

          // ── LOGS PANEL (DRAWER-LIKE) ──────────────────────
          if (_showLogs) _buildLogsOverlay(vc),
        ],
      ),
    );
  }

  Widget _buildAppBar(VibeCodeController vc) {
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 8, bottom: 8, left: 16, right: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0F),
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white70, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'VIBE CODE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3,
                  ),
                ),
                Text(
                  'ANTIGRAVITY CORE v2',
                  style: TextStyle(
                    color: Color(0xFF7C3AED),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.terminal_rounded,
              color: _showLogs ? const Color(0xFF7C3AED) : Colors.white70,
              size: 20,
            ),
            onPressed: () => setState(() => _showLogs = !_showLogs),
          ),
          IconButton(
            icon: const Icon(Icons.tune_rounded, color: Colors.white70, size: 20),
            onPressed: () => _showBuildSettings(context, vc),
          ),
        ],
      ),
    );
  }

  Widget _buildTabNavigator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Container(
        height: 44,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFF16161E),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            _buildTabItem(0, Icons.chat_bubble_outline_rounded, 'GENESIS CHAT'),
            _buildTabItem(1, Icons.code_rounded, 'WORKSPACE'),
          ],
        ),
      ),
    );
  }

  Widget _buildTabItem(int index, IconData icon, String label) {
    final isSelected = _selectedIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedIndex = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF7C3AED).withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? const Color(0xFF7C3AED).withValues(alpha: 0.3) : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: isSelected ? const Color(0xFF7C3AED) : Colors.white38, size: 16),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white38,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgressOverlay(VibeCodeController vc) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: Container(
        color: Colors.black.withValues(alpha: 0.6),
        width: double.infinity,
        height: double.infinity,
        child: Center(
          child: Container(
            width: 300,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: const Color(0xFF16161E),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white10),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF7C3AED).withValues(alpha: 0.2),
                  blurRadius: 40,
                  spreadRadius: -10,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 60,
                  height: 60,
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF7C3AED)),
                    strokeWidth: 2,
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  vc.currentPhase.name.toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFF7C3AED),
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  vc.thinkingMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 24),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: vc.buildProgress,
                    backgroundColor: Colors.white.withValues(alpha: 0.05),
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF7C3AED)),
                    minHeight: 4,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${(vc.buildProgress * 100).toInt()}% COMPLETE',
                  style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogsOverlay(VibeCodeController vc) {
    return Positioned(
      bottom: 20,
      left: 20,
      right: 20,
      child: Material(
        color: Colors.transparent,
        child: Container(
          height: 300,
          decoration: BoxDecoration(
            color: const Color(0xFF0D0D12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white10),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 20)],
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.terminal_rounded, color: Colors.white38, size: 16),
                    const SizedBox(width: 8),
                    const Text(
                      'BUILD LOGS',
                      style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white38, size: 16),
                      onPressed: () => setState(() => _showLogs = false),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: vc.buildLogs.length,
                  itemBuilder: (context, index) {
                    final log = vc.buildLogs[vc.buildLogs.length - 1 - index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '[${log.phase.name.substring(0, 3).toUpperCase()}]',
                            style: const TextStyle(color: Color(0xFF7C3AED), fontSize: 11, fontFamily: 'monospace'),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              log.message,
                              style: const TextStyle(color: Colors.white60, fontSize: 11, fontFamily: 'monospace'),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showBuildSettings(BuildContext context, VibeCodeController vc) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF16161E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'GENESIS CONFIG',
                style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 2),
              ),
              const SizedBox(height: 24),
              const Text('AI ARCHITECT PROVIDER', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _providerChip(null, 'AUTO-FALLBACK', vc),
                  _providerChip(AIProvider.gemini, 'GEMINI 1.5 PRO', vc),
                  _providerChip(AIProvider.nvidia, 'NVIDIA NIM', vc),
                  _providerChip(AIProvider.ollamaCloud, 'OLLAMA CLOUD', vc),
                  _providerChip(AIProvider.ollama, 'LOCAL OLLAMA', vc),
                ],
              ),
              const SizedBox(height: 32),
              _buildIntegrationStatus(
                'SUPABASE',
                vc.isSupabaseConnected ? 'CONNECTED' : 'NOT CONNECTED',
                vc.isSupabaseConnected ? Colors.green : Colors.red,
              ),
              _buildIntegrationStatus(
                'GITHUB',
                vc.isGithubConnected ? 'CONNECTED' : 'NOT CONNECTED',
                vc.isGithubConnected ? Colors.green : Colors.red,
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  Widget _buildIntegrationStatus(String label, String status, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.bold)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Text(
              status,
              style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _providerChip(AIProvider? provider, String label, VibeCodeController vc) {
    final isSelected = vc.preferredProvider == provider;
    return GestureDetector(
      onTap: () {
        vc.setProvider(provider);
        Navigator.pop(context);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF7C3AED) : const Color(0xFF1E1E2E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? Colors.white30 : Colors.white10),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white60,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  Widget _buildWorkspaceView(VibeCodeController vc) {
    if (!vc.hasProject) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF16161E),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.03)),
              ),
              child: const Icon(Icons.rocket_launch_rounded, size: 40, color: Colors.white10),
            ),
            const SizedBox(height: 24),
            const Text(
              'AWAITING GENESIS',
              style: TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 2),
            ),
            const SizedBox(height: 8),
            const Text(
              'Describe your vision in the chat to begin building.',
              style: TextStyle(color: Colors.white24, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 900) {
          return Row(
            children: [
              const SizedBox(width: 240, child: FileExplorerPanel()),
              VerticalDivider(color: Colors.white.withValues(alpha: 0.05), width: 1),
              const Expanded(flex: 3, child: CodeEditorPanel()),
              VerticalDivider(color: Colors.white.withValues(alpha: 0.05), width: 1),
              const Expanded(flex: 2, child: PreviewPanel()),
            ],
          );
        } else {
          return const Column(
            children: [
              Expanded(flex: 3, child: CodeEditorPanel()),
              Divider(color: Color(0xFF1E1E2E), height: 1),
              Expanded(flex: 2, child: PreviewPanel()),
            ],
          );
        }
      },
    );
  }
}
