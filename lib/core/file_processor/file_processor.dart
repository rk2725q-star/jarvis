import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:docx_to_text/docx_to_text.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class FileProcessor {
  final _textRecognizer = TextRecognizer();

  Future<String> extractText(String path) async {
    final file = File(path);
    if (!await file.exists()) throw Exception("File does not exist");

    if (path.toLowerCase().endsWith(".pdf")) {
      return await _readPdf(file);
    } else if (path.toLowerCase().endsWith(".docx")) {
      return await _readDocx(file);
    } else if (path.toLowerCase().endsWith(".pptx") || path.toLowerCase().endsWith(".odt")) {
      return await _readFromZip(file);
    } else if (path.toLowerCase().endsWith(".txt") || path.toLowerCase().endsWith(".md")) {
      return await file.readAsString();
    } else if (_isImage(path)) {
      return await _readImage(path);
    } else {
      throw Exception("Unsupported file format");
    }
  }

  bool _isImage(String path) {
    final p = path.toLowerCase();
    return p.endsWith(".jpg") || p.endsWith(".jpeg") || p.endsWith(".png") || p.endsWith(".webp");
  }

  Future<String> _readPdf(File file) async {
    final Uint8List bytes = await file.readAsBytes();
    final PdfDocument document = PdfDocument(inputBytes: bytes);
    final String text = PdfTextExtractor(document).extractText();
    document.dispose();
    return text;
  }

  Future<String> _readDocx(File file) async {
    final bytes = await file.readAsBytes();
    // Use docx_to_text if it works, else fallback to zip
    try {
      return docxToText(bytes);
    } catch (e) {
      debugPrint("docx_to_text failed: $e, falling back to zip extraction");
      return await _readFromZip(file);
    }
  }

  Future<String> _readFromZip(File file) async {
    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final buffer = StringBuffer();

    for (final file in archive) {
      if (file.name.contains("document.xml") || // DOCX
          file.name.contains("slide") || // PPTX
          file.name.contains("content.xml")) { // ODT/generic
        try {
          final content = utf8.decode(file.content as List<int>, allowMalformed: true);
          // Simple XML tag removal
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
    final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);
    return recognizedText.text;
  }

  List<String> chunkText(String text, {int size = 2000}) {
    List<String> chunks = [];
    for (int i = 0; i < text.length; i += size) {
      chunks.add(text.substring(i, i + size > text.length ? text.length : i + size));
    }
    return chunks;
  }

  void dispose() {
    _textRecognizer.close();
  }
}
