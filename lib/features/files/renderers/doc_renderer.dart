import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/doc_models.dart';

// ─── Theme ────────────────────────────────────────────────────────────────────
class DocTheme {
  static const pageColor = Color(0xFFFFFFFF);
  static const pageShadow = Color(0xFFD0D0D0);
  static const bgColor = Color(0xFFEEEEEE);
  static const textPrimary = Color(0xFF1A1A2E);
  static const textSecondary = Color(0xFF4A4A68);
  static const accent = Color(0xFF2563EB);
  static const accentLight = Color(0xFFEFF6FF);
  static const slideGrad1 = Color(0xFF1E3A5F);
  static const slideGrad2 = Color(0xFF0F172A);
  static const tableBorder = Color(0xFFCBD5E1);
  static const tableHeaderBg = Color(0xFF1E3A5F);
  static const tableAltRow = Color(0xFFF8FAFC);
  static const bulletColor = Color(0xFF2563EB);
  static const quoteBarColor = Color(0xFF2563EB);
  static const codeBackground = Color(0xFF1E293B);
  static const codeText = Color(0xFFE2E8F0);
  static const dividerColor = Color(0xFFE2E8F0);
  static const sheetHeaderBg = Color(0xFF1E3A5F);
  static const sheetHeaderText = Color(0xFFFFFFFF);
  static const sheetBorder = Color(0xFFCBD5E1);
  static const sheetAltRow = Color(0xFFF1F5F9);
}

// ═══════════════════════════════════════════════════════════════════════════════
//  DOCX RENDERER
// ═══════════════════════════════════════════════════════════════════════════════

class DocxRenderer extends StatelessWidget {
  final ParsedDocument doc;
  final bool isEditMode;
  const DocxRenderer({super.key, required this.doc, this.isEditMode = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: DocTheme.bgColor,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Column(
          children: [
            _DocInfoBanner(doc: doc),
            const SizedBox(height: 16),
            _DocPage(blocks: doc.blocks, isEditMode: isEditMode),
          ],
        ),
      ),
    );
  }
}

class _DocInfoBanner extends StatelessWidget {
  final ParsedDocument doc;
  const _DocInfoBanner({required this.doc});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E3A5F), Color(0xFF0F172A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.description, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  doc.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 12,
                  children: [
                    if (doc.author != null)
                      _chip(Icons.person_outline, doc.author!),
                    if (doc.pageCount != null)
                      _chip(Icons.pages_outlined, '${doc.pageCount} pages'),
                    if (doc.imageCount > 0)
                      _chip(Icons.image_outlined, '${doc.imageCount} images'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white60, size: 12),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.white60, fontSize: 11),
        ),
      ],
    );
  }
}

class _DocPage extends StatelessWidget {
  final List<DocBlock> blocks;
  final bool isEditMode;
  const _DocPage({required this.blocks, this.isEditMode = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: DocTheme.pageColor,
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: DocTheme.pageShadow.withValues(alpha: 0.5),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 56),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: blocks.map((b) => _buildBlock(b)).toList(),
      ),
    );
  }

  Widget _buildBlock(DocBlock block) {
    if (isEditMode &&
        block.type != BlockType.image &&
        block.type != BlockType.table) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: TextField(
          controller: TextEditingController(text: block.plainText),
          maxLines: null,
          style: const TextStyle(
            fontSize: 13.5,
            color: DocTheme.textPrimary,
            height: 1.5,
          ),
          decoration: const InputDecoration(
            border: InputBorder.none,
            isDense: true,
          ),
          onChanged: (v) => block.plainText = v,
        ),
      );
    }
    switch (block.type) {
      case BlockType.heading1:
        return _Heading1Widget(block: block);
      case BlockType.heading2:
        return _Heading2Widget(block: block);
      case BlockType.heading3:
        return _Heading3Widget(block: block);
      case BlockType.paragraph:
        return _ParagraphWidget(block: block);
      case BlockType.bulletPoint:
        return _BulletWidget(block: block);
      case BlockType.numberedPoint:
        return _NumberedWidget(block: block);
      case BlockType.table:
        return _TableWidget(block: block);
      case BlockType.image:
        return _ImageWidget(block: block);
      case BlockType.pageBreak:
        return _PageBreakWidget(block: block);
      case BlockType.divider:
        return _DividerWidget();
      case BlockType.quote:
        return _QuoteWidget(block: block);
      case BlockType.codeBlock:
        return _CodeWidget(block: block);
      case BlockType.emptyLine:
        return const SizedBox(height: 10);
    }
  }
}

// ─── Heading 1 ────────────────────────────────────────────────────────────────
class _Heading1Widget extends StatelessWidget {
  final DocBlock block;
  const _Heading1Widget({required this.block});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 28, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RichTextWidget(
            runs: block.runs,
            defaultStyle: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: DocTheme.textPrimary,
              height: 1.3,
              letterSpacing: -0.5,
            ),
            alignment: block.alignment,
          ),
          const SizedBox(height: 8),
          Container(
            height: 3,
            width: 60,
            decoration: BoxDecoration(
              color: DocTheme.accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Heading 2 ────────────────────────────────────────────────────────────────
class _Heading2Widget extends StatelessWidget {
  final DocBlock block;
  const _Heading2Widget({required this.block});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 6),
      child: _RichTextWidget(
        runs: block.runs,
        defaultStyle: const TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1E3A5F),
          height: 1.35,
        ),
        alignment: block.alignment,
      ),
    );
  }
}

// ─── Heading 3 ────────────────────────────────────────────────────────────────
class _Heading3Widget extends StatelessWidget {
  final DocBlock block;
  const _Heading3Widget({required this.block});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 4),
      child: _RichTextWidget(
        runs: block.runs,
        defaultStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: DocTheme.textPrimary,
          height: 1.4,
        ),
        alignment: block.alignment,
      ),
    );
  }
}

// ─── Paragraph ────────────────────────────────────────────────────────────────
class _ParagraphWidget extends StatelessWidget {
  final DocBlock block;
  const _ParagraphWidget({required this.block});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        top: 4,
        bottom: 6,
        left: block.indentLevel * 20.0,
      ),
      child: _RichTextWidget(
        runs: block.runs,
        defaultStyle: const TextStyle(
          fontSize: 13.5,
          color: DocTheme.textPrimary,
          height: 1.75,
          fontWeight: FontWeight.w400,
        ),
        alignment: block.alignment,
      ),
    );
  }
}

// ─── Bullet ───────────────────────────────────────────────────────────────────
class _BulletWidget extends StatelessWidget {
  final DocBlock block;
  const _BulletWidget({required this.block});

  @override
  Widget build(BuildContext context) {
    final indent = block.indentLevel * 16.0 + 8.0;
    final bulletSize = block.indentLevel == 0 ? 6.0 : 4.0;
    final bulletColor = block.indentLevel == 0
        ? DocTheme.bulletColor
        : DocTheme.textSecondary;

    return Padding(
      padding: EdgeInsets.only(left: indent, top: 3, bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8, right: 10),
            child: Container(
              width: bulletSize,
              height: bulletSize,
              decoration: BoxDecoration(
                color: bulletColor,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Expanded(
            child: _RichTextWidget(
              runs: block.runs,
              defaultStyle: const TextStyle(
                fontSize: 13.5,
                color: DocTheme.textPrimary,
                height: 1.7,
              ),
              alignment: 'left',
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Numbered ─────────────────────────────────────────────────────────────────
class _NumberedWidget extends StatelessWidget {
  final DocBlock block;
  const _NumberedWidget({required this.block});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: block.indentLevel * 16.0 + 8.0,
        top: 3,
        bottom: 3,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '${block.bulletNumber ?? 1}.',
              style: const TextStyle(
                fontSize: 13.5,
                color: DocTheme.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: _RichTextWidget(
              runs: block.runs,
              defaultStyle: const TextStyle(
                fontSize: 13.5,
                color: DocTheme.textPrimary,
                height: 1.7,
              ),
              alignment: 'left',
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Quote ────────────────────────────────────────────────────────────────────
class _QuoteWidget extends StatelessWidget {
  final DocBlock block;
  const _QuoteWidget({required this.block});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: DocTheme.accentLight,
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(8),
          bottomRight: Radius.circular(8),
        ),
        border: const Border(
          left: BorderSide(color: DocTheme.quoteBarColor, width: 4),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: _RichTextWidget(
        runs: block.runs,
        defaultStyle: const TextStyle(
          fontSize: 13.5,
          color: DocTheme.textSecondary,
          fontStyle: FontStyle.italic,
          height: 1.7,
        ),
        alignment: 'left',
      ),
    );
  }
}

// ─── Code ─────────────────────────────────────────────────────────────────────
class _CodeWidget extends StatelessWidget {
  final DocBlock block;
  const _CodeWidget({required this.block});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: DocTheme.codeBackground,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(16),
      width: double.infinity,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SelectableText(
          block.plainText ?? '',
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            color: DocTheme.codeText,
            height: 1.6,
          ),
        ),
      ),
    );
  }
}

// ─── Image ────────────────────────────────────────────────────────────────────
class _ImageWidget extends StatelessWidget {
  final DocBlock block;
  const _ImageWidget({required this.block});

  @override
  Widget build(BuildContext context) {
    if (block.imageBytes == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: _buildImage(block.imageBytes!, block.imageExt ?? 'png'),
            ),
          ),
          if (block.imageCaption != null && block.imageCaption!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              block.imageCaption!,
              style: const TextStyle(
                fontSize: 11,
                color: DocTheme.textSecondary,
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildImage(Uint8List bytes, String ext) {
    if ([
      'jpg',
      'jpeg',
      'png',
      'gif',
      'webp',
      'bmp',
    ].contains(ext.toLowerCase())) {
      return Image.memory(
        bytes,
        fit: BoxFit.contain,
        errorBuilder:
            (BuildContext context, Object error, StackTrace? stackTrace) =>
                _brokenImage(),
      );
    }
    return _brokenImage();
  }

  Widget _brokenImage() {
    return Container(
      height: 120,
      color: Colors.grey.shade100,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_outlined, color: Colors.grey, size: 36),
            SizedBox(height: 6),
            Text(
              'Image could not be displayed',
              style: TextStyle(color: Colors.grey, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Table ────────────────────────────────────────────────────────────────────
class _TableWidget extends StatelessWidget {
  final DocBlock block;
  const _TableWidget({required this.block});

  @override
  Widget build(BuildContext context) {
    final rows = block.tableRows!;
    if (rows.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        border: Border.all(color: DocTheme.tableBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.hardEdge,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: IntrinsicWidth(
          child: Column(
            children: rows.asMap().entries.map((entry) {
              final rowIdx = entry.key;
              final row = entry.value;
              final isHeader = rowIdx == 0;
              final isAlt = !isHeader && rowIdx % 2 == 0;

              return Container(
                color: isHeader
                    ? DocTheme.tableHeaderBg
                    : isAlt
                    ? DocTheme.tableAltRow
                    : Colors.white,
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: row.cells.asMap().entries.map((ce) {
                      final colIdx = ce.key;
                      final cell = ce.value;
                      final isLast = colIdx == row.cells.length - 1;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          border: Border(
                            right: isLast
                                ? BorderSide.none
                                : BorderSide(
                                    color: isHeader
                                        ? Colors.white24
                                        : DocTheme.tableBorder,
                                  ),
                            bottom: rowIdx == rows.length - 1
                                ? BorderSide.none
                                : BorderSide(
                                    color: isHeader
                                        ? Colors.white24
                                        : DocTheme.tableBorder,
                                  ),
                          ),
                        ),
                        child: Text(
                          cell.plainText,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isHeader
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: isHeader
                                ? Colors.white
                                : DocTheme.textPrimary,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

// ─── Page Break ───────────────────────────────────────────────────────────────
class _PageBreakWidget extends StatelessWidget {
  final DocBlock block;
  const _PageBreakWidget({required this.block});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Row(
        children: [
          Expanded(child: Divider(color: DocTheme.dividerColor, thickness: 1)),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: DocTheme.accentLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: DocTheme.accent.withValues(alpha: 0.3)),
            ),
            child: Text(
              'Page ${block.pageNumber ?? ''}',
              style: const TextStyle(
                fontSize: 10,
                color: DocTheme.accent,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(child: Divider(color: DocTheme.dividerColor, thickness: 1)),
        ],
      ),
    );
  }
}

class _DividerWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Divider(color: DocTheme.dividerColor, thickness: 1),
    );
  }
}

// ─── Rich Text with inline formatting ────────────────────────────────────────
class _RichTextWidget extends StatelessWidget {
  final List<TextRun> runs;
  final TextStyle defaultStyle;
  final String alignment;

  const _RichTextWidget({
    required this.runs,
    required this.defaultStyle,
    this.alignment = 'left',
  });

  @override
  Widget build(BuildContext context) {
    if (runs.isEmpty) return const SizedBox.shrink();

    final spans = runs.map((run) {
      Color? textColor;
      if (run.color != null) {
        try {
          final hex = run.color!.replaceAll('#', '');
          if (hex.length == 6) {
            textColor = Color(int.parse('FF$hex', radix: 16));
          }
        } catch (_) {}
      }

      Color? bg;
      if (run.highlight != null) {
        try {
          final hex = run.highlight!.replaceAll('#', '');
          if (hex.length >= 6) {
            bg = Color(int.parse('FF${hex.substring(0, 6)}', radix: 16));
          }
        } catch (_) {}
      }

      TextDecoration deco = TextDecoration.none;
      if (run.isUnderline && run.isStrike) {
        deco = TextDecoration.combine([
          TextDecoration.underline,
          TextDecoration.lineThrough,
        ]);
      } else if (run.isUnderline) {
        deco = TextDecoration.underline;
      } else if (run.isStrike) {
        deco = TextDecoration.lineThrough;
      }

      return TextSpan(
        text: run.text,
        style: defaultStyle.copyWith(
          fontWeight: run.isBold ? FontWeight.bold : null,
          fontStyle: run.isItalic ? FontStyle.italic : null,
          decoration: deco,
          fontSize: run.fontSize ?? defaultStyle.fontSize,
          color: textColor ?? defaultStyle.color,
          backgroundColor: bg,
        ),
      );
    }).toList();

    TextAlign align;
    switch (alignment) {
      case 'center':
        align = TextAlign.center;
        break;
      case 'right':
        align = TextAlign.right;
        break;
      case 'justify':
        align = TextAlign.justify;
        break;
      default:
        align = TextAlign.left;
    }

    return SelectableText.rich(TextSpan(children: spans), textAlign: align);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  PPTX RENDERER
// ═══════════════════════════════════════════════════════════════════════════════

class PptxRenderer extends StatefulWidget {
  final ParsedDocument doc;
  final bool isEditMode;
  const PptxRenderer({super.key, required this.doc, this.isEditMode = false});

  @override
  State<PptxRenderer> createState() => _PptxRendererState();
}

class _PptxRendererState extends State<PptxRenderer> {
  int _current = 0;
  final PageController _pageCtrl = PageController();
  bool _showThumbnails = false;
  bool _isSidebarOpen = false;

  List<ParsedSlide> get slides => widget.doc.slides ?? [];

  @override
  Widget build(BuildContext context) {
    if (slides.isEmpty) {
      return const Center(child: Text('No slides found.'));
    }

    return Column(
      children: [
        // Top info bar
        Container(
          color: const Color(0xFF0F172A),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.slideshow, color: Colors.white54, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.doc.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${_current + 1} / ${slides.length}',
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
              const SizedBox(width: 12),
              InkWell(
                onTap: () => setState(() => _isSidebarOpen = !_isSidebarOpen),
                child: Icon(
                  _isSidebarOpen ? Icons.menu_open : Icons.menu,
                  color: Colors.white70,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              InkWell(
                onTap: () => setState(() => _showThumbnails = !_showThumbnails),
                child: Icon(
                  _showThumbnails
                      ? Icons.view_agenda_outlined
                      : Icons.grid_view_outlined,
                  color: Colors.white70,
                  size: 18,
                ),
              ),
            ],
          ),
        ),

        // Main content
        Expanded(
          child: _showThumbnails
              ? _buildThumbnailGrid()
              : Row(
                  children: [
                    // Slide panel
                    if (_isSidebarOpen) _buildSidePanel(),
                    // Main slide view
                    Expanded(child: _buildMainSlide()),
                  ],
                ),
        ),

        // Bottom navigation
        if (!_showThumbnails) _buildBottomNav(),
      ],
    );
  }

  Widget _buildSidePanel() {
    return Container(
      width: 90,
      color: const Color(0xFF1E293B),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: slides.length,
        itemBuilder: (_, i) {
          final isSelected = i == _current;
          return GestureDetector(
            onTap: () {
              setState(() => _current = i);
              _pageCtrl.jumpToPage(i);
            },
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(
                  color: isSelected ? DocTheme.accent : Colors.transparent,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Stack(
                children: [
                  _SlideMiniature(slide: slides[i]),
                  Positioned(
                    bottom: 2,
                    right: 4,
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        fontSize: 9,
                        color: isSelected ? DocTheme.accent : Colors.white54,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMainSlide() {
    return Container(
      color: const Color(0xFFF1F5F9), // Light background behind slide
      child: PageView.builder(
        controller: _pageCtrl,
        onPageChanged: (i) => setState(() => _current = i),
        itemCount: slides.length,
        itemBuilder: (_, i) =>
            _SlideView(slide: slides[i], isEditMode: widget.isEditMode),
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      color: const Color(0xFF0F172A),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.first_page, color: Colors.white),
            onPressed: _current > 0
                ? () {
                    _pageCtrl.jumpToPage(0);
                    setState(() => _current = 0);
                  }
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_left, color: Colors.white),
            onPressed: _current > 0
                ? () {
                    _pageCtrl.previousPage(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                    );
                  }
                : null,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Slide ${_current + 1} of ${slides.length}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, color: Colors.white),
            onPressed: _current < slides.length - 1
                ? () {
                    _pageCtrl.nextPage(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                    );
                  }
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.last_page, color: Colors.white),
            onPressed: _current < slides.length - 1
                ? () {
                    _pageCtrl.jumpToPage(slides.length - 1);
                    setState(() => _current = slides.length - 1);
                  }
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildThumbnailGrid() {
    return Container(
      color: const Color(0xFF1E293B),
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 16 / 9,
        ),
        itemCount: slides.length,
        itemBuilder: (_, i) {
          final isSelected = i == _current;
          return GestureDetector(
            onTap: () {
              setState(() {
                _current = i;
                _showThumbnails = false;
              });
              _pageCtrl.jumpToPage(i);
            },
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: isSelected ? DocTheme.accent : Colors.white24,
                  width: isSelected ? 2 : 1,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: _SlideMiniature(slide: slides[i]),
                  ),
                  Positioned(
                    bottom: 4,
                    left: 0,
                    right: 0,
                    child: Text(
                      'Slide ${i + 1}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Full Slide View ──────────────────────────────────────────────────────────
class _SlideView extends StatelessWidget {
  final ParsedSlide slide;
  final bool isEditMode;
  const _SlideView({required this.slide, this.isEditMode = false});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: _buildSlideContent(),
          ),
        ),
      ),
    );
  }

  Widget _buildSlideContent() {
    final images = slide.blocks
        .where((b) => b.type == BlockType.image)
        .toList();
    final nonImages = slide.blocks
        .where((b) => b.type != BlockType.image)
        .toList();
    final heading = nonImages
        .where(
          (b) => b.type == BlockType.heading1 || b.type == BlockType.heading2,
        )
        .toList();
    final body = nonImages
        .where(
          (b) => b.type != BlockType.heading1 && b.type != BlockType.heading2,
        )
        .toList();

    if (images.isNotEmpty && nonImages.isEmpty) {
      // Image-only slide
      return Image.memory(
        images.first.imageBytes!,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) =>
            const Icon(Icons.broken_image, color: Colors.white),
      );
    }

    return Stack(
      children: [
        // Decorative accent
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(height: 4, color: DocTheme.accent),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: DocTheme.accent.withValues(alpha: 0.05),
              shape: BoxShape.circle,
            ),
          ),
        ),

        // Content
        Padding(
          padding: const EdgeInsets.fromLTRB(40, 32, 40, 28),
          child: images.isNotEmpty
              ? Row(
                  children: [
                    Expanded(
                      child: _SlideTextColumn(
                        heading: heading,
                        body: body,
                        isEditMode: isEditMode,
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(child: _SlideImages(images: images)),
                  ],
                )
              : _SlideTextColumn(
                  heading: heading,
                  body: body,
                  isEditMode: isEditMode,
                ),
        ),

        // Slide number
        Positioned(
          bottom: 8,
          right: 14,
          child: Text(
            '${slide.index}',
            style: TextStyle(
              color: Colors.black.withValues(alpha: 0.4),
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }
}

class _SlideTextColumn extends StatelessWidget {
  final List<DocBlock> heading;
  final List<DocBlock> body;
  final bool isEditMode;
  const _SlideTextColumn({
    required this.heading,
    required this.body,
    this.isEditMode = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...heading.map(
          (b) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: isEditMode
                ? TextField(
                    controller: TextEditingController(text: b.plainText),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: DocTheme.textPrimary,
                    ),
                    decoration: const InputDecoration(border: InputBorder.none),
                    onChanged: (v) => b.plainText = v,
                  )
                : _RichTextWidget(
                    runs: b.runs,
                    defaultStyle: TextStyle(
                      fontSize: b.type == BlockType.heading1 ? 24 : 18,
                      fontWeight: FontWeight.bold,
                      color: DocTheme.textPrimary,
                      height: 1.3,
                    ),
                  ),
          ),
        ),
        if (heading.isNotEmpty)
          Container(
            height: 2,
            width: 40,
            color: DocTheme.accent,
            margin: const EdgeInsets.only(bottom: 14),
          ),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: body
                  .map(
                    (b) => isEditMode
                        ? TextField(
                            controller: TextEditingController(
                              text: b.plainText,
                            ),
                            maxLines: null,
                            style: const TextStyle(
                              fontSize: 13,
                              color: DocTheme.textPrimary,
                            ),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                            ),
                            onChanged: (v) => b.plainText = v,
                          )
                        : _buildBodyBlock(b),
                  )
                  .toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBodyBlock(DocBlock b) {
    if (b.type == BlockType.bulletPoint) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 7, right: 10),
              width: 5,
              height: 5,
              decoration: const BoxDecoration(
                color: DocTheme.accent,
                shape: BoxShape.circle,
              ),
            ),
            Expanded(
              child: _RichTextWidget(
                runs: b.runs,
                defaultStyle: const TextStyle(
                  fontSize: 16,
                  color: DocTheme.textPrimary,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (b.type == BlockType.table) {
      return _TableWidget(block: b);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: _RichTextWidget(
        runs: b.runs,
        defaultStyle: const TextStyle(
          fontSize: 12,
          color: Colors.white70,
          height: 1.6,
        ),
      ),
    );
  }
}

class _SlideImages extends StatelessWidget {
  final List<DocBlock> images;
  const _SlideImages({required this.images});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: images.take(2).map((img) {
        if (img.imageBytes == null) return const SizedBox.shrink();
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.memory(
                img.imageBytes!,
                fit: BoxFit.contain,
                errorBuilder:
                    (
                      BuildContext context,
                      Object error,
                      StackTrace? stackTrace,
                    ) => const Icon(Icons.broken_image, color: Colors.white38),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─── Slide Miniature (side panel thumbnail) ───────────────────────────────────
class _SlideMiniature extends StatelessWidget {
  final ParsedSlide slide;
  const _SlideMiniature({required this.slide});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1E3A5F), Color(0xFF0F172A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.all(6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (slide.title != null)
            Text(
              slide.title!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 6,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: 2),
          ...slide.blocks
              .where(
                (b) =>
                    b.type == BlockType.paragraph ||
                    b.type == BlockType.bulletPoint,
              )
              .take(3)
              .map(
                (b) => Padding(
                  padding: const EdgeInsets.only(bottom: 1),
                  child: Text(
                    b.plainText ?? '',
                    style: const TextStyle(color: Colors.white38, fontSize: 5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  XLSX RENDERER
// ═══════════════════════════════════════════════════════════════════════════════

class XlsxRenderer extends StatefulWidget {
  final ParsedDocument doc;
  final bool isEditMode;
  const XlsxRenderer({super.key, required this.doc, this.isEditMode = false});

  @override
  State<XlsxRenderer> createState() => _XlsxRendererState();
}

class _XlsxRendererState extends State<XlsxRenderer>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  String _search = '';
  final _searchCtrl = TextEditingController();

  List<SheetData> get sheets => widget.doc.sheets ?? [];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: sheets.length, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (sheets.isEmpty) {
      return const Center(child: Text('No sheets found.'));
    }

    return Column(
      children: [
        // Header
        Container(
          color: DocTheme.sheetHeaderBg,
          child: Column(
            children: [
              // File info
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Row(
                  children: [
                    const Icon(
                      Icons.table_chart,
                      color: Colors.white,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.doc.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${sheets.length} sheet${sheets.length > 1 ? 's' : ''}',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              // Search bar
              Padding(
                padding: const EdgeInsets.all(10),
                child: Container(
                  height: 34,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: 'Search in sheet...',
                      hintStyle: TextStyle(color: Colors.white38),
                      prefixIcon: Icon(
                        Icons.search,
                        color: Colors.white38,
                        size: 18,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                    ),
                    onChanged: (v) => setState(() => _search = v.toLowerCase()),
                  ),
                ),
              ),
              // Sheet tabs
              if (sheets.length > 1)
                TabBar(
                  controller: _tabCtrl,
                  isScrollable: true,
                  indicatorColor: DocTheme.accent,
                  indicatorWeight: 3,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white54,
                  labelStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  tabs: sheets.map((s) => Tab(text: s.name)).toList(),
                ),
            ],
          ),
        ),

        // Sheet content
        Expanded(
          child: sheets.length == 1
              ? _buildSheet(sheets[0])
              : TabBarView(
                  controller: _tabCtrl,
                  children: sheets.map((s) => _buildSheet(s)).toList(),
                ),
        ),
      ],
    );
  }

  Widget _buildSheet(SheetData sheet) {
    var rows = sheet.rows;
    if (_search.isNotEmpty) {
      rows = rows
          .where((r) => r.any((c) => c.toLowerCase().contains(_search)))
          .toList();
    }

    if (rows.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.table_rows_outlined, size: 48, color: Colors.grey),
            SizedBox(height: 12),
            Text('No data found', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    final maxCols = rows.fold(0, (m, r) => r.length > m ? r.length : m);
    final colLetters = List.generate(maxCols, (i) => _colLetter(i));

    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Column letter header
            _buildColHeader(colLetters, maxCols),
            // Data rows
            ...rows.asMap().entries.map((entry) {
              final rowIdx = entry.key;
              final isHeader = rowIdx == 0;
              final isAlt = !isHeader && rowIdx % 2 == 0;
              return _buildRow(
                entry.value,
                rowIdx + 1,
                maxCols,
                isHeader: isHeader,
                isAlt: isAlt,
                onCellChanged: (colIdx, newValue) {
                  setState(() {
                    if (colIdx < entry.value.length) {
                      entry.value[colIdx] = newValue;
                    }
                  });
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildColHeader(List<String> letters, int count) {
    return Row(
      children: [
        // Row number column placeholder
        Container(
          width: 44,
          height: 28,
          color: const Color(0xFFE8ECF0),
          alignment: Alignment.center,
          child: const Text(
            '#',
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ...letters.map(
          (l) => Container(
            width: 200,
            height: 28,
            color: const Color(0xFFE8ECF0),
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              border: Border(
                right: BorderSide(color: DocTheme.sheetBorder),
                bottom: BorderSide(color: DocTheme.sheetBorder),
              ),
            ),
            child: Text(
              l,
              style: const TextStyle(
                fontSize: 10,
                color: Colors.grey,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRow(
    List<String> cells,
    int rowNum,
    int maxCols, {
    bool isHeader = false,
    bool isAlt = false,
    Function(int, String)? onCellChanged,
  }) {
    final bg = isHeader
        ? DocTheme.sheetHeaderBg
        : isAlt
        ? DocTheme.sheetAltRow
        : Colors.white;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Row number
          Container(
            width: 44,
            color: const Color(0xFFE8ECF0),
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              border: Border(right: BorderSide(color: DocTheme.sheetBorder)),
            ),
            child: Text(
              '$rowNum',
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ),
          // Data cells
          ...List.generate(maxCols, (i) {
            final value = i < cells.length ? cells[i] : '';
            final isHighlight =
                _search.isNotEmpty && value.toLowerCase().contains(_search);

            return Container(
              width: 200,
              color: isHighlight ? Colors.yellow.shade100 : bg,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(color: DocTheme.sheetBorder, width: 0.5),
                  bottom: BorderSide(color: DocTheme.sheetBorder, width: 0.5),
                ),
              ),
              child: widget.isEditMode && !isHeader
                  ? TextFormField(
                      initialValue: value,
                      style: const TextStyle(
                        fontSize: 12,
                        color: DocTheme.textPrimary,
                      ),
                      maxLines: null,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: (v) => onCellChanged?.call(i, v),
                    )
                  : Text(
                      value,
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isHeader
                            ? FontWeight.bold
                            : FontWeight.w400,
                        color: isHeader
                            ? DocTheme.sheetHeaderText
                            : DocTheme.textPrimary,
                      ),
                    ),
            );
          }),
        ],
      ),
    );
  }

  String _colLetter(int index) {
    String result = '';
    int i = index;
    do {
      result = String.fromCharCode(65 + i % 26) + result;
      i = i ~/ 26 - 1;
    } while (i >= 0);
    return result;
  }
}
