import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import '../models/doc_models.dart';

class DocxParser {
  final Archive _archive;
  final Map<String, Uint8List> _images = {};
  final Map<String, String> _rels = {};
  final Map<String, String> _hyperlinks = {};

  DocxParser(this._archive) {
    _loadImages();
    _loadRels();
  }

  void _loadImages() {
    for (final file in _archive) {
      if (file.name.startsWith('word/media/')) {
        _images[file.name] = Uint8List.fromList(file.content as List<int>);
      }
    }
  }

  void _loadRels() {
    final relFile = _archive.findFile('word/_rels/document.xml.rels');
    if (relFile == null) return;
    try {
      final doc = XmlDocument.parse(utf8.decode(relFile.content as List<int>));
      for (final rel in doc.findAllElements('Relationship')) {
        final id = rel.getAttribute('Id') ?? '';
        final target = rel.getAttribute('Target') ?? '';
        if (target.startsWith('http')) {
          _hyperlinks[id] = target;
        } else {
          _rels[id] = target.startsWith('media/')
              ? 'word/$target'
              : 'word/$target';
        }
      }
    } catch (_) {}
  }

  ParsedDocument parse(String fileName) {
    final docFile = _archive.findFile('word/document.xml');
    if (docFile == null) {
      return ParsedDocument(
        title: fileName,
        format: 'docx',
        blocks: [
          DocBlock(
            type: BlockType.paragraph,
            plainText: 'Could not read document.',
          ),
        ],
      );
    }

    late XmlDocument doc;
    try {
      doc = XmlDocument.parse(utf8.decode(docFile.content as List<int>));
    } catch (e) {
      return ParsedDocument(
        title: fileName,
        format: 'docx',
        blocks: [
          DocBlock(type: BlockType.paragraph, plainText: 'Parse error: $e'),
        ],
      );
    }

    final blocks = <DocBlock>[];
    int imgCount = 0;
    int pageCount = 1;

    final body = doc.findAllElements('w:body').firstOrNull;
    if (body == null) {
      return ParsedDocument(title: fileName, format: 'docx', blocks: blocks);
    }

    for (final child in body.childElements) {
      switch (child.name.local) {
        case 'p':
          // Check for page break
          if (_hasPageBreak(child)) {
            pageCount++;
            blocks.add(
              DocBlock(type: BlockType.pageBreak, pageNumber: pageCount),
            );
          }
          final block = _parseParagraph(child);
          if (block != null) {
            if (block.type == BlockType.image) imgCount++;
            blocks.add(block);
          }
          break;
        case 'oMathPara':
        case 'oMath':
          final mathText = child.descendantElements
              .where((e) => e.name.local == 't')
              .map((e) => e.innerText)
              .join();
          if (mathText.isNotEmpty) {
            final latex = "\$ $mathText \$";
            blocks.add(
              DocBlock(
                type: BlockType.paragraph,
                runs: [TextRun(text: latex, isItalic: true)],
                plainText: latex,
              ),
            );
          }
          break;
        case 'tbl':
          final tbl = _parseTable(child);
          if (tbl != null) blocks.add(tbl);
          break;
        case 'sdt':
          // Structured document tag — recurse
          for (final p in child.findAllElements('w:p')) {
            final b = _parseParagraph(p);
            if (b != null) blocks.add(b);
          }
          break;
      }
    }

    // Extract title from core properties
    final title = _extractCoreProperty('dc:title') ?? fileName;
    final author = _extractCoreProperty('dc:creator');
    final created = _extractCoreProperty('dcterms:created');

    return ParsedDocument(
      title: title,
      format: 'docx',
      blocks: blocks,
      author: author,
      createdDate: created,
      pageCount: pageCount,
      imageCount: imgCount,
    );
  }

  bool _hasPageBreak(XmlElement para) {
    return para.findAllElements('w:pageBreakBefore').isNotEmpty ||
        para
            .findAllElements('w:br')
            .any((e) => e.getAttribute('w:type') == 'page');
  }

  DocBlock? _parseParagraph(XmlElement para) {
    // ── Image check ────────────────────────────────────────────────────────
    for (final drawing in para.findAllElements('w:drawing')) {
      final blip = drawing.findAllElements('a:blip').firstOrNull;
      if (blip != null) {
        final rEmbed = blip.getAttribute('r:embed') ?? '';
        final path = _rels[rEmbed];
        if (path != null) {
          final imgData = _images[path];
          if (imgData != null) {
            final ext = path.split('.').last.toLowerCase();
            // Try to get dimensions
            final ext2 = drawing.findAllElements('wp:extent').firstOrNull;
            double? w, h;
            if (ext2 != null) {
              final cx = int.tryParse(ext2.getAttribute('cx') ?? '');
              final cy = int.tryParse(ext2.getAttribute('cy') ?? '');
              if (cx != null) w = cx / 914400 * 96; // EMU to px
              if (cy != null) h = cy / 914400 * 96;
            }
            // Caption from descr attribute
            final nvPr = drawing.findAllElements('pic:cNvPr').firstOrNull;
            final caption = nvPr?.getAttribute('descr');
            return DocBlock(
              type: BlockType.image,
              imageBytes: imgData,
              imageExt: ext,
              imageWidth: w,
              imageHeight: h,
              imageCaption: caption,
            );
          }
        }
      }
    }

    // ── Style ──────────────────────────────────────────────────────────────
    final pPr = para.findAllElements('w:pPr').firstOrNull;
    final pStyle =
        pPr
            ?.findAllElements('w:pStyle')
            .firstOrNull
            ?.getAttribute('w:val')
            ?.toLowerCase() ??
        '';

    BlockType blockType = BlockType.paragraph;
    if (pStyle.contains('heading1') || pStyle == 'title') {
      blockType = BlockType.heading1;
    } else if (pStyle.contains('heading2') || pStyle == 'subtitle') {
      blockType = BlockType.heading2;
    } else if (pStyle.contains('heading3')) {
      blockType = BlockType.heading3;
    } else if (pStyle.contains('quote') || pStyle.contains('block')) {
      blockType = BlockType.quote;
    }

    // ── Alignment ─────────────────────────────────────────────────────────
    final jcEl = pPr?.findAllElements('w:jc').firstOrNull;
    String alignment = 'left';
    if (jcEl != null) {
      final val = jcEl.getAttribute('w:val') ?? 'left';
      alignment = val == 'both' ? 'justify' : val;
    }

    // ── Bullet / Numbered ─────────────────────────────────────────────────
    int indentLevel = 0;
    int? bulletNumber;
    final numPr = pPr?.findAllElements('w:numPr').firstOrNull;
    if (numPr != null) {
      final ilvl =
          int.tryParse(
            numPr
                    .findAllElements('w:ilvl')
                    .firstOrNull
                    ?.getAttribute('w:val') ??
                '0',
          ) ??
          0;
      final numId = numPr
          .findAllElements('w:numId')
          .firstOrNull
          ?.getAttribute('w:val');
      indentLevel = ilvl;
      // Heuristic: if numId exists, it's a list
      if (numId != null && numId != '0') {
        blockType = BlockType.bulletPoint;
      }
    }

    // Indent level from indentation
    final indEl = pPr?.findAllElements('w:ind').firstOrNull;
    if (indEl != null && blockType == BlockType.paragraph) {
      final left = int.tryParse(indEl.getAttribute('w:left') ?? '0') ?? 0;
      indentLevel = (left / 720).round().clamp(0, 6);
    }

    // ── Text Runs ─────────────────────────────────────────────────────────
    final runs = <TextRun>[];
    for (final elem in para.childElements) {
      if (elem.name.local == 'r') {
        final run = _parseRun(elem);
        if (run != null) runs.add(run);
      } else if (elem.name.local == 'hyperlink') {
        // Hyperlink runs
        final rId = elem.getAttribute('r:id') ?? '';
        final url = _hyperlinks[rId];
        for (final r in elem.findAllElements('w:r')) {
          final run = _parseRun(r, hyperlink: url);
          if (run != null) runs.add(run);
        }
      } else if (elem.name.local == 'ins') {
        // Track changes — accepted insertions
        for (final r in elem.findAllElements('w:r')) {
          final run = _parseRun(r);
          if (run != null) runs.add(run);
        }
      } else if (elem.name.local == 'oMath' || elem.name.local == 'oMathPara') {
        // Office Math ML equations - wrap in LaTeX-like markers for AI
        final mathText = elem.descendantElements
            .where((e) => e.name.local == 't')
            .map((e) => e.innerText)
            .join();
        if (mathText.isNotEmpty) {
          runs.add(TextRun(text: "\$ $mathText \$", isItalic: true));
        }
      }
    }

    final plainText = runs.map((r) => r.text).join();
    if (plainText.trim().isEmpty && blockType == BlockType.paragraph) {
      return DocBlock(type: BlockType.emptyLine);
    }

    return DocBlock(
      type: blockType,
      runs: runs,
      plainText: plainText,
      alignment: alignment,
      indentLevel: indentLevel,
      bulletNumber: bulletNumber,
    );
  }

  TextRun? _parseRun(XmlElement run, {String? hyperlink}) {
    final rPr = run.findAllElements('w:rPr').firstOrNull;

    // Skip deleted text
    if (run.findAllElements('w:del').isNotEmpty) return null;

    bool isBold = false;
    bool isItalic = false;
    bool isUnderline = false;
    bool isStrike = false;
    bool isSuperscript = false;
    bool isSubscript = false;
    double? fontSize;
    String? color;
    String? highlight;

    if (rPr != null) {
      isBold =
          rPr.findAllElements('w:b').isNotEmpty &&
          rPr.findAllElements('w:b').first.getAttribute('w:val') != 'false';
      isItalic = rPr.findAllElements('w:i').isNotEmpty;
      isUnderline =
          rPr.findAllElements('w:u').isNotEmpty &&
          rPr.findAllElements('w:u').first.getAttribute('w:val') != 'none';
      isStrike = rPr.findAllElements('w:strike').isNotEmpty;

      final vertAlign = rPr
          .findAllElements('w:vertAlign')
          .firstOrNull
          ?.getAttribute('w:val');
      isSuperscript = vertAlign == 'superscript';
      isSubscript = vertAlign == 'subscript';

      final szEl = rPr.findAllElements('w:sz').firstOrNull;
      if (szEl != null) {
        fontSize = (double.tryParse(szEl.getAttribute('w:val') ?? '') ?? 0) / 2;
      }

      final colorEl = rPr.findAllElements('w:color').firstOrNull;
      if (colorEl != null) {
        final c = colorEl.getAttribute('w:val');
        if (c != null && c != 'auto') color = '#$c';
      }

      final hlEl = rPr.findAllElements('w:highlight').firstOrNull;
      if (hlEl != null) {
        highlight = _colorNameToHex(hlEl.getAttribute('w:val') ?? '');
      }
    }

    final text = run.findAllElements('w:t').map((t) => t.innerText).join();

    if (text.isEmpty) return null;

    return TextRun(
      text: text,
      isBold: isBold,
      isItalic: isItalic,
      isUnderline: isUnderline,
      isStrike: isStrike,
      fontSize: fontSize,
      color: color,
      highlight: highlight,
      isSuperscript: isSuperscript,
      isSubscript: isSubscript,
      hyperlink: hyperlink,
    );
  }

  DocBlock? _parseTable(XmlElement tbl) {
    final rows = <TableRow>[];
    bool isFirstRow = true;

    for (final tr in tbl.findAllElements('w:tr')) {
      final cells = <TableCell>[];
      for (final tc in tr.findAllElements('w:tc')) {
        final tcPr = tc.findAllElements('w:tcPr').firstOrNull;
        final colSpan =
            int.tryParse(
              tcPr
                      ?.findAllElements('w:gridSpan')
                      .firstOrNull
                      ?.getAttribute('w:val') ??
                  '1',
            ) ??
            1;

        // Background
        final shdEl = tcPr?.findAllElements('w:shd').firstOrNull;
        String? bgColor;
        if (shdEl != null) {
          final fill = shdEl.getAttribute('w:fill');
          if (fill != null && fill != 'auto') bgColor = '#$fill';
        }

        // Cell runs
        final runs = <TextRun>[];
        for (final p in tc.findAllElements('w:p')) {
          for (final r in p.findAllElements('w:r')) {
            final run = _parseRun(r);
            if (run != null) runs.add(run);
          }
          runs.add(const TextRun(text: '\n'));
        }
        if (runs.isNotEmpty && runs.last.text == '\n') runs.removeLast();

        cells.add(
          TableCell(
            runs: runs,
            colSpan: colSpan,
            isHeader: isFirstRow,
            bgColor: bgColor,
          ),
        );
      }
      if (cells.isNotEmpty) rows.add(TableRow(cells));
      isFirstRow = false;
    }

    if (rows.isEmpty) return null;
    return DocBlock(type: BlockType.table, tableRows: rows);
  }

  String? _extractCoreProperty(String tag) {
    final coreFile = _archive.findFile('docProps/core.xml');
    if (coreFile == null) return null;
    try {
      final doc = XmlDocument.parse(utf8.decode(coreFile.content as List<int>));
      return doc.findAllElements(tag).firstOrNull?.innerText;
    } catch (_) {
      return null;
    }
  }

  String _colorNameToHex(String name) {
    const map = {
      'yellow': '#FFFF00',
      'green': '#00FF00',
      'cyan': '#00FFFF',
      'magenta': '#FF00FF',
      'blue': '#0000FF',
      'red': '#FF0000',
      'darkBlue': '#00008B',
      'darkRed': '#8B0000',
      'darkGreen': '#006400',
      'darkYellow': '#9B870C',
    };
    return map[name] ?? '#FFFF00';
  }
}
