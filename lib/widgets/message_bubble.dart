// ignore_for_file: deprecated_member_use
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_markdown_latex/flutter_markdown_latex.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:jarvis_ai/features/chat/chat_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../../theme/jarvis_theme.dart';
import '../../models/message.dart';
import 'integration_card_bubble.dart';
import 'roadmap_card_bubble.dart';
import '../../features/integrations/integrations_model.dart';
import '../../features/integrations/integration_browser_screen.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'jarvis_pdf_button.dart';

// ── Model DNA config (emoji + short label + accent color) ──
const _dnaConfig = [
  _DnaInfo('claude-sonnet-4-6', '⚡', 'Sonnet 4.6', Color(0xFFFF8C00)),
  _DnaInfo('claude-opus-4-6', '🧠', 'Opus 4.6', Color(0xFF7C3AED)),
  _DnaInfo('claude-opus-4-7', '🔬', 'Opus 4.7', Color(0xFF06B6D4)),
  _DnaInfo('claude-opus-4-8', '🏆', 'Opus 4.8', Color(0xFFFFD700)),
  _DnaInfo('gemini-3-5-flash', '🚀', 'Flash 3.5', Color(0xFF4285F4)),
  _DnaInfo('gpt-5-5', '🧩', 'GPT 5.5', Color(0xFF00A67E)),
  _DnaInfo('kimi-k2-6', '🌊', 'Kimi K2.6', Color(0xFF0EA5E9)),
];

class _DnaInfo {
  final String id;
  final String emoji;
  final String label;
  final Color color;
  const _DnaInfo(this.id, this.emoji, this.label, this.color);
}

class MessageBubble extends StatelessWidget {
  final Message message;

  const MessageBubble({super.key, required this.message});

  Color _providerColor(String? provider) {
    switch (provider?.toLowerCase()) {
      case 'gemini':
        return JarvisColors.geminiColor;
      case 'ollama':
        return JarvisColors.ollamaColor;
      case 'nvidia':
        return JarvisColors.nvidiaColor;
      case 'deepseek':
        return JarvisColors.deepseekColor;
      case 'local':
        return JarvisColors.localColor;
      default:
        return JarvisColors.accentPrimary;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (message.isUser) {
      if (message.provider != null &&
          message.provider!.isNotEmpty &&
          message.provider != 'imagiya' &&
          message.provider != 'codesign') {
        return Column(
          children: [
            _UserBubble(message: message),
            _InlineIntegrationBrowser(
              integrationId: message.provider!,
              query: message.content,
            ),
          ],
        );
      }
      return _UserBubble(message: message);
    } else if (message.provider == 'imagiya') {
      // Extract URL from markdown image syntax: ![Generated Image](url)
      final imgMatch = RegExp(r'!\[.*?\]\((.+?)\)').firstMatch(message.content);
      final imageUrl = imgMatch?.group(1) ?? '';
      return _ImagiyaImageBubble(
        imageUrl: imageUrl,
        providerColor: const Color(0xFF9B88FF),
        label: 'IMAGIYA · AI Image',
      );
    } else if (message.provider == 'codesign') {
      // CoDesign: render actual HTML in WebView (open-codesign architecture)
      if (message.content == '[CODESIGN_GENERATING]') {
        return _CodesignGeneratingBubble();
      }
      if (message.content.startsWith('[CODESIGN_HTML]')) {
        final htmlCode = message.content.substring('[CODESIGN_HTML]'.length);
        return _CodesignHtmlBubble(htmlCode: htmlCode);
      }
      // Legacy fallback: Pollinations image
      final imgMatch = RegExp(r'!\[.*?\]\((.+?)\)').firstMatch(message.content);
      final imageUrl = imgMatch?.group(1) ?? '';
      if (imageUrl.isNotEmpty) {
        return _ImagiyaImageBubble(
          imageUrl: imageUrl,
          providerColor: const Color(0xFF4DD0E1),
          label: 'CODESIGN · AI Design',
        );
      }
      return _CodesignGeneratingBubble();
    } else if (RoadmapCardBubble.isRoadmapCard(message.content)) {
      return RoadmapCardBubble(rawContent: message.content);
    } else if (IntegrationCardBubble.isIntegrationCard(message.content)) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12, left: 16, right: 16),
        child: IntegrationCardBubble(rawContent: message.content),
      );
    } else {
      return _AIBubble(
        message: message,
        providerColor: _providerColor(message.provider),
      );
    }
  }
}

class _InlineIntegrationBrowser extends StatefulWidget {
  final String integrationId;
  final String query;

  const _InlineIntegrationBrowser({
    required this.integrationId,
    required this.query,
  });

  @override
  State<_InlineIntegrationBrowser> createState() =>
      _InlineIntegrationBrowserState();
}

class _InlineIntegrationBrowserState extends State<_InlineIntegrationBrowser> {
  bool _hasInjected = false;

  @override
  Widget build(BuildContext context) {
    final integration = kAIIntegrations.cast<AIIntegration?>().firstWhere(
      (i) => i?.id == widget.integrationId,
      orElse: () => null,
    );
    if (integration == null) return const SizedBox.shrink();

    final launchUrl = integration.buildTaskUrl(widget.query);

    if (launchUrl.startsWith('internal://')) {
      return const SizedBox.shrink();
    }

    return Container(
          width: double.infinity,
          height: MediaQuery.of(context).size.height * 0.68,
          margin: const EdgeInsets.only(top: 8, bottom: 24, left: 4, right: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF0A0A0F),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: JarvisColors.border, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: integration.gradientColors.isNotEmpty
                    ? Color(
                        integration.gradientColors.first,
                      ).withValues(alpha: 0.1)
                    : Colors.black26,
                blurRadius: 20,
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              InAppWebView(
                initialUrlRequest: URLRequest(url: WebUri(launchUrl)),
                gestureRecognizers: {
                  Factory<VerticalDragGestureRecognizer>(
                    () => VerticalDragGestureRecognizer(),
                  ),
                  Factory<HorizontalDragGestureRecognizer>(
                    () => HorizontalDragGestureRecognizer(),
                  ),
                  Factory<ScaleGestureRecognizer>(
                    () => ScaleGestureRecognizer(),
                  ),
                },
                initialSettings: InAppWebViewSettings(
                  useWideViewPort: true,
                  loadWithOverviewMode: true,
                  javaScriptEnabled: true,
                  transparentBackground: true,
                  preferredContentMode: UserPreferredContentMode.MOBILE,
                  supportZoom: true,
                ),
                onLoadStop: (controller, url) async {
                  if (!_hasInjected && widget.query.isNotEmpty) {
                    _hasInjected = true;

                    // Human-like typewriting simulation to bypass detection and wait 2 seconds
                    String query = widget.query
                        .replaceAll('"', '\\"')
                        .replaceAll('\n', '\\n');
                    String script =
                        '''
                  (async function() {
                    const humanType = async (el, text) => {
                      el.focus();
                      for (let char of text) {
                        document.execCommand('insertText', false, char);
                        await new Promise(r => setTimeout(r, 30 + Math.random() * 70));
                      }
                      el.dispatchEvent(new Event('input', { bubbles: true }));
                      el.dispatchEvent(new Event('change', { bubbles: true }));
                    };

                    await new Promise(r => setTimeout(r, 2000)); // Initial 2s delay as requested

                    let selectors = [
                      '#prompt-textarea', 'textarea', 'input[type="text"]', 
                      '[contenteditable="true"]', '.chat-input', '.text-area'
                    ];
                    
                    let tf = null;
                    for(let s of selectors) {
                      tf = document.querySelector(s);
                      if(tf) break;
                    }

                    if(tf) {
                      await humanType(tf, "$query");
                      await new Promise(r => setTimeout(r, 1000));

                      let btnSelectors = [
                        'button[data-testid="send-button"]', 'button[type="submit"]',
                        'button.send-button', '.submit-button', 'button svg'
                      ];

                      let btn = null;
                      for(let bs of btnSelectors) {
                        let candidate = document.querySelector(bs);
                        if(candidate) {
                          if(candidate.tagName === 'svg') btn = candidate.parentElement;
                          else btn = candidate;
                          break;
                        }
                      }
                      
                      if(!btn) {
                        let btns = Array.from(document.querySelectorAll('button'));
                        btn = btns.find(b => b.innerText.toLowerCase().match(/send|submit|generate|create|battle/));
                      }

                      if(btn) btn.click();
                      else tf.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', code: 'Enter', bubbles: true }));
                    }
                  })();
                ''';
                    await controller.evaluateJavascript(source: script);
                  }
                },
              ),
              Positioned(
                bottom: 8,
                right: 8,
                child: GestureDetector(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            IntegrationBrowserScreen(integration: integration),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      children: [
                        Text(
                          integration.emoji,
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          integration.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.open_in_new,
                          color: Colors.white54,
                          size: 12,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        )
        .animate()
        .fadeIn(duration: 400.ms)
        .slideY(begin: 0.1, end: 0, curve: Curves.easeOut);
  }
}

// ── Imagiya / CoDesign Image Bubble ────────────────────────────────────────────
class _ImagiyaImageBubble extends StatefulWidget {
  final String imageUrl;
  final Color providerColor;
  final String label;
  const _ImagiyaImageBubble({
    required this.imageUrl,
    required this.providerColor,
    this.label = 'IMAGIYA · AI Image',
  });

  @override
  State<_ImagiyaImageBubble> createState() => _ImagiyaImageBubbleState();
}

class _ImagiyaImageBubbleState extends State<_ImagiyaImageBubble> {
  bool _saving = false;

  Future<Uint8List> _getImageBytes() async {
    if (widget.imageUrl.startsWith('data:image/')) {
      final base64String = widget.imageUrl.split(',').last;
      return base64Decode(base64String);
    } else {
      final response = await http.get(Uri.parse(widget.imageUrl));
      if (response.statusCode != 200) {
        throw Exception('Server returned status code ${response.statusCode}');
      }
      return response.bodyBytes;
    }
  }

  Future<void> _downloadToGallery() async {
    if (widget.imageUrl.isEmpty) return;
    setState(() => _saving = true);
    try {
      final bytes = await _getImageBytes();
      await Gal.putImageBytes(
        bytes,
        name: 'jarvis_imagiya_${DateTime.now().millisecondsSinceEpoch}',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Image saved to gallery!'),
            backgroundColor: Color(0xFF22C55E),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _exportPdf() async {
    if (widget.imageUrl.isEmpty) return;
    try {
      final bytes = await _getImageBytes();
      final pdfDoc = pw.Document();
      final image = pw.MemoryImage(bytes);
      pdfDoc.addPage(
        pw.Page(
          build: (pw.Context context) {
            return pw.Center(child: pw.Image(image));
          },
        ),
      );
      final pdfBytes = await pdfDoc.save();
      final tempDir = await getTemporaryDirectory();
      final file = File(
        '${tempDir.path}/imagiya_image_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
      await file.writeAsBytes(pdfBytes, flush: true);
      await Share.shareXFiles([
        XFile(file.path, mimeType: 'application/pdf'),
      ], subject: 'JARVIS Imagiya PDF');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PDF Export failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.90,
            ),
            margin: const EdgeInsets.only(left: 16, right: 8, bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Provider badge
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: widget.providerColor,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        widget.label,
                        style: TextStyle(
                          color: widget.providerColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),
                // Image with rounded corners
                if (widget.imageUrl.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: widget.imageUrl.startsWith('data:image/')
                        ? Image.memory(
                            base64Decode(widget.imageUrl.split(',').last),
                            fit: BoxFit.contain,
                          )
                        : Image.network(
                            widget.imageUrl,
                            fit: BoxFit.contain,
                            loadingBuilder: (ctx, child, progress) {
                              if (progress == null) return child;
                              return Container(
                                height: 220,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1A1A2E),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      CircularProgressIndicator(
                                        value:
                                            progress.expectedTotalBytes != null
                                            ? progress.cumulativeBytesLoaded /
                                                  progress.expectedTotalBytes!
                                            : null,
                                        color: widget.providerColor,
                                        strokeWidth: 2,
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        'Generating image...',
                                        style: TextStyle(
                                          color: widget.providerColor
                                              .withValues(alpha: 0.7),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                            errorBuilder: (ctx, err, st) => Container(
                              height: 100,
                              decoration: BoxDecoration(
                                color: const Color(0xFF1A1A2E),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.broken_image_rounded,
                                  color: Colors.white30,
                                  size: 40,
                                ),
                              ),
                            ),
                          ),
                  ),
                const SizedBox(height: 10),
                // Action bar
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _ImageActionBtn(
                      icon: _saving
                          ? Icons.hourglass_top_rounded
                          : Icons.download_rounded,
                      label: _saving ? 'Saving...' : 'Download',
                      color: const Color(0xFF22C55E),
                      onTap: _saving ? null : _downloadToGallery,
                    ),
                    _ImageActionBtn(
                      icon: Icons.share_rounded,
                      label: 'Share',
                      color: widget.providerColor,
                      onTap: () => Share.share(
                        widget.imageUrl,
                        subject: 'JARVIS Imagiya Image',
                      ),
                    ),
                    _ImageActionBtn(
                      icon: Icons.picture_as_pdf_rounded,
                      label: 'PDF',
                      color: const Color(0xFFEF4444),
                      onTap: _exportPdf,
                    ),
                    _ImageActionBtn(
                      icon: Icons.copy_rounded,
                      label: 'Copy URL',
                      color: Colors.white54,
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: widget.imageUrl));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Image URL copied!'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        )
        .animate()
        .slideX(begin: -0.05, end: 0, duration: 200.ms, curve: Curves.easeOut)
        .fadeIn(duration: 150.ms);
  }
}

class _ImageActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  const _ImageActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── CoDesign Generating Pulse Bubble ──────────────────────────────────────────
class _CodesignGeneratingBubble extends StatelessWidget {
  const _CodesignGeneratingBubble();

  @override
  Widget build(BuildContext context) {
    const teal = Color(0xFF4DD0E1);
    return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(left: 16, right: 8, bottom: 16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF0D1117),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: teal.withValues(alpha: 0.25)),
              boxShadow: [
                BoxShadow(
                  color: teal.withValues(alpha: 0.08),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2, color: teal),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CoDesign',
                      style: TextStyle(
                        color: teal,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Crafting your UI...',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        )
        .animate()
        .fadeIn(duration: 300.ms)
        .shimmer(
          delay: 500.ms,
          duration: 1500.ms,
          color: teal.withValues(alpha: 0.08),
        );
  }
}

// ── CoDesign HTML WebView Bubble ───────────────────────────────────────────────
class _CodesignHtmlBubble extends StatefulWidget {
  final String htmlCode;
  const _CodesignHtmlBubble({required this.htmlCode});

  @override
  State<_CodesignHtmlBubble> createState() => _CodesignHtmlBubbleState();
}

class _CodesignHtmlBubbleState extends State<_CodesignHtmlBubble> {
  bool _isFullscreen = false;
  bool _codeCopied = false;
  InAppWebViewController? _webViewController;

  static const _teal = Color(0xFF4DD0E1);

  @override
  void didUpdateWidget(covariant _CodesignHtmlBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.htmlCode != widget.htmlCode) {
      _webViewController?.loadData(
        data: widget.htmlCode,
        mimeType: 'text/html',
        encoding: 'utf-8',
        baseUrl: WebUri('about:blank'),
      );
    }
  }

  void _copyHtmlCode() {
    Clipboard.setData(ClipboardData(text: widget.htmlCode));
    setState(() => _codeCopied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _codeCopied = false);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ HTML code copied!'),
        duration: Duration(seconds: 2),
        backgroundColor: Color(0xFF22C55E),
      ),
    );
  }

  Future<void> _shareHtml() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final file = File(
        '${tempDir.path}/codesign_jarvis_${DateTime.now().millisecondsSinceEpoch}.html',
      );
      await file.writeAsString(widget.htmlCode, flush: true);
      await Share.shareXFiles([
        XFile(file.path, mimeType: 'text/html'),
      ], subject: 'CoDesign by JARVIS');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Share failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _openInBrowser() async {
    final dataUrl =
        'data:text/html;charset=utf-8,${Uri.encodeComponent(widget.htmlCode)}';
    final uri = Uri.parse(dataUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _exportPdf() async {
    try {
      final pdfBytes = await Printing.convertHtml(
        html: widget.htmlCode,
        format: PdfPageFormat.a4,
      );
      final tempDir = await getTemporaryDirectory();
      final file = File(
        '${tempDir.path}/codesign_ui_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
      await file.writeAsBytes(pdfBytes, flush: true);
      await Share.shareXFiles([
        XFile(file.path, mimeType: 'application/pdf'),
      ], subject: 'JARVIS CoDesign PDF');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PDF Export failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _toggleFullscreen() {
    setState(() => _isFullscreen = !_isFullscreen);
    if (_isFullscreen) {
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (_) => Dialog.fullscreen(
          child: Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: const Color(0xFF0D1117),
              leading: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              title: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: _teal,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'CoDesign Preview',
                    style: TextStyle(
                      color: _teal,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.code, color: Colors.white70),
                  onPressed: () {
                    Navigator.pop(context);
                    _copyHtmlCode();
                  },
                ),
                const SizedBox(width: 8),
              ],
            ),
            body: _buildWebView(fullscreen: true),
          ),
        ),
      ).then((_) => setState(() => _isFullscreen = false));
    }
  }

  Widget _buildWebView({bool fullscreen = false}) {
    return InAppWebView(
      initialData: InAppWebViewInitialData(
        data: widget.htmlCode,
        mimeType: 'text/html',
        encoding: 'utf-8',
        baseUrl: WebUri('about:blank'),
      ),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        transparentBackground: true,
        supportZoom: fullscreen,
        domStorageEnabled: true,
        databaseEnabled: true,
        mediaPlaybackRequiresUserGesture: false,
        allowFileAccessFromFileURLs: true,
        allowUniversalAccessFromFileURLs: true,
      ),
      onWebViewCreated: (controller) {
        _webViewController = controller;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: screenWidth - 24,
            margin: const EdgeInsets.only(left: 16, right: 8, bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Provider badge
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: _teal,
                          boxShadow: [
                            BoxShadow(
                              color: Color(0x664DD0E1),
                              blurRadius: 8,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'CODESIGN · Live Preview',
                        style: TextStyle(
                          color: _teal,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: _toggleFullscreen,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _teal.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _teal.withValues(alpha: 0.3),
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.open_in_full_rounded,
                                color: _teal,
                                size: 11,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Expand',
                                style: TextStyle(
                                  color: _teal,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // WebView preview
                Container(
                  height: 380,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _teal.withValues(alpha: 0.2)),
                    boxShadow: [
                      BoxShadow(
                        color: _teal.withValues(alpha: 0.06),
                        blurRadius: 20,
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _buildWebView(),
                ),
                const SizedBox(height: 10),
                // Action bar
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _ImageActionBtn(
                      icon: Icons.open_in_full_rounded,
                      label: 'Fullscreen',
                      color: _teal,
                      onTap: _toggleFullscreen,
                    ),
                    _ImageActionBtn(
                      icon: _codeCopied
                          ? Icons.check_rounded
                          : Icons.code_rounded,
                      label: _codeCopied ? 'Copied!' : 'Copy HTML',
                      color: _codeCopied
                          ? const Color(0xFF22C55E)
                          : Colors.white70,
                      onTap: _copyHtmlCode,
                    ),
                    _ImageActionBtn(
                      icon: Icons.download_rounded,
                      label: 'Download HTML',
                      color: const Color(0xFF22C55E),
                      onTap: _shareHtml,
                    ),
                    _ImageActionBtn(
                      icon: Icons.share_rounded,
                      label: 'Share',
                      color: _teal,
                      onTap: _shareHtml,
                    ),
                    _ImageActionBtn(
                      icon: Icons.picture_as_pdf_rounded,
                      label: 'PDF',
                      color: const Color(0xFFEF4444),
                      onTap: _exportPdf,
                    ),
                    _ImageActionBtn(
                      icon: Icons.open_in_browser_rounded,
                      label: 'Browser',
                      color: Colors.white54,
                      onTap: _openInBrowser,
                    ),
                  ],
                ),
              ],
            ),
          ),
        )
        .animate()
        .slideX(begin: -0.05, end: 0, duration: 200.ms, curve: Curves.easeOut)
        .fadeIn(duration: 150.ms);
  }
}

class _UserBubble extends StatelessWidget {
  final Message message;
  const _UserBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    return Align(
          alignment: Alignment.centerRight,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78,
            ),
            margin: const EdgeInsets.only(left: 48, bottom: 12, right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              gradient: JarvisColors.primaryGradient,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(4),
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
              boxShadow: [
                BoxShadow(
                  color: JarvisColors.accentPrimary.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Text(
              message.content,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                height: 1.5,
              ),
            ),
          ),
        )
        .animate()
        .slideX(begin: 0.1, end: 0, duration: 200.ms, curve: Curves.easeOut)
        .fadeIn(duration: 150.ms);
  }
}

class _AIBubble extends StatelessWidget {
  final Message message;
  final Color providerColor;
  const _AIBubble({required this.message, required this.providerColor});

  @override
  Widget build(BuildContext context) {
    return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.98,
            ),
            margin: const EdgeInsets.only(right: 8, bottom: 16, left: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Provider badge
                if (message.provider != null || message.tokenCount != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: providerColor,
                            boxShadow: [
                              BoxShadow(
                                color: providerColor.withValues(alpha: 0.5),
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${message.provider?.toUpperCase() ?? 'JARVIS'}'
                          '${message.model != null ? " · ${message.model}" : ""}'
                          '${message.tokenCount != null ? " · ${message.tokenCount} tokens" : ""}',
                          style: TextStyle(
                            color: providerColor.withValues(alpha: 0.9),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                // ── JARVIS Intelligence Panel (live during streaming) ──
                if (message.isStreaming)
                  Consumer<ChatProvider>(
                    builder: (context, cp, _) {
                      if (cp.activeDnaModels.isEmpty &&
                          cp.activeContextualSkills.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      return _JarvisIntelligencePanel(
                        dnaModels: cp.activeDnaModels,
                        contextualSkills: cp.activeContextualSkills,
                        providerColor: providerColor,
                      );
                    },
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 8,
                  ),
                  decoration: const BoxDecoration(
                    // Remove fixed box decoration for an airy feel
                    color: Colors.transparent,
                  ),
                  child: message.content.isEmpty
                      ? _TypingIndicator()
                      : SelectionArea(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (message.content.contains(
                                '<!--JARVIS_DIAGRAM-->',
                              )) ...[
                                Builder(
                                  builder: (context) {
                                    final parts = message.content.split(
                                      '<!--JARVIS_DIAGRAM-->',
                                    );
                                    final textPart = parts[0].trim();
                                    final htmlPart = parts
                                        .sublist(1)
                                        .join('<!--JARVIS_DIAGRAM-->')
                                        .trim();
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (textPart.isNotEmpty)
                                          _buildMarkdown(context, textPart),
                                        if (htmlPart.isNotEmpty)
                                          message.isStreaming
                                              ? Container(
                                                  height: 160,
                                                  width: double.infinity,
                                                  margin: const EdgeInsets.only(
                                                    top: 8,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: const Color(
                                                      0xFF080810,
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          16,
                                                        ),
                                                    border: Border.all(
                                                      color:
                                                          JarvisColors.border,
                                                    ),
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: JarvisColors
                                                            .accentPrimary
                                                            .withValues(
                                                              alpha: 0.1,
                                                            ),
                                                        blurRadius: 10,
                                                        spreadRadius: 2,
                                                      ),
                                                    ],
                                                  ),
                                                  child: Column(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    children: [
                                                      const SizedBox(
                                                        width: 28,
                                                        height: 28,
                                                        child:
                                                            CircularProgressIndicator(
                                                              strokeWidth: 2.5,
                                                              color: JarvisColors
                                                                  .accentPrimary,
                                                            ),
                                                      ),
                                                      const SizedBox(
                                                        height: 16,
                                                      ),
                                                      Text(
                                                        'Crafting Diagram...',
                                                        style:
                                                            GoogleFonts.outfit(
                                                              color: JarvisColors
                                                                  .accentPrimary
                                                                  .withValues(
                                                                    alpha: 0.8,
                                                                  ),
                                                              fontSize: 13,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                              letterSpacing:
                                                                  0.5,
                                                            ),
                                                      ),
                                                    ],
                                                  ),
                                                )
                                              : _InlineDiagram(html: htmlPart),
                                      ],
                                    );
                                  },
                                ),
                              ] else ...[
                                _buildMarkdown(context, message.content),
                              ],
                              if (message.isStreaming) ...[
                                const SizedBox(height: 12),
                                _StreamingCursor(),
                              ] else ...[
                                const SizedBox(height: 12),
                                _buildActionRow(context),
                              ],
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
        )
        .animate()
        .slideX(begin: -0.05, end: 0, duration: 200.ms, curve: Curves.easeOut)
        .fadeIn(duration: 150.ms);
  }

  Widget _buildMarkdown(BuildContext context, String content) {
    return MarkdownBody(
      data: _cleanResponse(content),
      imageBuilder: (uri, title, alt) {
        final src = uri.toString();
        if (src.startsWith('data:image/')) {
          try {
            final b64 = src.split(',').last;
            if (b64.length % 4 != 0) {
              // incomplete base64 mid-stream — show lightweight placeholder, don't attempt decode
              return const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              );
            }
            return ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(base64Decode(b64), fit: BoxFit.contain),
            );
          } catch (_) {
            return const SizedBox(
              height: 100,
              child: Center(
                child: Icon(Icons.broken_image_rounded, color: Colors.white30),
              ),
            );
          }
        }
        return Image.network(
          src,
          errorBuilder: (ctx, err, st) =>
              const Icon(Icons.broken_image_rounded, color: Colors.white30),
        );
      },
      builders: {
        'latex': LatexElementBuilder(
          textStyle: TextStyle(color: JarvisColors.textPrimary),
          textScaleFactor: 1.1,
        ),
        'customtable': CustomTableBuilder(),
        'custommermaid': CustomMermaidBuilder(),
      },
      styleSheetTheme: MarkdownStyleSheetBaseTheme.cupertino,
      extensionSet: md.ExtensionSet(
        [
          LatexBlockSyntax(),
          const CustomTableSyntax(),
          const CustomMermaidSyntax(),
          ...md.ExtensionSet.gitHubFlavored.blockSyntaxes,
        ],
        [LatexInlineSyntax(), ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes],
      ),
      styleSheet: MarkdownStyleSheet(
        p: GoogleFonts.outfit(
          color: JarvisColors.textPrimary,
          fontSize: 15,
          height: 1.6,
        ),
        h2: GoogleFonts.outfit(
          color: JarvisColors.accentSecondary,
          fontSize: 18,
          fontWeight: FontWeight.bold,
          height: 2.0,
        ),
        h3: GoogleFonts.outfit(
          color: JarvisColors.accentPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          height: 1.8,
        ),
        strong: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
        listBullet: const TextStyle(color: JarvisColors.accentPrimary),
        tableHead: GoogleFonts.outfit(
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        tableBody: GoogleFonts.outfit(color: JarvisColors.textPrimary),
        tableBorder: TableBorder.all(color: JarvisColors.border, width: 1),
        blockquote: GoogleFonts.outfit(
          color: const Color(0xFFD0D0F0),
          fontSize: 14,
          fontStyle: FontStyle.italic,
          height: 1.5,
        ),
        blockquoteDecoration: BoxDecoration(
          color: const Color(0xFF161622),
          border: const Border(
            left: BorderSide(color: JarvisColors.accentPrimary, width: 4),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        blockquotePadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        code: GoogleFonts.firaCode(
          backgroundColor: Colors.black26,
          fontSize: 13,
          color: JarvisColors.accentPrimary,
        ),
        codeblockDecoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: JarvisColors.border),
        ),
        codeblockPadding: const EdgeInsets.all(12),
      ),
      onTapLink: (text, href, title) {
        if (href != null) launchUrl(Uri.parse(href));
      },
    );
  }

  Widget _buildActionRow(BuildContext context) {
    final isDiagram = message.content.contains('<!--JARVIS_DIAGRAM-->');
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _ActionButton(
          icon: Icons.copy_all_rounded,
          onTap: () {
            Clipboard.setData(
              ClipboardData(text: _getSharableContent(message.content)),
            );
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Clean content copied to clipboard!'),
                duration: Duration(seconds: 1),
                backgroundColor: JarvisColors.surfaceElevated,
              ),
            );
          },
          tooltip: 'Copy clean text',
        ),
        const SizedBox(width: 12),
        _ActionButton(
          icon: Icons.volume_up_rounded,
          onTap: () {
            context.read<ChatProvider>().ttsService.speak(
              _getSharableContent(message.content),
            );
          },
          tooltip: 'Speak',
        ),
        const SizedBox(width: 12),
        _ActionButton(
          icon: Icons.share_rounded,
          onTap: () {
            Share.share(
              _getSharableContent(message.content, includeDiagramCode: true),
            );
          },
          tooltip: 'Share response',
        ),
        const SizedBox(width: 12),
        JarvisPDFButton(
          responseText: _getSharableContent(
            message.content,
            includeDiagramCode: true,
          ),
        ),
        if (isDiagram) ...[
          const SizedBox(width: 12),
          _ActionButton(
            icon: Icons.download_rounded,
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Long-press the diagram to save it'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            tooltip: 'Save diagram',
          ),
        ],
      ],
    );
  }

  String _getSharableContent(
    String text, {
    bool includeDiagramCode = false,
    bool isForPdf = false,
  }) {
    String clean = text
        .replaceAll(RegExp(r'<SCHEDULE_REMINDER[^>]*>'), '')
        .replaceAll(RegExp(r'<CANCEL_REMINDER[^>]*>'), '')
        .replaceAll(RegExp(r'<SKIP_ROUTINE[^>]*>'), '')
        .replaceAll(RegExp(r'<WEB_SEARCH[^>]*>'), '')
        .replaceAll(RegExp(r'<UPDATE_ROUTINE[^>]*>'), '')
        .replaceAll(RegExp(r'<GENERATE_IMAGE[^>]*>'), '')
        .replaceAll(RegExp(r'<!--JARVIS_DIAGRAM-->'), '')
        .trim();

    // Fix for PDF/Sharing: Handle Mermaid diagrams gracefully
    if (!includeDiagramCode) {
      clean = clean.replaceAll(
        RegExp(r'```mermaid[\s\S]*?```'),
        '[Diagram Included]',
      );
      clean = clean.replaceAll(
        RegExp(r'<body[^>]*>[\s\S]*?</body>'),
        '[Diagram Content]',
      );
    }

    if (isForPdf) {
      // COMPREHENSIVE EMOJI STRIPPING: Standard PDF fonts don't support emojis, causing 'block' squares.
      clean = clean
          .replaceAll(RegExp(r'[\u{10000}-\u{10FFFF}]', unicode: true), '')
          .replaceAll(RegExp(r'[\u{2600}-\u{27BF}]', unicode: true), '')
          .replaceAll(RegExp(r'\*\*([^*]+)\*\*'), r'\1')
          .replaceAll(RegExp(r'\*([^*]+)\*'), r'\1')
          .replaceAll(RegExp(r'#{1,6}\s+'), '')
          .replaceAll(RegExp(r'\[([^\]]+)\]\(([^)]+)\)'), r'\1 (\2)');
    }

    return clean.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  String _cleanResponse(String text) {
    final clean = _getSharableContent(text, includeDiagramCode: true);
    final cleanTables = replaceMarkdownTables(clean);
    return replaceMermaidDiagrams(cleanTables);
  }
}

class _TypingIndicator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        return Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              child: const _PulseDot(),
            )
            .animate(
              delay: Duration(milliseconds: i * 150),
              onPlay: (c) => c.repeat(),
            )
            .fadeIn(duration: 400.ms)
            .then()
            .fadeOut(duration: 400.ms);
      }),
    );
  }
}

class _PulseDot extends StatelessWidget {
  const _PulseDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: JarvisColors.textMuted,
      ),
    );
  }
}

class _StreamingCursor extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
          width: 8,
          height: 16,
          decoration: BoxDecoration(
            color: JarvisColors.accentPrimary,
            borderRadius: BorderRadius.circular(2),
          ),
        )
        .animate(onPlay: (c) => c.repeat())
        .fadeIn(duration: 500.ms)
        .then()
        .fadeOut(duration: 500.ms);
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  const _ActionButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Icon(
          icon,
          size: 16,
          color: JarvisColors.textMuted.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}

class _InlineDiagram extends StatefulWidget {
  final String html;

  const _InlineDiagram({required this.html});

  @override
  State<_InlineDiagram> createState() => _InlineDiagramState();
}

class _InlineDiagramState extends State<_InlineDiagram> {
  double _height = 100.0;
  InAppWebViewController? _webViewController;
  bool _isLoaded = false;

  @override
  void didUpdateWidget(covariant _InlineDiagram oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.html != widget.html) {
      _webViewController?.loadData(
        data: widget.html,
        mimeType: 'text/html',
        encoding: 'utf-8',
        baseUrl: WebUri('about:blank'),
      );
    }
  }

  void _updateHeight() async {
    if (_webViewController != null) {
      final hStr = await _webViewController!.evaluateJavascript(
        source: "document.documentElement.scrollHeight;",
      );
      if (hStr != null && hStr.toString().isNotEmpty) {
        final double contentHeight = double.tryParse(hStr.toString()) ?? 100.0;
        if (contentHeight > _height && mounted) {
          setState(() {
            _height =
                contentHeight +
                40.0; // Adding a 40px buffer to entirely prevent clipping
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      height: _height,
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: JarvisColors.border),
        boxShadow: [
          BoxShadow(
            color: JarvisColors.accentPrimary.withValues(alpha: 0.1),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            InAppWebView(
              initialData: InAppWebViewInitialData(
                data: widget.html,
                mimeType: 'text/html',
                encoding: 'utf-8',
                baseUrl: WebUri('about:blank'),
              ),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                transparentBackground: true,
                disableHorizontalScroll: true,
                disableVerticalScroll:
                    true, // Native gesture scroll pass-through
                supportZoom: false,
              ),
              onWebViewCreated: (controller) {
                _webViewController = controller;
                controller.addJavaScriptHandler(
                  handlerName: 'heightChanged',
                  callback: (args) {
                    _updateHeight();
                  },
                );
              },
              onLoadStop: (controller, url) async {
                setState(() {
                  _isLoaded = true;
                });
                // Polling height evaluation to account for delayed async JS Mermaid rendering
                for (int i = 0; i < 5; i++) {
                  await Future.delayed(const Duration(milliseconds: 500));
                  _updateHeight();
                }
              },
            ),
            if (!_isLoaded)
              const Center(
                child: SizedBox(
                  width: 30,
                  height: 30,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: JarvisColors.accentPrimary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// JARVIS Intelligence Panel — Live thinking/skill display during generation
// ══════════════════════════════════════════════════════════════════════════════
class _JarvisIntelligencePanel extends StatefulWidget {
  final List<String> dnaModels;
  final List<String> contextualSkills;
  final Color providerColor;

  const _JarvisIntelligencePanel({
    required this.dnaModels,
    required this.contextualSkills,
    required this.providerColor,
  });

  @override
  State<_JarvisIntelligencePanel> createState() =>
      _JarvisIntelligencePanelState();
}

class _JarvisIntelligencePanelState extends State<_JarvisIntelligencePanel>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _rotateController;
  late AnimationController _thinkController;
  late Animation<double> _pulseAnim;
  late Animation<double> _rotateAnim;
  late Animation<double> _glowAnim;

  bool _expanded = false;
  int _thinkStep = 0;

  static const _thinkingSteps = [
    'Activating Model DNA...',
    'Loading elite capabilities...',
    'Scanning knowledge base...',
    'Selecting expert skills...',
    'Synthesizing intelligence...',
    'Composing response...',
  ];

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _glowAnim = Tween<double>(begin: 0.2, end: 0.6).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _rotateAnim = Tween<double>(begin: 0, end: 1).animate(_rotateController);

    _thinkController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 900),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed && mounted) {
            setState(
              () => _thinkStep = (_thinkStep + 1) % _thinkingSteps.length,
            );
            _thinkController.forward(from: 0);
          }
        });
    _thinkController.forward();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotateController.dispose();
    _thinkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalSkills =
        widget.dnaModels.length + widget.contextualSkills.length;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF080812),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF7C3AED).withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C3AED).withValues(alpha: 0.08),
            blurRadius: 20,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row: brain orb + status + expand toggle ──
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Row(
                children: [
                  // Animated brain orb
                  AnimatedBuilder(
                    animation: Listenable.merge([_pulseAnim, _rotateAnim]),
                    builder: (_, child) => Transform.scale(
                      scale: _pulseAnim.value,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: SweepGradient(
                            transform: GradientRotation(
                              _rotateAnim.value * 6.28,
                            ),
                            colors: const [
                              Color(0xFF7C3AED),
                              Color(0xFF06B6D4),
                              Color(0xFFFFD700),
                              Color(0xFF7C3AED),
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF7C3AED,
                              ).withValues(alpha: _glowAnim.value),
                              blurRadius: 12,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Text('🧠', style: TextStyle(fontSize: 13)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Thinking status text
                  Expanded(
                    child: AnimatedBuilder(
                      animation: _thinkController,
                      builder: (_, child) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'JARVIS Intelligence Engine',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.85),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.3,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF7C3AED,
                                  ).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: const Color(
                                      0xFF7C3AED,
                                    ).withValues(alpha: 0.4),
                                  ),
                                ),
                                child: Text(
                                  '$totalSkills ACTIVE',
                                  style: const TextStyle(
                                    color: Color(0xFFA78BFA),
                                    fontSize: 8,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _thinkingSteps[_thinkStep],
                            style: const TextStyle(
                              color: Color(0xFF7C3AED),
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Expand toggle
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 250),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Colors.white.withValues(alpha: 0.3),
                      size: 18,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Always visible: 7 Model DNA chips ──
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _dnaConfig.map((dna) {
                  return Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: dna.color.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: dna.color.withValues(alpha: 0.35),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              dna.emoji,
                              style: const TextStyle(fontSize: 11),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              dna.label,
                              style: TextStyle(
                                color: dna.color,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      )
                      .animate(onPlay: (c) => c.repeat(reverse: true))
                      .shimmer(
                        duration: 2000.ms,
                        color: dna.color.withValues(alpha: 0.15),
                      );
                }).toList(),
              ),
            ),
          ),

          // ── Expandable: contextual skills section ──
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            child: _expanded && widget.contextualSkills.isNotEmpty
                ? Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: Colors.white.withValues(alpha: 0.05),
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6, top: 2),
                          child: Row(
                            children: [
                              const Text('⚡ ', style: TextStyle(fontSize: 9)),
                              Text(
                                'CONTEXTUAL SKILLS (${widget.contextualSkills.length} matched)',
                                style: const TextStyle(
                                  color: Color(0xFF4ADE80),
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Wrap(
                          spacing: 5,
                          runSpacing: 5,
                          children: widget.contextualSkills.map((skillName) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF4ADE80,
                                ).withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(
                                    0xFF4ADE80,
                                  ).withValues(alpha: 0.2),
                                  width: 0.7,
                                ),
                              ),
                              child: Text(
                                skillName.length > 25
                                    ? '${skillName.substring(0, 25)}…'
                                    : skillName,
                                style: const TextStyle(
                                  color: Color(0xFF4ADE80),
                                  fontSize: 9,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),

          // ── Bottom: show/hide skills hint ──
          if (widget.contextualSkills.isNotEmpty)
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 5),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: Colors.white.withValues(alpha: 0.04),
                    ),
                  ),
                ),
                child: Center(
                  child: Text(
                    _expanded
                        ? '▲ Hide ${widget.contextualSkills.length} matched skills'
                        : '▼ Show ${widget.contextualSkills.length} matched skills',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.25),
                      fontSize: 9,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.1, end: 0);
  }
}

String replaceMermaidDiagrams(String text) {
  final regex = RegExp(r'```mermaid([\s\S]*?)```');
  return text.replaceAllMapped(regex, (match) {
    final mermaidCode = match.group(1)!.trim();
    final base64Str = base64Encode(utf8.encode(mermaidCode));
    return '<custommermaid data="$base64Str" />';
  });
}

class CustomMermaidSyntax extends md.BlockSyntax {
  @override
  RegExp get pattern => RegExp(r'^<custommermaid\s+data="([^"]+)"\s*/>');

  const CustomMermaidSyntax();

  @override
  md.Node? parse(md.BlockParser parser) {
    final match = pattern.firstMatch(parser.current.content);
    if (match == null) return null;
    final data = match.group(1)!;
    parser.advance();

    final element = md.Element('custommermaid', []);
    element.attributes['data'] = data;
    return element;
  }
}

class CustomMermaidBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final dataBase64 = element.attributes['data'];
    if (dataBase64 == null) return const SizedBox.shrink();

    try {
      final mermaidCode = utf8.decode(base64Decode(dataBase64));
      return _InlineMermaidDiagram(mermaidCode: mermaidCode);
    } catch (e) {
      debugPrint("Error parsing custom mermaid: $e");
      return const SizedBox.shrink();
    }
  }
}

class _InlineMermaidDiagram extends StatefulWidget {
  final String mermaidCode;

  const _InlineMermaidDiagram({required this.mermaidCode});

  @override
  State<_InlineMermaidDiagram> createState() => _InlineMermaidDiagramState();
}

class _InlineMermaidDiagramState extends State<_InlineMermaidDiagram> {
  double _height = 250.0;
  InAppWebViewController? _webViewController;
  bool _isLoaded = false;

  @override
  void didUpdateWidget(covariant _InlineMermaidDiagram oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mermaidCode != widget.mermaidCode) {
      final html = compileMermaidHtml(widget.mermaidCode);
      _webViewController?.loadData(
        data: html,
        mimeType: 'text/html',
        encoding: 'utf-8',
        baseUrl: WebUri('about:blank'),
      );
    }
  }

  void _updateHeight() async {
    if (_webViewController != null) {
      final hStr = await _webViewController!.evaluateJavascript(
        source: "document.documentElement.scrollHeight;",
      );
      if (hStr != null && hStr.toString().isNotEmpty) {
        final double contentHeight = double.tryParse(hStr.toString()) ?? 250.0;
        if (contentHeight > _height && mounted) {
          setState(() {
            _height = contentHeight + 40.0; // Buffer to prevent clipping
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final html = compileMermaidHtml(widget.mermaidCode);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      height: _height,
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF080810),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: JarvisColors.border),
        boxShadow: [
          BoxShadow(
            color: JarvisColors.accentPrimary.withValues(alpha: 0.1),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            InAppWebView(
              initialData: InAppWebViewInitialData(
                data: html,
                mimeType: 'text/html',
                encoding: 'utf-8',
                baseUrl: WebUri('about:blank'),
              ),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                transparentBackground: true,
                disableHorizontalScroll:
                    false, // Diagrams can scroll horizontally if large
                disableVerticalScroll: true,
                supportZoom: true,
              ),
              onWebViewCreated: (controller) {
                _webViewController = controller;
                controller.addJavaScriptHandler(
                  handlerName: 'heightChanged',
                  callback: (args) {
                    _updateHeight();
                  },
                );
              },
              onLoadStop: (controller, url) async {
                setState(() {
                  _isLoaded = true;
                });
                // Polling height evaluation to account for delayed async JS Mermaid rendering
                for (int i = 0; i < 5; i++) {
                  await Future.delayed(const Duration(milliseconds: 500));
                  _updateHeight();
                }
              },
            ),
            if (!_isLoaded)
              const Center(
                child: SizedBox(
                  width: 30,
                  height: 30,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: JarvisColors.accentPrimary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String compileMermaidHtml(String mermaidCode) {
  return '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <title>Mermaid Diagram</title>
  <style>
    @import url('https://fonts.googleapis.com/css2?family=Outfit:wght@300;400;500;600;700;800&display=swap');
    
    body {
      background-color: #080810;
      background-image: 
        linear-gradient(rgba(255, 255, 255, 0.02) 1px, transparent 1px),
        linear-gradient(90deg, rgba(255, 255, 255, 0.02) 1px, transparent 1px);
      background-size: 24px 24px;
      color: #EEEEFF;
      font-family: 'Outfit', sans-serif;
      margin: 0;
      padding: 16px;
      box-sizing: border-box;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      min-height: 100vh;
      overflow-x: auto;
    }
    
    #diagram-container {
      width: 100%;
      display: flex;
      justify-content: center;
      align-items: center;
      opacity: 0;
      transform: scale(0.95);
      animation: fadeInUp 0.6s cubic-bezier(0.16, 1, 0.3, 1) forwards;
    }

    .mermaid {
      font-family: 'Outfit', sans-serif !important;
    }

    /* Style Rectangles / Nodes */
    .node rect, .node circle, .node polygon, .node path {
      fill: rgba(18, 18, 30, 0.8) !important;
      stroke: #7C5CFC !important;
      stroke-width: 1.8px !important;
      filter: drop-shadow(0 0 8px rgba(124, 92, 252, 0.35)) !important;
      rx: 12px !important;
      ry: 12px !important;
    }

    .node:hover rect, .node:hover circle, .node:hover polygon, .node:hover path {
      fill: rgba(26, 26, 42, 0.9) !important;
      stroke: #00FFB4 !important;
      stroke-width: 2.2px !important;
      filter: drop-shadow(0 0 16px rgba(0, 255, 180, 0.6)) !important;
      cursor: pointer;
    }

    /* Text Labels */
    .node .label, .label {
      font-family: 'Outfit', sans-serif !important;
      color: #FFFFFF !important;
      font-weight: 600 !important;
      font-size: 13px !important;
      fill: #FFFFFF !important;
    }

    .node:hover .label {
      color: #00FFB4 !important;
      fill: #00FFB4 !important;
    }

    /* Edge Lines */
    .edgePath .path {
      stroke: #7C5CFC !important;
      stroke-width: 2.2px !important;
      filter: drop-shadow(0 0 5px rgba(124, 92, 252, 0.3)) !important;
    }

    .edgePath:hover .path {
      stroke: #00FFB4 !important;
      stroke-width: 3px !important;
      filter: drop-shadow(0 0 10px rgba(0, 255, 180, 0.5)) !important;
    }

    .edgeLabel rect {
      fill: #080810 !important;
      rx: 6px !important;
      ry: 6px !important;
    }

    .edgeLabel span {
      color: #9090B0 !important;
      font-size: 10px !important;
      font-weight: 600 !important;
    }

    /* Marker / Arrowhead */
    .marker, #arrowhead {
      fill: #7C5CFC !important;
    }
    
    .edgePath:hover .marker, .edgePath:hover #arrowhead {
      fill: #00FFB4 !important;
    }

    .edgePath .path {
      stroke-dasharray: 6;
      animation: dash 15s linear infinite;
    }
    
    @keyframes dash {
      to {
        stroke-dashoffset: -100;
      }
    }

    @keyframes fadeInUp {
      to {
        opacity: 1;
        transform: scale(1);
      }
    }
  </style>
  <script src="https://cdn.jsdelivr.net/npm/mermaid/dist/mermaid.min.js"></script>
</head>
<body>

  <div id="diagram-container">
    <pre class="mermaid">
$mermaidCode
    </pre>
  </div>

  <script>
    mermaid.initialize({
      startOnLoad: true,
      theme: 'dark',
      securityLevel: 'loose',
      themeVariables: {
        fontFamily: 'Outfit',
        primaryColor: '#12121e',
        primaryTextColor: '#fff',
        lineColor: '#7C5CFC',
      }
    });

    window.addEventListener('load', () => {
      setTimeout(() => {
        if (window.flutter_inappwebview) {
          window.flutter_inappwebview.callHandler('heightChanged');
        }
      }, 600);
    });
  </script>
</body>
</html>
  ''';
}

String replaceMarkdownTables(String text) {
  final lines = text.split('\n');
  final List<String> resultLines = [];
  List<String> currentTableLines = [];

  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.startsWith('|')) {
      currentTableLines.add(line);
    } else {
      if (currentTableLines.isNotEmpty) {
        bool hasSeparator = false;
        if (currentTableLines.length >= 2) {
          final secondLine = currentTableLines[1].trim();
          hasSeparator = secondLine.replaceAll(RegExp(r'[\s\-:|]'), '').isEmpty;
        }

        if (hasSeparator) {
          final jsonStr = jsonEncode(currentTableLines);
          final base64Str = base64Encode(utf8.encode(jsonStr));
          resultLines.add('<customtable data="$base64Str" />');
        } else {
          resultLines.addAll(currentTableLines);
        }
        currentTableLines = [];
      }
      resultLines.add(line);
    }
  }

  if (currentTableLines.isNotEmpty) {
    bool hasSeparator = false;
    if (currentTableLines.length >= 2) {
      final secondLine = currentTableLines[1].trim();
      hasSeparator = secondLine.replaceAll(RegExp(r'[\s\-:|]'), '').isEmpty;
    }
    if (hasSeparator) {
      final jsonStr = jsonEncode(currentTableLines);
      final base64Str = base64Encode(utf8.encode(jsonStr));
      resultLines.add('<customtable data="$base64Str" />');
    } else {
      resultLines.addAll(currentTableLines);
    }
  }

  return resultLines.join('\n');
}

class CustomTableSyntax extends md.BlockSyntax {
  @override
  RegExp get pattern => RegExp(r'^<customtable\s+data="([^"]+)"\s*/>');

  const CustomTableSyntax();

  @override
  md.Node? parse(md.BlockParser parser) {
    final match = pattern.firstMatch(parser.current.content);
    if (match == null) return null;
    final data = match.group(1)!;
    parser.advance();

    final element = md.Element('customtable', []);
    element.attributes['data'] = data;
    return element;
  }
}

class CustomTableBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final dataBase64 = element.attributes['data'];
    if (dataBase64 == null) return const SizedBox.shrink();

    try {
      final jsonStr = utf8.decode(base64Decode(dataBase64));
      final List<dynamic> tableLinesDynamic = jsonDecode(jsonStr);
      final List<String> tableLines = tableLinesDynamic.cast<String>();

      if (tableLines.length < 2) return const SizedBox.shrink();

      final List<TableRow> tableRows = [];

      List<String> parseRowCells(String line) {
        final cells = line.split('|');
        if (cells.isNotEmpty && cells.first.trim().isEmpty) cells.removeAt(0);
        if (cells.isNotEmpty && cells.last.trim().isEmpty) cells.removeLast();
        return cells.map((c) => c.trim()).toList();
      }

      final headers = parseRowCells(tableLines[0]);

      // Header row
      tableRows.add(
        TableRow(
          decoration: const BoxDecoration(color: Color(0xFF161626)),
          children: headers.map((headerText) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Text(
                headerText,
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            );
          }).toList(),
        ),
      );

      // Body rows
      for (int i = 2; i < tableLines.length; i++) {
        final cells = parseRowCells(tableLines[i]);
        if (cells.isEmpty) continue;

        if (cells.length > headers.length) {
          cells.removeRange(headers.length, cells.length);
        } else {
          while (cells.length < headers.length) {
            cells.add('');
          }
        }

        tableRows.add(
          TableRow(
            decoration: BoxDecoration(
              color: i % 2 == 0
                  ? const Color(0xFF0F0F17)
                  : const Color(0xFF14141F),
            ),
            children: cells.map((cellText) {
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Text(
                  cellText,
                  style: GoogleFonts.outfit(
                    color: const Color(0xFFEEEEFF),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              );
            }).toList(),
          ),
        );
      }

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12.0),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: JarvisColors.border, width: 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Table(
              defaultColumnWidth: const FixedColumnWidth(150.0),
              border: TableBorder(
                horizontalInside: BorderSide(
                  color: JarvisColors.border.withValues(alpha: 0.6),
                  width: 0.8,
                ),
                verticalInside: BorderSide(
                  color: JarvisColors.border.withValues(alpha: 0.6),
                  width: 0.8,
                ),
              ),
              children: tableRows,
            ),
          ),
        ),
      );
    } catch (e) {
      debugPrint("Error parsing custom table: $e");
      try {
        final jsonStr = utf8.decode(base64Decode(dataBase64));
        final List<dynamic> tableLinesDynamic = jsonDecode(jsonStr);
        final List<String> tableLines = tableLinesDynamic.cast<String>();
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF161622),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: JarvisColors.border),
          ),
          child: Text(
            tableLines.join('\n'),
            style: GoogleFonts.firaCode(
              color: JarvisColors.textPrimary,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        );
      } catch (_) {
        return const SizedBox.shrink();
      }
    }
  }
}
