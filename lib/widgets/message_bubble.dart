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
import '../../features/integrations/integrations_model.dart';
import '../../features/integrations/integration_browser_screen.dart';
import 'jarvis_pdf_button.dart';

class MessageBubble extends StatelessWidget {
  final Message message;

  const MessageBubble({super.key, required this.message});

  Color _providerColor(String? provider) {
    switch (provider?.toLowerCase()) {
      case 'gemini': return JarvisColors.geminiColor;
      case 'ollama': return JarvisColors.ollamaColor;
      case 'nvidia': return JarvisColors.nvidiaColor;
      case 'deepseek': return JarvisColors.deepseekColor;
      case 'local': return JarvisColors.localColor;
      default: return JarvisColors.accentPrimary;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (message.isUser) {
      if (message.provider != null && message.provider!.isNotEmpty &&
          message.provider != 'imagiya' && message.provider != 'codesign') {
        return Column(
          children: [
            _UserBubble(message: message),
            _InlineIntegrationBrowser(integrationId: message.provider!, query: message.content),
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
    } else if (IntegrationCardBubble.isIntegrationCard(message.content)) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12, left: 16, right: 16),
        child: IntegrationCardBubble(rawContent: message.content),
      );
    } else {
      return _AIBubble(message: message, providerColor: _providerColor(message.provider));
    }
  }
}

class _InlineIntegrationBrowser extends StatefulWidget {
  final String integrationId;
  final String query;

  const _InlineIntegrationBrowser({required this.integrationId, required this.query});

  @override
  State<_InlineIntegrationBrowser> createState() => _InlineIntegrationBrowserState();
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
                ? Color(integration.gradientColors.first).withValues(alpha: 0.1)
                : Colors.black26,
            blurRadius: 20,
          )
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(launchUrl)),
            gestureRecognizers: {
              Factory<VerticalDragGestureRecognizer>(() => VerticalDragGestureRecognizer()),
              Factory<HorizontalDragGestureRecognizer>(() => HorizontalDragGestureRecognizer()),
              Factory<ScaleGestureRecognizer>(() => ScaleGestureRecognizer()),
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
                String query = widget.query.replaceAll('"', '\\"').replaceAll('\n', '\\n');
                String script = '''
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
                  MaterialPageRoute(builder: (_) => IntegrationBrowserScreen(integration: integration)),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: [
                    Text(integration.emoji, style: const TextStyle(fontSize: 14)),
                    const SizedBox(width: 6),
                    Text(integration.name, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 4),
                    const Icon(Icons.open_in_new, color: Colors.white54, size: 12),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0, curve: Curves.easeOut);
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

  Future<void> _downloadToGallery() async {
    if (widget.imageUrl.isEmpty) return;
    setState(() => _saving = true);
    try {
      final response = await http.get(Uri.parse(widget.imageUrl));
      if (response.statusCode == 200) {
        await Gal.putImageBytes(response.bodyBytes, name: 'jarvis_imagiya_${DateTime.now().millisecondsSinceEpoch}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Image saved to gallery!'), backgroundColor: Color(0xFF22C55E)),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.90),
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
                  Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: widget.providerColor)),
                  const SizedBox(width: 8),
                  Text(widget.label, style: TextStyle(color: widget.providerColor, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.0)),
                ],
              ),
            ),
            // Image with rounded corners
            if (widget.imageUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(
                  widget.imageUrl,
                  fit: BoxFit.contain,
                  loadingBuilder: (ctx, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      height: 220,
                      decoration: BoxDecoration(color: const Color(0xFF1A1A2E), borderRadius: BorderRadius.circular(16)),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(
                              value: progress.expectedTotalBytes != null
                                  ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                                  : null,
                              color: widget.providerColor,
                              strokeWidth: 2,
                            ),
                            const SizedBox(height: 12),
                            Text('Generating image...', style: TextStyle(color: widget.providerColor.withValues(alpha: 0.7), fontSize: 12)),
                          ],
                        ),
                      ),
                    );
                  },
                  errorBuilder: (ctx, err, st) => Container(
                    height: 100,
                    decoration: BoxDecoration(color: const Color(0xFF1A1A2E), borderRadius: BorderRadius.circular(16)),
                    child: const Center(child: Icon(Icons.broken_image_rounded, color: Colors.white30, size: 40)),
                  ),
                ),
              ),
            const SizedBox(height: 10),
            // Action bar
            Row(
              children: [
                _ImageActionBtn(
                  icon: _saving ? Icons.hourglass_top_rounded : Icons.download_rounded,
                  label: _saving ? 'Saving...' : 'Download',
                  color: const Color(0xFF22C55E),
                  onTap: _saving ? null : _downloadToGallery,
                ),
                const SizedBox(width: 8),
                _ImageActionBtn(
                  icon: Icons.share_rounded,
                  label: 'Share',
                  color: widget.providerColor,
                  onTap: () => Share.share(widget.imageUrl, subject: 'JARVIS Imagiya Image'),
                ),
                const SizedBox(width: 8),
                _ImageActionBtn(
                  icon: Icons.copy_rounded,
                  label: 'Copy URL',
                  color: Colors.white54,
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: widget.imageUrl));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Image URL copied!'), duration: Duration(seconds: 1)),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    ).animate().slideX(begin: -0.05, end: 0, duration: 200.ms, curve: Curves.easeOut).fadeIn(duration: 150.ms);
  }
}

class _ImageActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  const _ImageActionBtn({required this.icon, required this.label, required this.color, this.onTap});

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
            Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
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
          boxShadow: [BoxShadow(color: teal.withValues(alpha: 0.08), blurRadius: 20, spreadRadius: 2)],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 28, height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2, color: teal,
              ),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('CoDesign', style: TextStyle(color: teal, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
                const SizedBox(height: 2),
                Text('Crafting your UI...', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13)),
              ],
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 300.ms).shimmer(delay: 500.ms, duration: 1500.ms, color: teal.withValues(alpha: 0.08));
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

  static const _teal = Color(0xFF4DD0E1);

  void _copyHtmlCode() {
    Clipboard.setData(ClipboardData(text: widget.htmlCode));
    setState(() => _codeCopied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _codeCopied = false);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅ HTML code copied!'), duration: Duration(seconds: 2), backgroundColor: Color(0xFF22C55E)),
    );
  }

  Future<void> _shareHtml() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/codesign_jarvis_${DateTime.now().millisecondsSinceEpoch}.html');
      await file.writeAsString(widget.htmlCode, flush: true);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/html')],
        subject: 'CoDesign by JARVIS',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Share failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _openInBrowser() async {
    final dataUrl = 'data:text/html;charset=utf-8,${Uri.encodeComponent(widget.htmlCode)}';
    final uri = Uri.parse(dataUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
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
              title: Row(children: [
                Container(width: 8, height: 8, decoration: const BoxDecoration(shape: BoxShape.circle, color: _teal)),
                const SizedBox(width: 8),
                const Text('CoDesign Preview', style: TextStyle(color: _teal, fontSize: 13, fontWeight: FontWeight.w700)),
              ]),
              actions: [
                IconButton(icon: const Icon(Icons.code, color: Colors.white70), onPressed: () { Navigator.pop(context); _copyHtmlCode(); }),
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
        transparentBackground: false,
        supportZoom: fullscreen,
        domStorageEnabled: true,
        databaseEnabled: true,
        mediaPlaybackRequiresUserGesture: false,
        allowFileAccessFromFileURLs: true,
        allowUniversalAccessFromFileURLs: true,
      ),
      onWebViewCreated: (_) {},
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
                    width: 8, height: 8,
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: _teal,
                      boxShadow: [BoxShadow(color: Color(0x664DD0E1), blurRadius: 8, spreadRadius: 1)],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('CODESIGN · Live Preview', style: TextStyle(color: _teal, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.0)),
                  const Spacer(),
                  GestureDetector(
                    onTap: _toggleFullscreen,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _teal.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _teal.withValues(alpha: 0.3)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.open_in_full_rounded, color: _teal, size: 11),
                          SizedBox(width: 4),
                          Text('Expand', style: TextStyle(color: _teal, fontSize: 10, fontWeight: FontWeight.w600)),
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
                boxShadow: [BoxShadow(color: _teal.withValues(alpha: 0.06), blurRadius: 20)],
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
                  icon: _codeCopied ? Icons.check_rounded : Icons.code_rounded,
                  label: _codeCopied ? 'Copied!' : 'Copy HTML',
                  color: _codeCopied ? const Color(0xFF22C55E) : Colors.white70,
                  onTap: _copyHtmlCode,
                ),
                _ImageActionBtn(
                  icon: Icons.share_rounded,
                  label: 'Share',
                  color: _teal,
                  onTap: _shareHtml,
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
    ).animate().slideX(begin: -0.05, end: 0, duration: 200.ms, curve: Curves.easeOut).fadeIn(duration: 150.ms);
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
    ).animate().slideX(
      begin: 0.1,
      end: 0,
      duration: 200.ms,
      curve: Curves.easeOut,
    ).fadeIn(duration: 150.ms);
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
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
                          if (message.content.startsWith('<!--JARVIS_DIAGRAM-->')) ...[
                            _InlineDiagram(html: message.content.replaceFirst('<!--JARVIS_DIAGRAM-->\n', '')),
                          ] else ...[
                            MarkdownBody(
                              data: _cleanResponse(message.content),
                              builders: {
                                'latex': LatexElementBuilder(
                                  textStyle: TextStyle(color: JarvisColors.textPrimary),
                                  textScaleFactor: 1.1,
                                ),
                              },
                              extensionSet: md.ExtensionSet(
                                [LatexBlockSyntax(), ...md.ExtensionSet.gitHubFlavored.blockSyntaxes],
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
                                listBullet: const TextStyle(
                                  color: JarvisColors.accentPrimary,
                                ),
                                tableHead: GoogleFonts.outfit(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                                tableBody: GoogleFonts.outfit(
                                  color: JarvisColors.textPrimary,
                                ),
                                tableBorder: TableBorder.all(
                                  color: JarvisColors.border,
                                  width: 1,
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
                              ),
                              onTapLink: (text, href, title) {
                                if (href != null) launchUrl(Uri.parse(href));
                              },
                            ),
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
    ).animate().slideX(
      begin: -0.05,
      end: 0,
      duration: 200.ms,
      curve: Curves.easeOut,
    ).fadeIn(duration: 150.ms);
  }

  Widget _buildActionRow(BuildContext context) {
    final isDiagram = message.content.startsWith('<!--JARVIS_DIAGRAM-->');
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _ActionButton(
          icon: Icons.copy_all_rounded,
          onTap: () {
            Clipboard.setData(ClipboardData(text: _getSharableContent(message.content)));
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
            context.read<ChatProvider>().ttsService.speak(_getSharableContent(message.content));
          },
          tooltip: 'Speak',
        ),
        const SizedBox(width: 12),
        _ActionButton(
          icon: Icons.share_rounded,
          onTap: () {
            Share.share(_getSharableContent(message.content, includeDiagramCode: true));
          },
          tooltip: 'Share response',
        ),
        const SizedBox(width: 12),
        JarvisPDFButton(
          responseText: _getSharableContent(message.content, includeDiagramCode: true),
        ),
        if (isDiagram) ...[
          const SizedBox(width: 12),
          _ActionButton(
            icon: Icons.download_rounded,
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Long-press the diagram to save it'), duration: Duration(seconds: 2)),
              );
            },
            tooltip: 'Save diagram',
          ),
        ],
      ],
    );
  }



  String _getSharableContent(String text, {bool includeDiagramCode = false, bool isForPdf = false}) {
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
      clean = clean.replaceAll(RegExp(r'```mermaid[\s\S]*?```'), '[Diagram Included]');
      clean = clean.replaceAll(RegExp(r'<body[^>]*>[\s\S]*?</body>'), '[Diagram Content]');
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
    return _getSharableContent(text, includeDiagramCode: true);
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
        ).animate(delay: Duration(milliseconds: i * 150), onPlay: (c) => c.repeat())
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
    ).animate(onPlay: (c) => c.repeat()).fadeIn(duration: 500.ms)
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

  void _updateHeight() async {
    if (_webViewController != null) {
      final hStr = await _webViewController!.evaluateJavascript(source: "document.documentElement.scrollHeight;");
      if (hStr != null && hStr.toString().isNotEmpty) {
        final double contentHeight = double.tryParse(hStr.toString()) ?? 100.0;
        if (contentHeight > _height && mounted) {
          setState(() {
            _height = contentHeight + 40.0; // Adding a 40px buffer to entirely prevent clipping
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final base64Html = base64Encode(utf8.encode(widget.html));
    final dataUri = 'data:text/html;charset=utf-8;base64,$base64Html';

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
              initialUrlRequest: URLRequest(url: WebUri(dataUri)),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                transparentBackground: true,
                disableHorizontalScroll: true,
                disableVerticalScroll: true, // Native gesture scroll pass-through
                supportZoom: false,
              ),
              onWebViewCreated: (controller) {
                _webViewController = controller;
              },
              onLoadStop: (controller, url) async {
                setState(() { _isLoaded = true; });
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
                   width: 30, height: 30,
                   child: CircularProgressIndicator(strokeWidth: 2, color: JarvisColors.accentPrimary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
