import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:docx_to_text/docx_to_text.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../../features/files/parsers/docx_parser.dart';
import '../../features/files/parsers/pptx_parser.dart';
import '../../features/files/parsers/xlsx_parser.dart';

class FileProcessor {
  final _textRecognizer = TextRecognizer();

  Future<String> extractText(String path) async {
    final file = File(path);
    if (!await file.exists()) throw Exception("File does not exist");

    final ext = path.toLowerCase();
    if (ext.endsWith(".pdf")) {
      return await _readPdf(file);
    } else if (ext.endsWith(".docx")) {
      return await _readDocx(file);
    } else if (ext.endsWith(".pptx") || ext.endsWith(".ppt")) {
      return await _readPptx(file);
    } else if (ext.endsWith(".xlsx") || ext.endsWith(".xls")) {
      return await _readXlsx(file);
    } else if (ext.endsWith(".odt")) {
      return await _readFromZip(file);
    } else if (ext.endsWith(".txt") ||
        ext.endsWith(".md") ||
        ext.endsWith(".csv")) {
      return await file.readAsString();
    } else if (_isImage(path)) {
      return await _readImage(path);
    } else {
      throw Exception("Unsupported file format");
    }
  }

  bool _isImage(String path) {
    final p = path.toLowerCase();
    return p.endsWith(".jpg") ||
        p.endsWith(".jpeg") ||
        p.endsWith(".png") ||
        p.endsWith(".webp");
  }

  Future<String> _readPdf(File file) async {
    final Uint8List bytes = await file.readAsBytes();
    final PdfDocument document = PdfDocument(inputBytes: bytes);
    final String text = PdfTextExtractor(document).extractText();
    document.dispose();
    return text;
  }

  Future<String> _readDocx(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final pDoc = DocxParser(
        archive,
      ).parse(file.path.split(Platform.pathSeparator).last);
      final sb = StringBuffer();
      for (final block in pDoc.blocks) {
        if (block.plainText != null) sb.writeln(block.plainText);
      }
      return sb.toString();
    } catch (e) {
      debugPrint("Advanced Docx extraction failed: $e. Falling back.");
      final bytes = await file.readAsBytes();
      return docxToText(bytes);
    }
  }

  Future<String> _readPptx(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final pDoc = PptxParser(
        archive,
      ).parse(file.path.split(Platform.pathSeparator).last);
      final sb = StringBuffer();
      for (final slide in pDoc.slides ?? []) {
        sb.writeln("Slide ${slide.index}: ${slide.title ?? ''}");
        for (final block in slide.blocks) {
          if (block.plainText != null) sb.writeln(block.plainText);
        }
      }
      return sb.toString();
    } catch (e) {
      return await _readFromZip(file);
    }
  }

  Future<String> _readXlsx(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final pDoc = XlsxParser(
        archive,
      ).parse(file.path.split(Platform.pathSeparator).last);
      final sb = StringBuffer();
      for (final sheet in pDoc.sheets ?? []) {
        sb.writeln("Sheet: ${sheet.name}");
        for (final row in sheet.rows) {
          sb.writeln(row.join(" | "));
        }
      }
      return sb.toString();
    } catch (e) {
      return await _readFromZip(file);
    }
  }

  Future<String> _readFromZip(File file) async {
    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final buffer = StringBuffer();

    for (final file in archive) {
      if (file.name.contains("document.xml") ||
          file.name.contains("slide") ||
          file.name.contains("sharedStrings.xml") ||
          file.name.contains("sheet") ||
          file.name.contains("content.xml")) {
        try {
          final content = utf8.decode(
            file.content as List<int>,
            allowMalformed: true,
          );
          buffer.write(content.replaceAll(RegExp(r'<[^>]*>'), ' '));
        } catch (e) {
          debugPrint("Failed to decode zip entry ${file.name}: $e");
        }
      }
    }
    return buffer.toString().trim();
  }

  Future<String> _readImage(String path) async {
    final inputImage = InputImage.fromFilePath(path);
    final RecognizedText recognizedText = await _textRecognizer.processImage(
      inputImage,
    );
    return recognizedText.text;
  }

  List<String> chunkText(String text, {int size = 2000}) {
    List<String> chunks = [];
    for (int i = 0; i < text.length; i += size) {
      chunks.add(
        text.substring(i, i + size > text.length ? text.length : i + size),
      );
    }
    return chunks;
  }

  void dispose() {
    _textRecognizer.close();
  }
}
