import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../vibecode_controller.dart';

class PreviewPanel extends StatefulWidget {
  const PreviewPanel({super.key});

  @override
  State<PreviewPanel> createState() => _PreviewPanelState();
}

class _PreviewPanelState extends State<PreviewPanel> {
  InAppWebViewController? _webController;
  bool _isLoading = true;
  String _currentHtml = '';

  void _loadHtml(String html) {
    if (html == _currentHtml) return;
    _currentHtml = html;
    _webController?.loadData(data: html);
  }

  @override
  Widget build(BuildContext context) {
    final vc = context.watch<VibeCodeController>();
    final project = vc.currentProject;

    if (project == null) {
      return _buildEmptyPreview();
    }

    // Load the combined HTML
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadHtml(project.combinedPreviewHtml);
    });

    return Container(
      color: const Color(0xFF0A0A0F),
      child: Column(
        children: [
          // Preview toolbar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: const Color(0xFF1E1E2E),
            child: Row(
              children: [
                // Browser-like dots
                Row(
                  children: [
                    _dot(Colors.red),
                    const SizedBox(width: 6),
                    _dot(Colors.yellow),
                    const SizedBox(width: 6),
                    _dot(Colors.green),
                  ],
                ),
                const SizedBox(width: 16),
                // URL bar
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A0A0F),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.lock, size: 10, color: Colors.greenAccent),
                        const SizedBox(width: 6),
                        Text(
                          project.vercelUrl ?? 'localhost:3000 (preview)',
                          style: const TextStyle(color: Colors.white38, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Refresh
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.white38, size: 16),
                  onPressed: () => _webController?.reload(),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 8),
                if (_isLoading)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: Color(0xFF7C3AED),
                    ),
                  ),
              ],
            ),
          ),
          // WebView
          Expanded(
            child: Stack(
              children: [
                InAppWebView(
                  initialSettings: InAppWebViewSettings(
                    javaScriptEnabled: true,
                    transparentBackground: true,
                  ),
                  onWebViewCreated: (controller) {
                    _webController = controller;
                  },
                  onLoadStart: (controller, url) {
                    setState(() => _isLoading = true);
                  },
                  onLoadStop: (controller, url) {
                    setState(() => _isLoading = false);
                  },
                ),
                if (vc.isGenerating)
                  Container(
                    color: Colors.black87,
                    child: const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: Color(0xFF7C3AED)),
                          SizedBox(height: 16),
                          Text(
                            '⚡ Jarvis is building your app...',
                            style: TextStyle(color: Colors.white, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot(Color color) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );

  Widget _buildEmptyPreview() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🖥️', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 16),
          const Text(
            'Preview will appear here',
            style: TextStyle(color: Colors.white38, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            'Tell Jarvis what to build in the chat →',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.2), fontSize: 12),
          ),
        ],
      ),
    );
  }
}
