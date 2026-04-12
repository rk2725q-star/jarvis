import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import '../models/doc_models.dart';

class PptxParser {
  final Archive _archive;
  final Map<String, Uint8List> _images = {};
  final Map<String, Map<String, String>> _slideRels = {};

  PptxParser(this._archive) {
    _loadImages();
  }

  void _loadImages() {
    for (final file in _archive) {
      if (file.name.contains('/media/')) {
        _images[file.name] = Uint8List.fromList(file.content as List<int>);
      }
    }
  }

  Map<String, String> _loadSlideRels(int slideNum) {
    final key = 'ppt/slides/_rels/slide$slideNum.xml.rels';
    if (_slideRels.containsKey(key)) return _slideRels[key]!;

    final relFile = _archive.findFile(key);
    final rels    = <String, String>{};
    if (relFile != null) {
      try {
        final doc = XmlDocument.parse(
            utf8.decode(relFile.content as List<int>));
        for (final rel in doc.findAllElements('Relationship')) {
          final id     = rel.getAttribute('Id')     ?? '';
          final target = rel.getAttribute('Target') ?? '';
          rels[id] = target.contains('../media/')
              ? 'ppt/media/${target.split('/').last}'
              : target;
        }
      } catch (_) {}
    }
    _slideRels[key] = rels;
    return rels;
  }

  ParsedDocument parse(String fileName) {
    // Discover slide count
    final slideFiles = _archive.files
        .where((f) =>
            f.name.startsWith('ppt/slides/slide') &&
            f.name.endsWith('.xml') &&
            !f.name.contains('_rels'))
        .toList()
      ..sort((a, b) => _slideNum(a.name).compareTo(_slideNum(b.name)));

    if (slideFiles.isEmpty) {
      return ParsedDocument(
        title: fileName,
        format: 'pptx',
        blocks: [],
        slides: [],
      );
    }

    final slides  = <ParsedSlide>[];
    int imgCount   = 0;

    for (int i = 0; i < slideFiles.length; i++) {
      final slideNum = _slideNum(slideFiles[i].name);
      final rels     = _loadSlideRels(slideNum);
      final slide    = _parseSlide(slideFiles[i], i + 1, rels);
      imgCount += slide.blocks.where((b) => b.type == BlockType.image).length;
      slides.add(slide);
    }

    final title = _extractTitle() ?? fileName;
    return ParsedDocument(
      title:      title,
      format:     'pptx',
      blocks:     [],
      slides:     slides,
      pageCount:  slides.length,
      imageCount: imgCount,
    );
  }

  int _slideNum(String name) {
    final match = RegExp(r'slide(\d+)\.xml').firstMatch(name);
    return int.tryParse(match?.group(1) ?? '0') ?? 0;
  }

  ParsedSlide _parseSlide(
      ArchiveFile slideFile, int index, Map<String, String> rels) {
    late XmlDocument doc;
    try {
      doc = XmlDocument.parse(
          utf8.decode(slideFile.content as List<int>));
    } catch (_) {
      return ParsedSlide(index: index, blocks: []);
    }

    final blocks = <DocBlock>[];
    String? slideTitle;

    // Get all shapes (sp) and picture (pic) elements
    final spTree = doc.findAllElements('p:spTree').firstOrNull;
    if (spTree == null) return ParsedSlide(index: index, blocks: blocks);

    for (final child in spTree.childElements) {
      switch (child.name.local) {
        case 'sp':
          final block = _parseShape(child, index == 1);
          if (block != null) {
            // First heading = slide title
            if (slideTitle == null &&
                block.type == BlockType.heading1) {
              slideTitle = block.plainText;
            }
            blocks.add(block);
          }
          break;
        case 'pic':
          final imgBlock = _parsePicture(child, rels);
          if (imgBlock != null) blocks.add(imgBlock);
          break;
        case 'graphicFrame':
          // Tables inside slides
          final tblBlock = _parseGraphicFrame(child);
          if (tblBlock != null) blocks.add(tblBlock);
          break;
        case 'grpSp':
          // Group shape — recurse
          _parseGroupShape(child, rels, blocks);
          break;
      }
    }

    // Presenter notes
    final notes = _extractNotes(index);

    return ParsedSlide(
      index:      index,
      title:      slideTitle,
      blocks:     blocks,
      notes:      notes,
      layoutName: _getLayoutName(doc),
    );
  }

  DocBlock? _parseShape(XmlElement sp, bool isFirstSlide) {
    final nvSpPr = sp.findAllElements('p:nvSpPr').firstOrNull;
    final ph      = nvSpPr?.findAllElements('p:ph').firstOrNull;
    final phType  = ph?.getAttribute('type') ?? '';

    // Determine block type from placeholder
    BlockType blockType = BlockType.paragraph;
    if (phType == 'title' || phType == 'ctrTitle') {
      blockType = BlockType.heading1;
    } else if (phType == 'subTitle' || phType == 'body') {
      blockType = BlockType.paragraph;
    }

    final txBody = sp.findAllElements('p:txBody').firstOrNull;
    if (txBody == null) return null;

    final allRuns  = <TextRun>[];
    String? mainText;
    BlockType firstParaType = blockType;
    bool isFirst = true;

    for (final para in txBody.findAllElements('a:p')) {
      final pRuns = _parseTextParagraph(para, isFirst ? blockType : BlockType.paragraph);
      if (isFirst && pRuns.isNotEmpty) {
        firstParaType = _detectParaType(para, blockType);
        isFirst = false;
      }
      allRuns.addAll(pRuns);
      allRuns.add(const TextRun(text: '\n'));
    }

    // Clean trailing newlines
    while (allRuns.isNotEmpty && allRuns.last.text == '\n') {
      allRuns.removeLast();
    }

    if (allRuns.isEmpty) return null;

    mainText = allRuns.map((r) => r.text).join().trim();
    if (mainText.isEmpty) return null;

    return DocBlock(
      type:      firstParaType,
      runs:      allRuns,
      plainText: mainText,
    );
  }

  BlockType _detectParaType(XmlElement para, BlockType fallback) {
    final buChar = para.findAllElements('a:buChar').firstOrNull;
    final buFont = para.findAllElements('a:buFont').firstOrNull;
    final buNone = para.findAllElements('a:buNone').firstOrNull;
    if (buNone != null) return fallback;
    if (buChar != null || buFont != null) return BlockType.bulletPoint;
    return fallback;
  }

  List<TextRun> _parseTextParagraph(XmlElement para, BlockType type) {
    final runs = <TextRun>[];
    for (final elem in para.children.whereType<XmlElement>()) {
      if (elem.name.local == 'r') {
        final rPr = elem.findAllElements('a:rPr').firstOrNull;
        final t   = elem.findAllElements('a:t').firstOrNull?.innerText ?? '';
        if (t.isEmpty) continue;

        bool bold   = rPr?.getAttribute('b') == '1';
        bool italic = rPr?.getAttribute('i') == '1';
        bool under  = rPr?.getAttribute('u') == 'sng';
        double? sz;
        String? color;

        final szAttr = rPr?.getAttribute('sz');
        if (szAttr != null) sz = (double.tryParse(szAttr) ?? 0) / 100;

        final solidFill = rPr?.findAllElements('a:solidFill').firstOrNull;
        final srgb       = solidFill?.findAllElements('a:srgbClr').firstOrNull;
        if (srgb != null) {
          color = '#${srgb.getAttribute('val') ?? ''}';
        }

        runs.add(TextRun(
          text:        t,
          isBold:      bold || type == BlockType.heading1,
          isItalic:    italic,
          isUnderline: under,
          fontSize:    sz,
          color:       color,
        ));
      } else if (elem.name.local == 'm' || elem.name.local == 'oMath') {
        _parseMath(elem, runs);
      }
    }
    return runs;
  }

  void _parseMath(XmlElement mathEl, List<TextRun> runs) {
    final text = mathEl.descendantElements
        .where((e) => e.name.local == 't')
        .map((e) => e.innerText)
        .join();
    if (text.isNotEmpty) {
      runs.add(TextRun(
        text: "\$ $text \$",
        isItalic: true,
      ));
    }
  }

  DocBlock? _parsePicture(XmlElement pic, Map<String, String> rels) {
    final blip   = pic.findAllElements('a:blip').firstOrNull;
    final rEmbed = blip?.getAttribute('r:embed') ?? '';
    final path   = rels[rEmbed];
    if (path == null) return null;

    final imgData = _images[path];
    if (imgData == null) return null;

    final ext = path.split('.').last.toLowerCase();

    // Try to get size from xfrm
    final ext2 = pic.findAllElements('a:ext').firstOrNull;
    double? w, h;
    if (ext2 != null) {
      final cx = int.tryParse(ext2.getAttribute('cx') ?? '');
      final cy = int.tryParse(ext2.getAttribute('cy') ?? '');
      if (cx != null) w = cx / 914400 * 96;
      if (cy != null) h = cy / 914400 * 96;
    }

    return DocBlock(
      type:        BlockType.image,
      imageBytes:  imgData,
      imageExt:    ext,
      imageWidth:  w,
      imageHeight: h,
    );
  }

  DocBlock? _parseGraphicFrame(XmlElement frame) {
    final tbl = frame.findAllElements('a:tbl').firstOrNull;
    if (tbl == null) return null;

    final rows      = <TableRow>[];
    bool isFirstRow = true;

    for (final tr in tbl.findAllElements('a:tr')) {
      final cells = <TableCell>[];
      for (final tc in tr.findAllElements('a:tc')) {
        final runs = <TextRun>[];
        for (final para in tc.findAllElements('a:p')) {
          for (final r in para.findAllElements('a:r')) {
            final t = r.findAllElements('a:t').firstOrNull?.innerText ?? '';
            if (t.isNotEmpty) runs.add(TextRun(text: t));
          }
        }
        cells.add(TableCell(runs: runs, isHeader: isFirstRow));
      }
      if (cells.isNotEmpty) rows.add(TableRow(cells));
      isFirstRow = false;
    }

    if (rows.isEmpty) return null;
    return DocBlock(type: BlockType.table, tableRows: rows);
  }

  void _parseGroupShape(
      XmlElement grpSp, Map<String, String> rels, List<DocBlock> blocks) {
    for (final child in grpSp.childElements) {
      switch (child.name.local) {
        case 'sp':
          final b = _parseShape(child, false);
          if (b != null) blocks.add(b);
          break;
        case 'pic':
          final b = _parsePicture(child, rels);
          if (b != null) blocks.add(b);
          break;
        case 'grpSp':
          _parseGroupShape(child, rels, blocks);
          break;
      }
    }
  }

  String? _extractNotes(int slideNum) {
    final notesFile =
        _archive.findFile('ppt/notesSlides/notesSlide$slideNum.xml');
    if (notesFile == null) return null;
    try {
      final doc = XmlDocument.parse(
          utf8.decode(notesFile.content as List<int>));
      final text = doc.findAllElements('a:t').map((e) => e.innerText).join(' ');
      return text.trim().isEmpty ? null : text.trim();
    } catch (_) {
      return null;
    }
  }

  String? _getLayoutName(XmlDocument doc) {
    return doc.findAllElements('p:cSld')
        .firstOrNull
        ?.getAttribute('name');
  }

  String? _extractTitle() {
    final coreFile = _archive.findFile('docProps/core.xml');
    if (coreFile == null) return null;
    try {
      final doc = XmlDocument.parse(
          utf8.decode(coreFile.content as List<int>));
      return doc.findAllElements('dc:title').firstOrNull?.innerText;
    } catch (_) {
      return null;
    }
  }
}
