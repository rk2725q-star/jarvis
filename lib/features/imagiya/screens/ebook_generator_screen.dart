import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/router/ai_router.dart';
import '../services/ebook_service.dart';
import 'dart:io';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:http/http.dart' as http;

class EBookGeneratorScreen extends StatefulWidget {
  const EBookGeneratorScreen({super.key});

  @override
  State<EBookGeneratorScreen> createState() => _EBookGeneratorScreenState();
}

class _EBookGeneratorScreenState extends State<EBookGeneratorScreen> {
  // ── Form controllers ──────────────────────────────────────────────────────
  final _titleCtrl = TextEditingController();
  final _synopsisCtrl = TextEditingController();

  String _genre = 'Comics';
  String _audience = 'Teen';
  String _tone = 'Adventurous';
  String _artStyle = 'comic-book';
  String _language = 'English';
  int _pageCount = 10;

  // ── Generation state ──────────────────────────────────────────────────────
  bool _isGenerating = false;
  EBookProgress? _progress;
  final List<EBookPage> _pages = [];
  StreamSubscription? _sub;

  // ── Viewer state ──────────────────────────────────────────────────────────
  int _viewPage = 0;
  final _pageCtrl = PageController();

  static const _genreOptions = [
    'Comics',
    'Fantasy',
    'Sci-Fi',
    'Adventure',
    'Educational',
    'Horror',
    'Romance',
    'Mystery',
  ];
  static const _audienceOptions = ['Children', 'Teen', 'Adult'];
  static const _toneOptions = [
    'Adventurous',
    'Humorous',
    'Dramatic',
    'Educational',
    'Suspenseful',
    'Romantic',
  ];
  static const _styleOptions = [
    'comic-book',
    'anime',
    'realistic',
    'watercolor',
    'sketch',
    'cyberpunk',
    '3d-render',
  ];
  static const _langOptions = [
    'English',
    'Tamil',
    'Hindi',
    'Telugu',
    'Malayalam',
    'Kannada',
  ];

  @override
  void dispose() {
    _sub?.cancel();
    _titleCtrl.dispose();
    _synopsisCtrl.dispose();
    _pageCtrl.dispose();
    super.dispose();
  }

  // ── Generate ──────────────────────────────────────────────────────────────
  void _startGeneration() {
    if (_titleCtrl.text.trim().isEmpty || _synopsisCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in Title and Synopsis.')),
      );
      return;
    }

    final router = context.read<AIRouter>();
    final service = EBookService(router);
    final config = EBookConfig(
      title: _titleCtrl.text.trim(),
      synopsis: _synopsisCtrl.text.trim(),
      genre: _genre,
      targetAudience: _audience,
      tone: _tone,
      artStyle: _artStyle,
      pageCount: _pageCount,
      language: _language,
    );

    setState(() {
      _isGenerating = true;
      _pages.clear();
      _progress = null;
      _viewPage = 0;
    });

    _sub?.cancel();
    _sub = service
        .generate(config)
        .listen(
          (event) {
            setState(() {
              _progress = event.progress;
              if (event.page != null) {
                final idx = _pages.indexWhere(
                  (p) => p.pageNumber == event.page!.pageNumber,
                );
                if (idx >= 0) {
                  _pages[idx] = event.page!;
                } else {
                  _pages.add(event.page!);
                  _pages.sort((a, b) => a.pageNumber.compareTo(b.pageNumber));
                }
              }
              if (event.progress.isDone) _isGenerating = false;
            });
          },
          onError: (e) {
            setState(() {
              _isGenerating = false;
              _progress = EBookProgress(
                stage: 'error',
                currentPage: 0,
                totalPages: _pageCount,
                message: 'Error: $e',
                hasError: true,
                errorMessage: e.toString(),
              );
            });
          },
        );
  }

  void _cancelGeneration() {
    _sub?.cancel();
    setState(() => _isGenerating = false);
  }

  // ── UI ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF12121E),
        title: const Row(
          children: [
            Icon(Icons.auto_stories, color: Color(0xFFB388FF), size: 22),
            SizedBox(width: 8),
            Text(
              'eBook Generator',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_pages.isNotEmpty && !_isGenerating)
            IconButton(
              icon: const Icon(
                Icons.picture_as_pdf,
                color: Colors.orangeAccent,
              ),
              tooltip: 'Download PDF',
              onPressed: _isDownloading ? null : _downloadPdf,
            ),
          if (_pages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.menu_book, color: Color(0xFFB388FF)),
              tooltip: 'Read eBook',
              onPressed: _pages.isEmpty ? null : _openReader,
            ),
        ],
      ),
      body: _pages.isNotEmpty && !_isGenerating
          ? _buildReader()
          : _buildSetupView(),
    );
  }

  Widget _buildSetupView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1A1030), Color(0xFF0D1A3A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFFB388FF).withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '📚 AI eBook Generator',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Generate a complete illustrated eBook with up to 45 pages using your AI provider.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
          _sectionLabel('📖 Story Details'),
          const SizedBox(height: 12),

          _inputField(_titleCtrl, 'eBook Title', 'e.g. "The Last Star Knight"'),
          const SizedBox(height: 12),
          _inputField(
            _synopsisCtrl,
            'Synopsis / Story Idea',
            'Describe your story in 1–3 sentences...',
            lines: 4,
          ),

          const SizedBox(height: 20),
          _sectionLabel('🎨 Style & Settings'),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: _dropdownField(
                  'Genre',
                  _genre,
                  _genreOptions,
                  (v) => setState(() => _genre = v!),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _dropdownField(
                  'Audience',
                  _audience,
                  _audienceOptions,
                  (v) => setState(() => _audience = v!),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _dropdownField(
                  'Tone',
                  _tone,
                  _toneOptions,
                  (v) => setState(() => _tone = v!),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _dropdownField(
                  'Art Style',
                  _artStyle,
                  _styleOptions,
                  (v) => setState(() => _artStyle = v!),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _dropdownField(
                  'Language',
                  _language,
                  _langOptions,
                  (v) => setState(() => _language = v!),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: _pageCountSlider()),
            ],
          ),

          const SizedBox(height: 28),

          // ── Progress ──────────────────────────────────────────────────────
          if (_progress != null) _buildProgressCard(),

          const SizedBox(height: 16),

          // ── Action button ─────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 54,
            child: _isGenerating
                ? ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4A1A1A),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(
                      Icons.stop_circle,
                      color: Colors.redAccent,
                    ),
                    label: const Text(
                      'Cancel Generation',
                      style: TextStyle(color: Colors.redAccent, fontSize: 16),
                    ),
                    onPressed: _cancelGeneration,
                  )
                : ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7C3AED),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.auto_stories, color: Colors.white),
                    label: const Text(
                      'Generate eBook',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onPressed: _startGeneration,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressCard() {
    final p = _progress!;
    final pct = p.totalPages > 0 ? p.currentPage / p.totalPages : 0.0;
    final stageIcon = switch (p.stage) {
      'outline' => '📋',
      'writing' => '✍️',
      'illustrating' => '🎨',
      'done' => '✅',
      _ => '⚙️',
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFB388FF).withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('$stageIcon ', style: const TextStyle(fontSize: 18)),
              Expanded(
                child: Text(
                  p.message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: pct,
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFFB388FF),
              ),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${p.currentPage} / ${p.totalPages} pages  •  ${_pages.length} written',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildReader() {
    return Column(
      children: [
        // Page indicator
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          color: const Color(0xFF12121E),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_viewPage + 1} / ${_pages.length}',
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
              Text(
                _pages[_viewPage].chapterTitle,
                style: const TextStyle(
                  color: Color(0xFFB388FF),
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _pages.clear();
                }),
                child: const Text(
                  '← New Book',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: PageView.builder(
            controller: _pageCtrl,
            itemCount: _pages.length,
            onPageChanged: (i) => setState(() => _viewPage = i),
            itemBuilder: (ctx, i) => _buildPageView(_pages[i]),
          ),
        ),
        // Nav row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          color: const Color(0xFF12121E),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, color: Colors.white),
                onPressed: _viewPage > 0
                    ? () => _pageCtrl.previousPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      )
                    : null,
              ),
              Row(
                children: List.generate(
                  (_pages.length).clamp(0, 8),
                  (i) => Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    width: i == _viewPage ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == _viewPage
                          ? const Color(0xFFB388FF)
                          : Colors.white24,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right, color: Colors.white),
                onPressed: _viewPage < _pages.length - 1
                    ? () => _pageCtrl.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPageView(EBookPage page) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Page header
          Text(
            'Page ${page.pageNumber}',
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 12,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            page.chapterTitle,
            style: const TextStyle(
              color: Color(0xFFB388FF),
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          // Image (shown for even pages)
          if (page.imageUrl != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                page.imageUrl!,
                fit: BoxFit.cover,
                width: double.infinity,
                height: 200,
                loadingBuilder: (ctx, child, progress) => progress == null
                    ? child
                    : Container(
                        height: 200,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A2E),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFFB388FF),
                          ),
                        ),
                      ),
                errorBuilder: (_, _, _) => Container(
                  height: 120,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A2E),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.image_not_supported,
                      color: Colors.white24,
                      size: 40,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          // Content
          Text(
            page.content,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              height: 1.7,
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  void _openReader() {
    setState(() {});
  }

  bool _isDownloading = false;

  Future<void> _downloadPdf() async {
    if (_pages.isEmpty) return;
    setState(() => _isDownloading = true);

    try {
      final pdf = pw.Document();

      // Title Page
      pdf.addPage(
        pw.Page(
          build: (pw.Context context) {
            return pw.Center(
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.Text(
                    _titleCtrl.text,
                    style: pw.TextStyle(
                      fontSize: 32,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 20),
                  pw.Text(
                    'Generated by JARVIS AI',
                    style: const pw.TextStyle(fontSize: 16),
                  ),
                ],
              ),
            );
          },
        ),
      );

      // Content Pages
      for (final page in _pages) {
        pw.MemoryImage? pdfImage;

        if (page.imageUrl != null) {
          try {
            final response = await http.get(Uri.parse(page.imageUrl!));
            if (response.statusCode == 200) {
              pdfImage = pw.MemoryImage(response.bodyBytes);
            }
          } catch (_) {}
        }

        pdf.addPage(
          pw.MultiPage(
            margin: const pw.EdgeInsets.all(32),
            build: (pw.Context context) {
              return [
                pw.Text(
                  page.chapterTitle,
                  style: pw.TextStyle(
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 20),
                if (pdfImage != null) ...[
                  pw.Image(pdfImage, fit: pw.BoxFit.contain, height: 300),
                  pw.SizedBox(height: 20),
                ],
                pw.Text(
                  page.content,
                  style: const pw.TextStyle(fontSize: 14, lineSpacing: 1.5),
                ),
              ];
            },
          ),
        );
      }

      final outputDir = await getApplicationDocumentsDirectory();
      final sanitizedTitle = _titleCtrl.text
          .replaceAll(RegExp(r'[^\w\s]+'), '')
          .trim()
          .replaceAll(' ', '_');
      final fileName =
          '${sanitizedTitle}_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final file = File('${outputDir.path}/$fileName');

      await file.writeAsBytes(await pdf.save());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ PDF Saved Successfully!')),
        );
        await OpenFilex.open(file.path);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('❌ Error saving PDF: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isDownloading = false);
      }
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  Widget _sectionLabel(String text) => Text(
    text,
    style: const TextStyle(
      color: Colors.white,
      fontWeight: FontWeight.w700,
      fontSize: 15,
    ),
  );

  Widget _inputField(
    TextEditingController ctrl,
    String label,
    String hint, {
    int lines = 1,
  }) {
    return TextField(
      controller: ctrl,
      maxLines: lines,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: Color(0xFFB388FF)),
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
        filled: true,
        fillColor: const Color(0xFF1A1A2E),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFB388FF), width: 0.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: const Color(0xFFB388FF).withValues(alpha: 0.3),
            width: 0.5,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFB388FF), width: 1.5),
        ),
      ),
    );
  }

  Widget _dropdownField(
    String label,
    String value,
    List<String> options,
    ValueChanged<String?> onChanged,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFB388FF).withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: const Color(0xFF1A1A2E),
          style: const TextStyle(color: Colors.white, fontSize: 14),
          hint: Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          items: options
              .map((o) => DropdownMenuItem(value: o, child: Text(o)))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _pageCountSlider() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFB388FF).withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pages: $_pageCount',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: const Color(0xFFB388FF),
              thumbColor: const Color(0xFFB388FF),
              inactiveTrackColor: Colors.white12,
              overlayColor: const Color(0xFFB388FF).withValues(alpha: 0.2),
            ),
            child: Slider(
              value: _pageCount.toDouble(),
              min: 5,
              max: 45,
              divisions: 40,
              onChanged: (v) => setState(() => _pageCount = v.round()),
            ),
          ),
        ],
      ),
    );
  }
}
