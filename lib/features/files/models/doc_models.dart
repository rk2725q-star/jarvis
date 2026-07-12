import 'dart:typed_data';

// ─── Block Types ──────────────────────────────────────────────────────────────
enum BlockType {
  heading1,
  heading2,
  heading3,
  paragraph,
  bulletPoint,
  numberedPoint,
  table,
  image,
  pageBreak,
  divider,
  codeBlock,
  quote,
  emptyLine,
}

// ─── Text Run (inline formatting) ────────────────────────────────────────────
class TextRun {
  final String text;
  final bool isBold;
  final bool isItalic;
  final bool isUnderline;
  final bool isStrike;
  final double? fontSize;
  final String? color; // hex like '#FF0000'
  final String? highlight; // hex background
  final bool isSuperscript;
  final bool isSubscript;
  final String? hyperlink;

  const TextRun({
    required this.text,
    this.isBold = false,
    this.isItalic = false,
    this.isUnderline = false,
    this.isStrike = false,
    this.fontSize,
    this.color,
    this.highlight,
    this.isSuperscript = false,
    this.isSubscript = false,
    this.hyperlink,
  });
}

// ─── Table Cell ───────────────────────────────────────────────────────────────
class TableCell {
  final List<TextRun> runs;
  final int colSpan;
  final int rowSpan;
  final bool isHeader;
  final String? bgColor;

  const TableCell({
    required this.runs,
    this.colSpan = 1,
    this.rowSpan = 1,
    this.isHeader = false,
    this.bgColor,
  });

  String get plainText => runs.map((r) => r.text).join();
}

// ─── Table Row ────────────────────────────────────────────────────────────────
class TableRow {
  final List<TableCell> cells;
  const TableRow(this.cells);
}

// ─── Slide / Sheet specific ───────────────────────────────────────────────────
class SheetData {
  final String name;
  final List<List<String>> rows; // [rowIndex][colIndex]
  final int maxCols;
  SheetData({required this.name, required this.rows, required this.maxCols});
}

// ─── Main Document Block ──────────────────────────────────────────────────────
class DocBlock {
  final BlockType type;

  // Text content (paragraph / heading / bullet)
  final List<TextRun> runs;
  String? plainText; // fast access

  // Alignment: 'left' | 'center' | 'right' | 'justify'
  final String alignment;

  // Indent level (bullets/numbered)
  final int indentLevel;
  final int? bulletNumber;

  // Image
  final Uint8List? imageBytes;
  final String? imageExt;
  final double? imageWidth;
  final double? imageHeight;
  final String? imageCaption;

  // Table
  final List<TableRow>? tableRows;

  // Code
  final String? language;

  // Page info
  final int? pageNumber;

  DocBlock({
    required this.type,
    this.runs = const [],
    this.plainText,
    this.alignment = 'left',
    this.indentLevel = 0,
    this.bulletNumber,
    this.imageBytes,
    this.imageExt,
    this.imageWidth,
    this.imageHeight,
    this.imageCaption,
    this.tableRows,
    this.language,
    this.pageNumber,
  });

  // convenience
  bool get hasContent =>
      runs.isNotEmpty || imageBytes != null || tableRows != null;
}

// ─── Parsed Document ──────────────────────────────────────────────────────────
class ParsedDocument {
  final String title;
  final String format; // 'docx' | 'pptx' | 'xlsx' | 'txt' | ...
  final List<DocBlock> blocks;

  // PPTX specific
  final List<ParsedSlide>? slides;

  // XLSX specific
  final List<SheetData>? sheets;

  // Metadata
  final String? author;
  final String? createdDate;
  final int? pageCount;
  final int imageCount;

  const ParsedDocument({
    required this.title,
    required this.format,
    required this.blocks,
    this.slides,
    this.sheets,
    this.author,
    this.createdDate,
    this.pageCount,
    this.imageCount = 0,
  });
}

class ParsedSlide {
  final int index;
  final String? title;
  final List<DocBlock> blocks;
  final Uint8List? thumbnail;
  final String? notes;
  final String? layoutName;

  const ParsedSlide({
    required this.index,
    this.title,
    required this.blocks,
    this.thumbnail,
    this.notes,
    this.layoutName,
  });
}
