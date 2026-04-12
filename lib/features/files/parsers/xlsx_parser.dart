import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import '../models/doc_models.dart';

class XlsxParser {
  final Archive _archive;
  List<String> _sharedStrings = [];
  final Map<String, String> _numberFormats = {};

  XlsxParser(this._archive) {
    _loadSharedStrings();
    _loadNumberFormats();
  }

  void _loadSharedStrings() {
    final file = _archive.findFile('xl/sharedStrings.xml');
    if (file == null) return;
    try {
      final doc = XmlDocument.parse(
          utf8.decode(file.content as List<int>));
      _sharedStrings = doc
          .findAllElements('si')
          .map((si) => si.findAllElements('t').map((t) => t.innerText).join())
          .toList();
    } catch (_) {}
  }

  void _loadNumberFormats() {
    final file = _archive.findFile('xl/styles.xml');
    if (file == null) return;
    try {
      final doc = XmlDocument.parse(
          utf8.decode(file.content as List<int>));
      for (final fmt in doc.findAllElements('numFmt')) {
        final id      = fmt.getAttribute('numFmtId')   ?? '';
        final fmtCode = fmt.getAttribute('formatCode') ?? '';
        _numberFormats[id] = fmtCode;
      }
    } catch (_) {}
  }

  ParsedDocument parse(String fileName) {
    // Discover sheets
    final workbookFile = _archive.findFile('xl/workbook.xml');
    final sheetNames   = <String>[];
    if (workbookFile != null) {
      try {
        final doc = XmlDocument.parse(
            utf8.decode(workbookFile.content as List<int>));
        sheetNames.addAll(doc
            .findAllElements('sheet')
            .map((s) => s.getAttribute('name') ?? 'Sheet'));
      } catch (_) {}
    }

    final sheets  = <SheetData>[];
    int sheetIdx  = 1;

    for (final name in sheetNames.isEmpty ? ['Sheet1'] : sheetNames) {
      final sheetFile =
          _archive.findFile('xl/worksheets/sheet$sheetIdx.xml');
      if (sheetFile != null) {
        final sheet = _parseSheet(name, sheetFile);
        sheets.add(sheet);
      }
      sheetIdx++;
    }

    // Also try to find sheets by scanning archive
    if (sheets.isEmpty) {
      final sheetFiles = _archive.files
          .where((f) => f.name.startsWith('xl/worksheets/sheet') &&
              f.name.endsWith('.xml'))
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      for (int i = 0; i < sheetFiles.length; i++) {
        sheets.add(_parseSheet('Sheet ${i + 1}', sheetFiles[i]));
      }
    }

    return ParsedDocument(
      title:  fileName,
      format: 'xlsx',
      blocks: [],
      sheets: sheets,
    );
  }

  SheetData _parseSheet(String name, ArchiveFile file) {
    late XmlDocument doc;
    try {
      doc = XmlDocument.parse(
          utf8.decode(file.content as List<int>));
    } catch (_) {
      return SheetData(name: name, rows: [], maxCols: 0);
    }

    // Build a sparse map [row][col] = value
    final data      = <int, Map<int, String>>{};
    int maxRow = 0;
    int maxCol = 0;

    for (final row in doc.findAllElements('row')) {
      final rowNum = int.tryParse(row.getAttribute('r') ?? '0') ?? 0;
      if (rowNum == 0) continue;
      maxRow = rowNum > maxRow ? rowNum : maxRow;
      data[rowNum] = {};

      for (final c in row.findAllElements('c')) {
        final cellRef = c.getAttribute('r') ?? '';
        final colIdx  = _colIndex(cellRef);
        if (colIdx > maxCol) maxCol = colIdx;

        final t   = c.getAttribute('t') ?? ''; // type
        final v   = c.findAllElements('v').firstOrNull?.innerText ?? '';
        final formula = c.findAllElements('f').firstOrNull?.innerText;
        final inline  = c.findAllElements('is')
            .expand((e) => e.findAllElements('t'))
            .map((e) => e.innerText)
            .join();

        String display = '';
        if (inline.isNotEmpty) {
          display = inline;
        } else if (t == 's') {
          // Shared string
          final idx = int.tryParse(v) ?? -1;
          display   = idx >= 0 && idx < _sharedStrings.length
              ? _sharedStrings[idx]
              : v;
        } else if (t == 'b') {
          display = v == '1' ? 'TRUE' : 'FALSE';
        } else if (t == 'e') {
          display = '#$v';
        } else if (formula != null && v.isNotEmpty) {
          display = v;
        } else {
          display = v;
        }

        data[rowNum]![colIdx] = display;
      }
    }

    // Convert sparse map to dense 2D list
    final rows = <List<String>>[];
    for (int r = 1; r <= maxRow; r++) {
      final rowData = List<String>.filled(maxCol, '');
      final rowMap  = data[r] ?? {};
      for (final entry in rowMap.entries) {
        if (entry.key <= maxCol) rowData[entry.key - 1] = entry.value;
      }
      rows.add(rowData);
    }

    return SheetData(name: name, rows: rows, maxCols: maxCol);
  }

  // Convert Excel column ref (A, B, ..., AA, AB...) to 1-based index
  int _colIndex(String cellRef) {
    final letters = cellRef.replaceAll(RegExp(r'[0-9]'), '');
    int idx = 0;
    for (final ch in letters.codeUnits) {
      idx = idx * 26 + (ch - 64);
    }
    return idx;
  }
}
