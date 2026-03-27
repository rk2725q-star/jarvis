import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:jarvis_ai/features/chat/chat_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import '../../theme/jarvis_theme.dart';
import '../../models/message.dart';

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
      return _UserBubble(message: message);
    } else {
      return _AIBubble(message: message, providerColor: _providerColor(message.provider));
    }
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
        margin: const EdgeInsets.only(left: 48, bottom: 12),
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
        margin: const EdgeInsets.only(right: 8, bottom: 16),
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
        _ActionButton(
          icon: Icons.picture_as_pdf_rounded,
          onTap: () => _downloadPdf(context),
          tooltip: 'Download as PDF',
        ),
      ],
    );
  }

  Future<void> _downloadPdf(BuildContext context) async {
    final pdf = pw.Document();
    
    // FETCH TAMIL FONT: To fix the "tofu" (boxes) in the PDF, we dynamically load a TTF that supports Tamil characters.
    // If the download fails, it will fall back to a built-in font.
    pw.Font? tamilFont;
    try {
      final response = await http.get(Uri.parse('https://github.com/googlefonts/noto-fonts/raw/main/hinted/ttf/NotoSansTamil/NotoSansTamil-Regular.ttf'));
      if (response.statusCode == 200) {
        tamilFont = pw.Font.ttf(response.bodyBytes.buffer.asByteData());
      }
    } catch (e) {
      debugPrint('Font fetch error: $e');
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Text('JARVIS - Intelligent AI Assistant', 
                style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)
              ),
            ),
            pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 8)),
            pw.Text(
              _getSharableContent(message.content, isForPdf: true),
              style: pw.TextStyle(
                font: tamilFont ?? pw.Font.courier(),
                fontSize: 10,
                lineSpacing: 1.5,
                color: PdfColors.black,
              ),
            ),
            pw.Footer(
              padding: const pw.EdgeInsets.only(top: 24),
              trailing: pw.Text('Generated by JARVIS AI OS', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
            ),
          ];
        },
      ),
    );

    try {
      Directory? dir;
      if (Platform.isAndroid) {
        dir = Directory('/storage/emulated/0/Download');
        if (!dir.existsSync()) {
          dir = await getExternalStorageDirectory();
        }
      } else {
        dir = await getApplicationDocumentsDirectory();
      }
      
      final fileName = 'jarvis_response_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final file = File('${dir?.path}/$fileName');
      await file.writeAsBytes(await pdf.save());
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_outline, color: JarvisColors.success),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'PDF Generated Successfully!',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      Text(
                        fileName,
                        style: const TextStyle(fontSize: 11, color: JarvisColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            backgroundColor: JarvisColors.surfaceHighlight,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: JarvisColors.accentPrimary, width: 1),
            ),
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'SHARE',
              textColor: JarvisColors.accentSecondary,
              onPressed: () => Share.shareXFiles([XFile(file.path)]),
            )
          )
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save PDF: $e'),
            backgroundColor: Colors.redAccent,
          )
        );
      }
    }
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
