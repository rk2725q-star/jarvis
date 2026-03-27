import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'dart:convert';
import 'diagram_service.dart';
import '../../core/router/ai_router.dart';

class DiagramScreen extends StatefulWidget {
  final AIRouter router;
  final String request;
  final String title;

  const DiagramScreen({
    super.key,
    required this.router,
    required this.request,
    this.title = 'DIAGRAM',
  });

  @override
  State<DiagramScreen> createState() => _DiagramScreenState();
}

class _DiagramScreenState extends State<DiagramScreen> {
  InAppWebViewController? _webViewController;
  bool _isGenerating = true;
  bool _isLoaded = false;
  String? _htmlContent;
  String? _errorMsg;
  final DiagramService _service = DiagramService();

  @override
  void initState() {
    super.initState();
    _startGeneration();
  }

  Future<void> _startGeneration() async {
    try {
      final html = await _service.generateDiagram(widget.router, widget.request);
      if (mounted) {
        setState(() {
          _htmlContent = html;
          _isGenerating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMsg = e.toString();
          _isGenerating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    String? dataUri;
    if (_htmlContent != null) {
      final base64Html = base64Encode(utf8.encode(_htmlContent!));
      dataUri = 'data:text/html;charset=utf-8;base64,$base64Html';
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0F),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Color(0xFF00FFB4), size: 18),
          onPressed: () => Navigator.pop(context, _htmlContent != null), // Return true if successful, tells provider
        ),
        title: Text(
          'JARVIS — \${widget.title.toUpperCase()}',
          style: const TextStyle(
            color: Color(0xFF00FFB4),
            fontFamily: 'monospace',
            fontSize: 12,
            letterSpacing: 2.5,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF445566), size: 20),
            onPressed: () {
              if (dataUri != null) {
                _webViewController?.reload();
              } else {
                setState(() {
                  _isGenerating = true;
                  _errorMsg = null;
                });
                _startGeneration();
              }
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: const Color(0xFF00FFB4).withValues(alpha: 0.15),
          ),
        ),
      ),
      body: Stack(
        children: [
          if (dataUri != null)
            InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(dataUri)),
              onWebViewCreated: (controller) {
                _webViewController = controller;
              },
              onLoadStop: (controller, url) {
                setState(() => _isLoaded = true);
              },
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                transparentBackground: true,
                useWideViewPort: false,
                loadWithOverviewMode: true,
                supportZoom: false,
                disableHorizontalScroll: true,
              ),
            ),

          // Loading overlay or Error State
          if (_isGenerating || (!_isLoaded && dataUri != null))
            Container(
              color: const Color(0xFF0A0A0F),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildPulsingRing(),
                    const SizedBox(height: 24),
                    const Text(
                      'GENERATING DIAGRAM',
                      style: TextStyle(
                        color: Color(0xFF00FFB4),
                        fontFamily: 'monospace',
                        fontSize: 11,
                        letterSpacing: 3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isGenerating ? 'JARVIS AI Engine is drawing...' : 'Rendering UI Engine...',
                      style: const TextStyle(
                        color: Color(0xFF445566),
                        fontFamily: 'monospace',
                        fontSize: 10,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
          if (_errorMsg != null)
             Container(
              color: const Color(0xFF0A0A0F),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      'FAILED TO GENERATE DIAGRAM',
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontFamily: 'monospace',
                        fontSize: 11,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        _errorMsg!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF445566),
                          fontFamily: 'monospace',
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPulsingRing() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.8, end: 1.2),
      duration: const Duration(milliseconds: 900),
      builder: (context, scale, child) {
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFF00FFB4),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00FFB4).withValues(alpha: 0.3),
                  blurRadius: 20,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: const Icon(
              Icons.auto_awesome,
              color: Color(0xFF00FFB4),
              size: 22,
            ),
          ),
        );
      },
      onEnd: () => setState(() {}),
    );
  }
}
