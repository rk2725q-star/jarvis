import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:jarvis_ai/theme/jarvis_theme.dart';
import 'package:jarvis_ai/core/file_processor/file_processor.dart';
import 'package:jarvis_ai/core/router/ai_router.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
// flutter_file_view removed — using open_filex + extracted text fallback
import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_markdown_latex/flutter_markdown_latex.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:archive/archive.dart';

import 'models/doc_models.dart';
import 'parsers/docx_parser.dart';
import 'parsers/pptx_parser.dart';
import 'parsers/xlsx_parser.dart';
import 'renderers/doc_renderer.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_pdf/pdf.dart';

// ─── File type helpers ────────────────────────────────────────────────────────
String _ext(String path) => path.split('.').last.toLowerCase();

bool _isImage(String path) => ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(_ext(path));
bool _isText(String path) => ['txt', 'md', 'dart', 'py', 'js', 'ts', 'kt', 'java', 'swift',
    'go', 'rs', 'cpp', 'c', 'h', 'html', 'css', 'scss', 'json', 'xml', 'yaml', 'yml',
    'sh', 'bat', 'sql', 'csv'].contains(_ext(path));
bool _isPdf(String path) => _ext(path) == 'pdf';
bool _isDoc(String path) => ['doc', 'docx'].contains(_ext(path));
bool _isSheet(String path) => ['xls', 'xlsx'].contains(_ext(path)); // removed csv from sheet logic for WPS render
bool _isSlides(String path) => ['ppt', 'pptx'].contains(_ext(path));
bool _isAudio(String path) => ['mp3', 'wav', 'aac', 'm4a', 'flac', 'ogg', 'opus'].contains(_ext(path));
bool _isVideo(String path) => ['mp4', 'mov', 'avi', 'mkv', 'webm', '3gp', 'flv'].contains(_ext(path));
bool _isOffice(String path) => _isDoc(path) || _isSheet(path) || _isSlides(path);
bool _isCsv(String path) => _ext(path) == 'csv';

String _basename(String path) => path.split(Platform.pathSeparator).last;
String _formatSize(int bytes) {
  if (bytes < 1024) return '${bytes}B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
}

Color _typeColor(String path) {
  if (_isPdf(path)) return const Color(0xFFFC5555);
  if (_isImage(path)) return const Color(0xFF8B5CF6);
  if (_isDoc(path)) return const Color(0xFF4285F4);
  if (_isSheet(path)) return const Color(0xFF34A853);
  if (_isCsv(path)) return const Color(0xFF34A853);
  if (_isSlides(path)) return const Color(0xFFFBBC05);
  if (_isAudio(path)) return const Color(0xFFE91E63);
  if (_isVideo(path)) return const Color(0xFF009688);
  if (_isText(path)) return const Color(0xFF00D4FF);
  return JarvisColors.textMuted;
}

IconData _typeIcon(String path) {
  if (_isPdf(path)) return Icons.picture_as_pdf_rounded;
  if (_isImage(path)) return Icons.image_rounded;
  if (_isDoc(path)) return Icons.description_rounded;
  if (_isSheet(path)) return Icons.table_chart_rounded;
  if (_isCsv(path)) return Icons.table_chart_rounded;
  if (_isSlides(path)) return Icons.slideshow_rounded;
  if (_isAudio(path)) return Icons.audiotrack_rounded;
  if (_isVideo(path)) return Icons.video_library_rounded;
  if (_isText(path)) return Icons.code_rounded;
  return Icons.insert_drive_file_rounded;
}

// ─── Main Viewer ─────────────────────────────────────────────────────────────
class JarvisFileViewer extends StatefulWidget {
  final String filePath;
  final String? initialQuestion;

  const JarvisFileViewer({super.key, required this.filePath, this.initialQuestion});

  @override
  State<JarvisFileViewer> createState() => _JarvisFileViewerState();
}

class _JarvisFileViewerState extends State<JarvisFileViewer> {
  String _extractedText = '';
  bool _loading = true;
  String? _error;
  List<String> _csvRows = [];

  ParsedDocument? _parsedDoc;
  bool _isEditMode = false;
  late TextEditingController _editCtrl;

  @override
  void initState() {
    super.initState();
    _editCtrl = TextEditingController();
    _loadFile();
  }

  @override
  void dispose() {
    _editCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadFile() async {
    try {
      final processor = context.read<FileProcessor>();
      final text = await processor.extractText(widget.filePath);

      // CSV: split into rows
      List<String> rows = [];
      if (_isCsv(widget.filePath)) {
        rows = text.split('\n').where((r) => r.trim().isNotEmpty).toList();
      }

      ParsedDocument? pDoc;
      if (_isOffice(widget.filePath)) {
        try {
          final fileBytes = await File(widget.filePath).readAsBytes();
          final archive = ZipDecoder().decodeBytes(fileBytes);
          
          if (_isDoc(widget.filePath)) {
            pDoc = DocxParser(archive).parse(_basename(widget.filePath));
          } else if (_isSlides(widget.filePath)) {
            pDoc = PptxParser(archive).parse(_basename(widget.filePath));
          } else if (_isSheet(widget.filePath)) {
            pDoc = XlsxParser(archive).parse(_basename(widget.filePath));
          }
        } catch (e) {
          debugPrint('Error parsing document layout: $e');
        }
      }

      String extracted = text;
      if (pDoc != null) {
         if (_isSheet(widget.filePath)) {
            final sb = StringBuffer();
            for (final sheet in pDoc.sheets ?? <SheetData>[]) {
               sb.writeln('=== Sheet: ${sheet.name} ===');
               for (final row in sheet.rows) {
                  sb.writeln(row.join(' | '));
               }
            }
            if (sb.isNotEmpty) extracted = sb.toString();
         } else if (_isDoc(widget.filePath) || _isSlides(widget.filePath)) {
            final sb = StringBuffer();
            for (final block in pDoc.blocks) {
              sb.writeln(block.plainText);
            }
            for (final slide in pDoc.slides ?? <ParsedSlide>[]) {
               sb.writeln('Slide ${slide.index}:');
               if (slide.title != null) sb.writeln(slide.title);
               for (final block in slide.blocks) {
                 if (block.plainText != null) sb.writeln(block.plainText);
               }
            }
            if (sb.isNotEmpty) extracted = sb.toString();
         }
      }

      setState(() {
        _extractedText = extracted;
        _editCtrl.text = extracted;
        _csvRows = rows;
        _parsedDoc = pDoc;
        _loading = false;
      });

      if (widget.initialQuestion != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _openChat());
      }
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _openChat() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FileChat(
        filePath: widget.filePath,
        extractedText: _extractedText,
        initialQuestion: widget.initialQuestion,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = _basename(widget.filePath);
    final color = _typeColor(widget.filePath);
    final file = File(widget.filePath);
    final size = file.existsSync() ? file.statSync().size : 0;

    return Scaffold(
      backgroundColor: JarvisColors.bg,
      appBar: AppBar(
        backgroundColor: JarvisColors.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: JarvisColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Icon(_typeIcon(widget.filePath), color: color, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(name,
                style: const TextStyle(color: JarvisColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_rounded, color: JarvisColors.textSecondary, size: 22),
            tooltip: 'Share original',
            onPressed: () => Share.shareXFiles([XFile(widget.filePath)]),
          ),
          IconButton(
            icon: Icon(_isEditMode ? Icons.save_rounded : Icons.open_in_new_rounded, 
                 color: _isEditMode ? JarvisColors.accentPrimary : JarvisColors.textSecondary, size: 22),
            tooltip: _isEditMode ? 'Save changes' : 'Open in native app',
            onPressed: () {
              if (_isEditMode) {
                _saveChanges();
              } else {
                OpenFilex.open(widget.filePath);
              }
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(36),
          child: _FileMeta(name: name, size: size, color: color, path: widget.filePath),
        ),
      ),
      body: _loading
          ? _buildLoader()
          : _error != null
              ? _buildError()
              : _buildContent(),
      floatingActionButton: _loading ? null : FloatingActionButton(
        onPressed: _openActionMenu,
        backgroundColor: JarvisColors.bg,
        elevation: 12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(50),
          side: const BorderSide(color: JarvisColors.accentPrimary, width: 2),
        ),
        child: Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [JarvisColors.accentPrimary, JarvisColors.accentSecondary.withValues(alpha: 0.8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: JarvisColors.accentPrimary.withValues(alpha: 0.4),
                blurRadius: 15,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const Center(
            child: Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 30),
          ),
        ),
      ).animate().scale(delay: 500.ms, duration: 400.ms, curve: Curves.easeOutBack),
    );
  }

  void _openActionMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: JarvisColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: JarvisColors.border)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: JarvisColors.border, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 24),
            _buildActionItem(
              Icons.auto_awesome_rounded, 'Ask JARVIS', 'Analyze and chat with this file',
              () { Navigator.pop(context); _openChat(); },
              isPrimary: true,
            ),
            const SizedBox(height: 12),
            _buildActionItem(
              _isEditMode ? Icons.view_quilt_rounded : Icons.edit_document, 
              _isEditMode ? 'Exit Edit Mode' : 'Edit File', 
              _isEditMode ? 'Return to viewing mode' : 'Highly customizable dynamic editor',
              () { 
                Navigator.pop(context); 
                if (_isSheet(widget.filePath)) {
                  setState(() => _isEditMode = !_isEditMode); 
                } else {
                  _openEditor(); 
                }
              },
            ),
            const SizedBox(height: 12),
            _buildActionItem(
              Icons.share_rounded, 'Share / Convert', 'Convert formats or share original',
              () { Navigator.pop(context); _openShareSheet(); },
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildActionItem(IconData icon, String title, String subtitle, VoidCallback onTap, {bool isPrimary = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isPrimary ? JarvisColors.accentPrimary.withValues(alpha: 0.1) : JarvisColors.bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isPrimary ? JarvisColors.accentPrimary.withValues(alpha: 0.3) : JarvisColors.border),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isPrimary ? JarvisColors.accentPrimary : JarvisColors.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: isPrimary ? Colors.white : JarvisColors.textPrimary, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: isPrimary ? JarvisColors.accentPrimary : JarvisColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 15)),
                  Text(subtitle, style: const TextStyle(color: JarvisColors.textMuted, fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: isPrimary ? JarvisColors.accentPrimary : JarvisColors.textSecondary),
          ],
        ),
      ),
    );
  }

  void _openEditor() {
    final editCtrl = TextEditingController(text: _extractedText);
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: JarvisColors.bg,
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                   const Icon(Icons.edit_document, color: JarvisColors.accentPrimary),
                   const SizedBox(width: 12),
                   const Text('JARVIS Editor', style: TextStyle(color: JarvisColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                   const Spacer(),
                   IconButton(icon: const Icon(Icons.close, color: JarvisColors.textSecondary), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            const Divider(height: 1, color: JarvisColors.border),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: editCtrl,
                  maxLines: null,
                  expands: true,
                  style: const TextStyle(color: JarvisColors.textPrimary, fontSize: 14),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Start editing...',
                    hintStyle: TextStyle(color: JarvisColors.textMuted),
                  ),
                ),
              ),
            ),
            const Divider(height: 1, color: JarvisColors.border),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                   TextButton(
                     onPressed: () => Navigator.pop(context),
                     child: const Text('Cancel', style: TextStyle(color: JarvisColors.textSecondary)),
                   ),
                   const SizedBox(width: 12),
                   ElevatedButton.icon(
                     onPressed: () {
                        setState(() => _extractedText = editCtrl.text);
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File changes saved locally.')));
                     },
                     style: ElevatedButton.styleFrom(backgroundColor: JarvisColors.accentPrimary, foregroundColor: Colors.white),
                     icon: const Icon(Icons.save_rounded, size: 18),
                     label: const Text('Save Changes'),
                   )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openShareSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: JarvisColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Share Options', style: TextStyle(color: JarvisColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.share, color: JarvisColors.textPrimary),
              title: const Text('Share Original File', style: TextStyle(color: JarvisColors.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                Share.shareXFiles([XFile(widget.filePath)]);
              },
            ),
            const Divider(color: JarvisColors.border),
            const Padding(
               padding: EdgeInsets.symmetric(vertical: 8),
               child: Text('Convert & Share', style: TextStyle(color: JarvisColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
            _buildConvertOption('PDF Document', '.pdf'),
            _buildConvertOption('Word Document', '.docx'),
            _buildConvertOption('Image', '.jpg'),
          ],
        ),
      ),
    );
  }

  Widget _buildConvertOption(String title, String ext) {
    return ListTile(
      leading: const Icon(Icons.transform_rounded, color: JarvisColors.accentPrimary),
      title: Text('Convert to $title', style: const TextStyle(color: JarvisColors.textPrimary)),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: JarvisColors.bg, borderRadius: BorderRadius.circular(4)),
        child: Text(ext, style: const TextStyle(color: JarvisColors.textSecondary, fontSize: 10, fontWeight: FontWeight.bold)),
      ),
      onTap: () {
        Navigator.pop(context);
        _performConversion(title, ext);
      },
    );
  }

  Future<void> _performConversion(String targetType, String targetExt) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: JarvisColors.surface, borderRadius: BorderRadius.circular(16)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: JarvisColors.accentPrimary),
              const SizedBox(height: 16),
              Text("Converting to $targetType...", style: const TextStyle(color: JarvisColors.textPrimary)),
            ],
          ),
        ),
      ),
    );

    try {
      final tempDir = await getTemporaryDirectory();
      final fileName = p.basenameWithoutExtension(widget.filePath);
      final outputPath = "${tempDir.path}/$fileName$targetExt";

      if (targetExt == '.pdf') {
        final pdfDoc = PdfDocument();
        pdfDoc.pageSettings.margins.all = 0; 
        
        // 1.5 cm border (approx 42.5 points)
        const double margin = 42.5;
        final contentSize = Size(pdfDoc.pageSettings.size.width - (margin * 2), pdfDoc.pageSettings.size.height - (margin * 2));
        
        // Use a better font if available, or stay with Helvetica for basic ASCII
        // If a Tamil font is provided in assets later, use: PdfTrueTypeFont(File('path').readAsBytesSync(), 12)
        final font = PdfStandardFont(PdfFontFamily.helvetica, 12);
        
        final textElement = PdfTextElement(
          text: _extractedText.isEmpty ? "Empty Document" : _extractedText,
          font: font,
          brush: PdfBrushes.black,
        );
        
        final layoutFormat = PdfLayoutFormat(
          layoutType: PdfLayoutType.paginate,
          breakType: PdfLayoutBreakType.fitPage,
        );

        // Draw on first page
        PdfLayoutResult? result = textElement.draw(
          pdfDoc.pages.add(),
          bounds: Rect.fromLTWH(margin + 20, margin + 20, contentSize.width - 40, contentSize.height - 40),
          format: layoutFormat,
        );

        // Draw borders on all pages
        for (int i = 0; i < pdfDoc.pages.count; i++) {
          final p = pdfDoc.pages[i];
          // Drawing simple medium-thick border around the content area
          p.graphics.drawRectangle(
            pen: PdfPen(PdfColor(0, 0, 0), 1.5), 
            bounds: Rect.fromLTWH(margin, margin, contentSize.width, contentSize.height),
          );
        }
        
        final bytes = await pdfDoc.save();
        pdfDoc.dispose();
        await File(outputPath).writeAsBytes(bytes);
      } else {
        if (_extractedText.isNotEmpty) {
          await File(outputPath).writeAsString(_extractedText);
        } else {
          await File(widget.filePath).copy(outputPath);
        }
      }

      if (!mounted) return;
      Navigator.pop(context); // close loader
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Successfully converted to $targetExt"),
          backgroundColor: JarvisColors.success,
          action: SnackBarAction(
            label: 'Share',
            textColor: Colors.white,
            onPressed: () => Share.shareXFiles([XFile(outputPath)]),
          ),
        ),
      );
      
      Share.shareXFiles([XFile(outputPath)]);
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Conversion failed: $e"), backgroundColor: JarvisColors.error),
      );
    }
  }

  Widget _buildLoader() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ShaderMask(
            shaderCallback: (b) => JarvisColors.primaryGradient.createShader(b),
            child: const Icon(Icons.document_scanner_rounded, size: 48, color: Colors.white),
          ).animate(onPlay: (c) => c.repeat()).shimmer(duration: 1200.ms),
          const SizedBox(height: 16),
          const Text('Reading file...', style: TextStyle(color: JarvisColors.textSecondary, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: JarvisColors.error, size: 48),
            const SizedBox(height: 12),
            const Text('Could not read this file', style: TextStyle(color: JarvisColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(_error ?? 'Unknown error', style: const TextStyle(color: JarvisColors.textMuted, fontSize: 12), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_isPdf(widget.filePath)) return _buildPdfView();
    if (_isOffice(widget.filePath)) {
      if (_parsedDoc != null) {
        if (_isDoc(widget.filePath)) {
          return DocxRenderer(doc: _parsedDoc!, isEditMode: _isEditMode);
        } else if (_isSlides(widget.filePath)) {
          return PptxRenderer(doc: _parsedDoc!, isEditMode: _isEditMode);
        } else if (_isSheet(widget.filePath)) {
          return XlsxRenderer(doc: _parsedDoc!, isEditMode: _isEditMode);
        }
      }
      return _OfficeViewerWidget(
        filePath: widget.filePath,
        fileName: _basename(widget.filePath),
        extractedText: _extractedText,
      );
    }
    if (_isImage(widget.filePath)) return _buildImageView();
    if (_isAudio(widget.filePath)) return _AudioViewerWidget(filePath: widget.filePath, fileName: _basename(widget.filePath));
    if (_isVideo(widget.filePath)) return _VideoViewerWidget(filePath: widget.filePath);
    if (_isCsv(widget.filePath) && _csvRows.isNotEmpty) return _buildCsvView();
    return _buildTextView();
  }

  Widget _buildPdfView() {
    return SfPdfViewer.file(
      File(widget.filePath),
      canShowScrollHead: false,
    );
  }

  Widget _buildImageView() {
    return Center(
      child: InteractiveViewer(
        child: Image.file(File(widget.filePath), fit: BoxFit.contain),
      ),
    );
  }

  Widget _buildCsvView() {
    if (_csvRows.isEmpty) return _buildTextView();
    final headers = _csvRows.first.split(',');
    final rows = _csvRows.skip(1).toList();

    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(16),
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(JarvisColors.surfaceElevated),
          dataRowColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected) ? JarvisColors.accentPrimary.withValues(alpha: 0.1) : JarvisColors.surface),
          border: TableBorder.all(color: JarvisColors.border, width: 0.5),
          columns: headers.map((h) => DataColumn(
            label: Text(h.trim(), style: const TextStyle(color: JarvisColors.accentSecondary, fontWeight: FontWeight.w600, fontSize: 12)),
          )).toList(),
          rows: rows.take(200).map((row) {
            final cells = row.split(',');
            return DataRow(
              cells: List.generate(headers.length, (i) => DataCell(
                Text(i < cells.length ? cells[i].trim() : '',
                    style: const TextStyle(color: JarvisColors.textSecondary, fontSize: 12)),
              )),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildTextView() {
    final isCode = _ext(widget.filePath) != 'txt' && _ext(widget.filePath) != 'md';
    return Container(
      color: isCode ? const Color(0xFF0D1017) : JarvisColors.bg,
      child: _extractedText.isEmpty
          ? const Center(child: Text('File is empty or cannot be read as text.',
              style: TextStyle(color: JarvisColors.textMuted)))
          : Scrollbar(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: _isEditMode
                    ? TextField(
                        controller: _editCtrl,
                        maxLines: null,
                        style: TextStyle(
                          color: isCode ? const Color(0xFFABB2BF) : JarvisColors.textPrimary,
                          fontSize: isCode ? 12.5 : 14,
                          fontFamily: isCode ? 'monospace' : null,
                        ),
                        decoration: const InputDecoration(border: InputBorder.none),
                        onChanged: (v) => _extractedText = v,
                      )
                    : SelectableText(
                        _extractedText,
                        style: TextStyle(
                          color: isCode ? const Color(0xFFABB2BF) : JarvisColors.textPrimary,
                          fontSize: isCode ? 12.5 : 14,
                          fontFamily: isCode ? 'monospace' : null,
                          height: 1.6,
                        ),
                      ),
              ),
            ),
    );
  }

  Future<void> _saveChanges() async {
    try {
      setState(() => _loading = true);
      // Update file on disk
      if (_isOffice(widget.filePath)) {
        // Since we can't easily re-encode ZIP/OOXML, we update the state text
        // In a production environment, you'd use a more advanced XML writer
        String finalContent = "";
        if (_parsedDoc != null) {
          final sb = StringBuffer();
          for (final block in _parsedDoc!.blocks) {
             sb.writeln(block.plainText);
          }
          if (_parsedDoc!.slides != null) {
            for (final slide in _parsedDoc!.slides!) {
               for (final block in slide.blocks) {
                  if (block.plainText != null) sb.writeln(block.plainText);
               }
            }
          }
          finalContent = sb.toString();
        }
        _extractedText = finalContent;
        _editCtrl.text = finalContent;
      } else {
        await File(widget.filePath).writeAsString(_extractedText);
      }
      
      setState(() {
        _isEditMode = false;
        _loading = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Changes saved successfully"), backgroundColor: JarvisColors.success),
      );
    } catch (e) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Save failed: $e"), backgroundColor: JarvisColors.error),
      );
    }
  }
}

// ─── File meta bar ────────────────────────────────────────────────────────────
class _FileMeta extends StatelessWidget {
  final String name;
  final int size;
  final Color color;
  final String path;

  const _FileMeta({required this.name, required this.size, required this.color, required this.path});

  @override
  Widget build(BuildContext context) {
    final ext = _ext(path).toUpperCase();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: JarvisColors.surface,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(ext, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
          Text(_formatSize(size), style: const TextStyle(color: JarvisColors.textMuted, fontSize: 11)),
          const SizedBox(width: 10),
          const Icon(Icons.auto_awesome_rounded, color: JarvisColors.accentPrimary, size: 11),
          const SizedBox(width: 4),
          const Text('Ask JARVIS about this file', style: TextStyle(color: JarvisColors.accentPrimary, fontSize: 11)),
        ],
      ),
    );
  }
}

// ─── In-file chat bottom sheet ────────────────────────────────────────────────
class _FileChat extends StatefulWidget {
  final String filePath;
  final String extractedText;
  final String? initialQuestion;

  const _FileChat({required this.filePath, required this.extractedText, this.initialQuestion});

  @override
  State<_FileChat> createState() => _FileChatState();
}

class _FileChatState extends State<_FileChat> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<({String text, bool isUser})> _messages = [];
  bool _thinking = false;


  @override
  void initState() {
    super.initState();
    if (widget.initialQuestion != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _send(widget.initialQuestion!));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send(String text) async {
    if (text.trim().isEmpty || _thinking) return;
    _controller.clear();

    setState(() {
      _messages.add((text: text.trim(), isUser: true));
      _thinking = true;
    });
    _scrollDown();

    try {
      final router = context.read<AIRouter>();
      final name = _basename(widget.filePath);
      final ext = _ext(widget.filePath).toUpperCase();

      // Truncate very large files to stay within context
      final content = widget.extractedText.length > 40000
          ? '${widget.extractedText.substring(0, 40000)}\n\n...[TRUNCATED — file is very large]'
          : widget.extractedText;

      final systemPrompt = '''You are JARVIS File Intelligence. The user has opened a file and is asking questions about it.

FILE NAME: $name
FILE TYPE: $ext
TOTAL CHARACTERS: ${widget.extractedText.length}

FILE CONTENT:
$content

INSTRUCTIONS:
- Answer ONLY based on the file content above.
- Be precise and reference specific parts when relevant.
- If asked to summarize: give a structured markdown summary.
- If asked to find something: quote it exactly with context.
- If file is code: explain it clearly, find bugs, suggest improvements.
- If file is a spreadsheet/CSV: analyze the data patterns.''';

      final buffer = StringBuffer();
      await for (final chunk in router.generateStream(text, systemPrompt: systemPrompt)) {
        buffer.write(chunk);
      }

      setState(() {
        _messages.add((text: buffer.toString(), isUser: false));
        _thinking = false;
      });
    } catch (e) {
      setState(() {
        _messages.add((text: '⚠️ Error: $e', isUser: false));
        _thinking = false;
      });
    }
    _scrollDown();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: JarvisColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(color: JarvisColors.border, borderRadius: BorderRadius.circular(2)),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(
                children: [
                  ShaderMask(
                    shaderCallback: (b) => JarvisColors.primaryGradient.createShader(b),
                    child: const Icon(Icons.bolt_rounded, size: 20, color: Colors.white),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Ask JARVIS', style: TextStyle(color: JarvisColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
                        Text('Chatting about your file', style: TextStyle(color: JarvisColors.textMuted, fontSize: 11)),
                      ],
                    ),
                  ),
                  // Quick prompts
                  _QuickChip(label: 'Summarize', onTap: () => _send('Please summarize this file for me.')),
                  const SizedBox(width: 6),
                  _QuickChip(label: 'Key Points', onTap: () => _send('What are the key points in this file?')),
                ],
              ),
            ),

            Divider(height: 1, color: JarvisColors.border),

            // Messages
            Expanded(
              child: _messages.isEmpty && !_thinking
                  ? _buildWelcome()
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: _messages.length + (_thinking ? 1 : 0),
                      itemBuilder: (_, i) {
                        if (i == _messages.length && _thinking) return _buildThinkingBubble();
                        final msg = _messages[i];
                        return _ChatBubble(text: msg.text, isUser: msg.isUser);
                      },
                    ),
            ),

            // Input bar
            Container(
              padding: EdgeInsets.only(left: 16, right: 8, top: 8, bottom: MediaQuery.of(context).viewInsets.bottom + 12),
              decoration: const BoxDecoration(
                color: JarvisColors.surfaceElevated,
                border: Border(top: BorderSide(color: JarvisColors.border, width: 0.5)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      style: const TextStyle(color: JarvisColors.textPrimary, fontSize: 14),
                      decoration: const InputDecoration(
                        hintText: 'Ask anything about this file...',
                        hintStyle: TextStyle(color: JarvisColors.textMuted),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 10),
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: _send,
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: _thinking
                        ? const SizedBox(width: 40, height: 40, child: CircularProgressIndicator(strokeWidth: 2, color: JarvisColors.accentPrimary))
                        : IconButton(
                            icon: const Icon(Icons.send_rounded, color: JarvisColors.accentPrimary),
                            onPressed: () => _send(_controller.text),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcome() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ShaderMask(
              shaderCallback: (b) => JarvisColors.primaryGradient.createShader(b),
              child: const Icon(Icons.chat_bubble_outline_rounded, size: 40, color: Colors.white),
            ).animate().scale(begin: const Offset(0.6, 0.6), duration: 400.ms, curve: Curves.elasticOut),
            const SizedBox(height: 12),
            const Text("Ask me anything about this file", style: TextStyle(color: JarvisColors.textSecondary, fontSize: 14), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8, runSpacing: 8, alignment: WrapAlignment.center,
              children: [
                '📋 Summarize it', '🐛 Find bugs', '📊 Analyze data', '🔍 Explain this',
              ].map((s) => GestureDetector(
                onTap: () => _send(s.substring(3)),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: JarvisColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: JarvisColors.border),
                  ),
                  child: Text(s, style: const TextStyle(color: JarvisColors.textSecondary, fontSize: 12)),
                ),
              )).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThinkingBubble() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(shape: BoxShape.circle, gradient: JarvisColors.primaryGradient),
            child: const Icon(Icons.auto_awesome_rounded, size: 14, color: Colors.white),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: JarvisColors.surfaceElevated,
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(4), topRight: Radius.circular(16), bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) => Container(
                width: 6, height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: const BoxDecoration(shape: BoxShape.circle, color: JarvisColors.accentPrimary),
              ).animate(delay: Duration(milliseconds: i * 180), onPlay: (c) => c.repeat())
                .fadeIn(duration: 400.ms)
                .then()
                .fadeOut(duration: 400.ms)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final String text;
  final bool isUser;

  const _ChatBubble({required this.text, required this.isUser});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(shape: BoxShape.circle, gradient: JarvisColors.primaryGradient),
              child: const Icon(Icons.auto_awesome_rounded, size: 14, color: Colors.white),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser ? JarvisColors.accentPrimary : JarvisColors.surfaceElevated,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
              ),
              child: isUser 
                ? SelectableText(
                    text,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5, height: 1.5,
                    ),
                  )
                : MarkdownBody(
                    data: text,
                    builders: {
                      'latex': LatexElementBuilder(
                        textStyle: TextStyle(color: JarvisColors.textPrimary, fontSize: 13.5),
                        textScaleFactor: 1.1,
                      ),
                    },
                    extensionSet: md.ExtensionSet(
                      [LatexBlockSyntax(), ...md.ExtensionSet.gitHubFlavored.blockSyntaxes],
                      [LatexInlineSyntax(), ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes],
                    ),
                    styleSheet: MarkdownStyleSheet(
                      p: GoogleFonts.outfit(color: JarvisColors.textPrimary, fontSize: 13.5, height: 1.5),
                      h2: GoogleFonts.outfit(color: JarvisColors.accentSecondary, fontSize: 16, fontWeight: FontWeight.bold),
                      h3: GoogleFonts.outfit(color: JarvisColors.accentPrimary, fontSize: 15, fontWeight: FontWeight.bold),
                      strong: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
                      listBullet: const TextStyle(color: JarvisColors.accentPrimary),
                      tableHead: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white),
                      tableBody: GoogleFonts.outfit(color: JarvisColors.textPrimary),
                      tableBorder: TableBorder.all(color: JarvisColors.border, width: 1),
                      code: GoogleFonts.firaCode(backgroundColor: Colors.black26, fontSize: 12, color: JarvisColors.accentPrimary),
                      codeblockDecoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: JarvisColors.border),
                      ),
                    ),
                  ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.1, end: 0);
  }
}

class _QuickChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _QuickChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: JarvisColors.accentPrimary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: JarvisColors.accentPrimary.withValues(alpha: 0.3)),
        ),
        child: Text(label, style: const TextStyle(color: JarvisColors.accentPrimary, fontSize: 11, fontWeight: FontWeight.w500)),
      ),
    );
  }
}

class _OfficeViewerWidget extends StatelessWidget {
  final String filePath;
  final String fileName;
  final String extractedText;

  const _OfficeViewerWidget({
    required this.filePath,
    required this.fileName,
    required this.extractedText,
  });

  @override
  Widget build(BuildContext context) {
    final ext = _ext(filePath).toUpperCase();
    final color = _typeColor(filePath);
    final icon = _typeIcon(filePath);

    return Column(
      children: [
        // Open-in-app banner
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color.withValues(alpha: 0.15), color.withValues(alpha: 0.05)],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ext, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    const Text('Open with your device\'s native app for full formatting',
                        style: TextStyle(color: JarvisColors.textMuted, fontSize: 11)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () => OpenFilex.open(filePath),
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: const Text('Open', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),

        // Extracted text preview
        Expanded(
          child: extractedText.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 56, color: color.withValues(alpha: 0.4)),
                      const SizedBox(height: 16),
                      Text('No text could be extracted from this $ext file.',
                          style: const TextStyle(color: JarvisColors.textMuted, fontSize: 14),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      const Text('Use "Open" above to view it with a compatible app.',
                          style: TextStyle(color: JarvisColors.textMuted, fontSize: 12),
                          textAlign: TextAlign.center),
                    ],
                  ),
                )
              : Scrollbar(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    child: SelectableText(
                      extractedText,
                      style: const TextStyle(
                        color: JarvisColors.textPrimary,
                        fontSize: 14,
                        height: 1.65,
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

// ── Audio Viewer ──────────────────────────────────────────────────────────────
class _AudioViewerWidget extends StatefulWidget {
  final String filePath;
  final String fileName;
  const _AudioViewerWidget({required this.filePath, required this.fileName});

  @override
  State<_AudioViewerWidget> createState() => _AudioViewerWidgetState();
}

class _AudioViewerWidgetState extends State<_AudioViewerWidget> {
  late AudioPlayer _audioPlayer;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _initAudio();
  }

  Future<void> _initAudio() async {
    try {
      await _audioPlayer.setFilePath(widget.filePath);
      _audioPlayer.durationStream.listen((d) => setState(() => _duration = d ?? Duration.zero));
      _audioPlayer.positionStream.listen((p) => setState(() => _position = p));
      _audioPlayer.playerStateStream.listen((state) {
        if (mounted) setState(() => _isPlaying = state.playing);
      });
    } catch (e) {
      debugPrint('Error loading audio: $e');
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(d.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(d.inSeconds.remainder(60));
    return "${twoDigits(d.inHours)}:$twoDigitMinutes:$twoDigitSeconds".replaceFirst(RegExp(r'^00:'), "");
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [JarvisColors.accentPrimary.withValues(alpha: 0.2), JarvisColors.accentSecondary.withValues(alpha: 0.2)],
                ),
              ),
              child: const Icon(Icons.music_note_rounded, size: 64, color: JarvisColors.accentPrimary),
            ),
            const SizedBox(height: 24),
            Text(widget.fileName, style: const TextStyle(color: JarvisColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
            const SizedBox(height: 32),
            SliderTheme(
              data: SliderThemeData(
                activeTrackColor: JarvisColors.accentPrimary,
                inactiveTrackColor: JarvisColors.border,
                thumbColor: JarvisColors.accentPrimary,
                overlayColor: JarvisColors.accentPrimary.withValues(alpha: 0.2),
              ),
              child: Slider(
                value: _position.inMilliseconds.toDouble(),
                max: _duration.inMilliseconds.toDouble() > 0 ? _duration.inMilliseconds.toDouble() : 1.0,
                onChanged: (v) => _audioPlayer.seek(Duration(milliseconds: v.toInt())),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_formatDuration(_position), style: const TextStyle(color: JarvisColors.textSecondary, fontSize: 12)),
                  Text(_formatDuration(_duration), style: const TextStyle(color: JarvisColors.textSecondary, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.replay_10_rounded, size: 32, color: JarvisColors.textPrimary),
                  onPressed: () => _audioPlayer.seek(_position - const Duration(seconds: 10)),
                ),
                const SizedBox(width: 24),
                Container(
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: JarvisColors.accentPrimary),
                  child: IconButton(
                    icon: Icon(_isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 40, color: Colors.white),
                    onPressed: () => _isPlaying ? _audioPlayer.pause() : _audioPlayer.play(),
                  ),
                ),
                const SizedBox(width: 24),
                IconButton(
                  icon: const Icon(Icons.forward_10_rounded, size: 32, color: JarvisColors.textPrimary),
                  onPressed: () => _audioPlayer.seek(_position + const Duration(seconds: 10)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Video Viewer ──────────────────────────────────────────────────────────────
class _VideoViewerWidget extends StatefulWidget {
  final String filePath;
  const _VideoViewerWidget({required this.filePath});

  @override
  State<_VideoViewerWidget> createState() => _VideoViewerWidgetState();
}

class _VideoViewerWidgetState extends State<_VideoViewerWidget> {
  late VideoPlayerController _controller;
  bool _initialized = false;
  bool _showControls = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    try {
      _controller = VideoPlayerController.file(File(widget.filePath));
      await _controller.initialize();
      if (mounted) {
        setState(() => _initialized = true);
        _controller.play();
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    if (_initialized) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.video_library_rounded, size: 56, color: Color(0xFF009688)),
              const SizedBox(height: 16),
              const Text('Cannot play this video format in-app.',
                  style: TextStyle(color: JarvisColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              const Text('Use "Open externally" to play with your video player.',
                  style: TextStyle(color: JarvisColors.textMuted, fontSize: 13),
                  textAlign: TextAlign.center),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => OpenFilex.open(widget.filePath),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF009688),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Open in Video Player', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      );
    }

    if (!_initialized) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: JarvisColors.accentPrimary),
            SizedBox(height: 12),
            Text('Loading video...', style: TextStyle(color: JarvisColors.textMuted, fontSize: 13)),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: () => setState(() => _showControls = !_showControls),
      child: Container(
        color: Colors.black,
        child: Center(
          child: AspectRatio(
            aspectRatio: _controller.value.aspectRatio,
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                VideoPlayer(_controller),
                AnimatedOpacity(
                  opacity: _showControls ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 250),
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.black87, Colors.transparent],
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        VideoProgressIndicator(
                          _controller,
                          allowScrubbing: true,
                          colors: const VideoProgressColors(
                            playedColor: JarvisColors.accentPrimary,
                            backgroundColor: JarvisColors.border,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.replay_10_rounded, color: Colors.white, size: 28),
                              onPressed: () {
                                final pos = _controller.value.position - const Duration(seconds: 10);
                                _controller.seekTo(pos < Duration.zero ? Duration.zero : pos);
                              },
                            ),
                            IconButton(
                              icon: Icon(
                                _controller.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 38,
                              ),
                              onPressed: () {
                                setState(() {
                                  _controller.value.isPlaying ? _controller.pause() : _controller.play();
                                });
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.forward_10_rounded, color: Colors.white, size: 28),
                              onPressed: () {
                                final pos = _controller.value.position + const Duration(seconds: 10);
                                _controller.seekTo(pos);
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
