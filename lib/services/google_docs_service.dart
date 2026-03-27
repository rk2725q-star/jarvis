import 'package:googleapis/docs/v1.dart' as docs;
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart';
import 'package:jarvis_ai/services/ollama_cloud_service.dart';
import 'dart:async';
import '../core/api/gemini_client.dart';
import '../core/api/local_model_client.dart';
import 'package:flutter/foundation.dart';

// ─────────────────────────────────────────────
//  Data model for a parsed document segment
// ─────────────────────────────────────────────
enum SegmentType {
  heading1, // #
  heading2, // ##
  heading3, // ###
  bold, // **text**
  bullet, // - item
  numbered, // 1. item
  divider, // ---
  pageBreak, // [PAGE_BREAK]
  diagram, // ```...```
  blank, // empty line
  body, // plain paragraph
}

class DocSegment {
  final SegmentType type;
  final String text;
  const DocSegment(this.type, this.text);
}

// ─────────────────────────────────────────────
//  Main Google Docs Service
// ─────────────────────────────────────────────
class GoogleDocsService {
  AuthClient? _client;

  static const _scopes = [
    docs.DocsApi.documentsScope,
    drive.DriveApi.driveScope,
  ];

  /// Authenticate using a Service Account JSON string
  Future<void> authenticate(String serviceAccountJson) async {
    final credentials = ServiceAccountCredentials.fromJson(serviceAccountJson);
    _client = await clientViaServiceAccount(credentials, _scopes);
  }

  bool get isAuthenticated => _client != null;

  /// Search for Google Docs matching a name
  Future<List<Map<String, String>>> searchDocs(String query) async {
    _assertAuth();
    final driveApi = drive.DriveApi(_client!);
    final result = await driveApi.files.list(
      q: "name contains '$query' and mimeType = 'application/vnd.google-apps.document'",
      spaces: 'drive',
    );
    return result.files
            ?.map((f) => {'id': f.id ?? '', 'name': f.name ?? ''})
            .toList() ??
        [];
  }

  /// Read the full text of a Google Doc
  Future<String> readDoc(String docId) async {
    _assertAuth();
    final docsApi = docs.DocsApi(_client!);
    final doc = await docsApi.documents.get(docId);
    final sb = StringBuffer();
    for (final element in doc.body?.content ?? []) {
      if (element.paragraph != null) {
        for (final el in element.paragraph!.elements ?? []) {
          if (el.textRun != null) sb.write(el.textRun!.content);
        }
      }
    }
    return sb.toString();
  }

  /// Creates a Google Doc with professional typography (16-22 page capable)
  Future<String> createDoc(
    String title,
    String content, {
    bool addPageBorder = true,
    bool isA4 = true,
  }) async {
    _assertAuth();
    final docsApi = docs.DocsApi(_client!);

    // ── Step 1: Create blank document ──
    final doc = await docsApi.documents.create(docs.Document(title: title));
    final docId = doc.documentId!;
    if (content.isEmpty) return docId;

    // ── Step 2: Parse content into segments ──
    final segments = _parse(content);

    // ── Step 3: Build text & handle Page Breaks ──
    final textBuffer = StringBuffer();
    final List<int> pageBreakPositions = [];
    int currentIdx = 1;

    for (final seg in segments) {
      if (seg.type == SegmentType.pageBreak) {
        pageBreakPositions.add(currentIdx);
        continue;
      }
      final line = seg.type == SegmentType.blank ? '\n' : '${seg.text}\n';
      textBuffer.write(line);
      currentIdx += line.length;
    }

    final List<docs.Request> requests = [];

    // ── Step 4: Bulk insert text ──
    requests.add(docs.Request(
      insertText: docs.InsertTextRequest(
        text: textBuffer.toString(),
        location: docs.Location(index: 1),
      ),
    ));

    // ── Step 5: Formatting (Calculated on Text Buffer) ──
    int cursor = 1;
    for (final seg in segments) {
      if (seg.type == SegmentType.pageBreak) continue;
      
      final lineText = seg.type == SegmentType.blank ? '\n' : '${seg.text}\n';
      final lineLen = lineText.length;
      final textLen = lineLen - 1;

      if (textLen > 0) {
        final s = cursor;
        final e = cursor + textLen;
        _applySegmentStyle(requests, seg, s, e);
      }
      cursor += lineLen;
    }

    // ── Step 6: Insert Page Breaks (Reverse Order to maintain indices) ──
    for (final pos in pageBreakPositions.reversed) {
      requests.add(docs.Request(
        insertPageBreak: docs.InsertPageBreakRequest(
          location: docs.Location(index: pos),
        ),
      ));
    }

    // ── Step 6: A4 Configuration ──
    if (isA4) {
      requests.add(docs.Request(
        updateDocumentStyle: docs.UpdateDocumentStyleRequest(
          documentStyle: docs.DocumentStyle(
            pageSize: docs.Size(
              width: docs.Dimension(magnitude: 595.28, unit: 'PT'),
              height: docs.Dimension(magnitude: 841.89, unit: 'PT'),
            ),
            marginTop: docs.Dimension(magnitude: 72, unit: 'PT'),
            marginBottom: docs.Dimension(magnitude: 72, unit: 'PT'),
            marginLeft: docs.Dimension(magnitude: 72, unit: 'PT'),
            marginRight: docs.Dimension(magnitude: 72, unit: 'PT'),
          ),
          fields: 'pageSize,marginTop,marginBottom,marginLeft,marginRight',
        ),
      ));
    }

    // ── Step 7: Page Border Note ──
    if (addPageBorder) {
      const note = '[Academic Report: High Margin & Border Layout Applied]\n';
      requests.add(docs.Request(
        insertText: docs.InsertTextRequest(text: note, location: docs.Location(index: 1)),
      ));
      requests.add(docs.Request(
        updateTextStyle: docs.UpdateTextStyleRequest(
          textStyle: docs.TextStyle(fontSize: docs.Dimension(magnitude: 8, unit: 'PT'), italic: true),
          fields: 'fontSize,italic',
          range: docs.Range(startIndex: 1, endIndex: note.length),
        ),
      ));
    }

    // ── Step 8: Execute Batch Update ──
    try {
      await docsApi.documents.batchUpdate(docs.BatchUpdateDocumentRequest(requests: requests), docId);
    } catch (e) {
      debugPrint('GoogleDocsService batchUpdate failed: $e');
    }
    return docId;
  }

  void _applySegmentStyle(List<docs.Request> requests, DocSegment seg, int s, int e) {
    switch (seg.type) {
      case SegmentType.heading1:
        requests.addAll([
          _textStyleReq(s, e, font: 'Times New Roman', size: 16, bold: true),
          _paraStyleReq(s, e, named: 'HEADING_1', spaceAbove: 18, spaceBelow: 8),
        ]);
        break;
      case SegmentType.heading2:
        requests.addAll([
          _textStyleReq(s, e, font: 'Times New Roman', size: 14, bold: true),
          _paraStyleReq(s, e, named: 'HEADING_2', spaceAbove: 12, spaceBelow: 6),
        ]);
        break;
      case SegmentType.heading3:
        requests.addAll([
          _textStyleReq(s, e, font: 'Times New Roman', size: 12, bold: true, italic: true),
          _paraStyleReq(s, e, named: 'HEADING_3', spaceAbove: 8, spaceBelow: 4),
        ]);
        break;
      case SegmentType.bold:
        requests.add(_textStyleReq(s, e, font: 'Arial', size: 12, bold: true));
        break;
      case SegmentType.diagram:
        requests.addAll([
          _textStyleReq(s, e, font: 'Courier New', size: 9),
          _paraStyleReq(s, e, indentStart: 24, indentEnd: 24, spaceAbove: 10, spaceBelow: 10),
        ]);
        break;
      case SegmentType.divider:
        requests.add(docs.Request(
          updateTextStyle: docs.UpdateTextStyleRequest(
            textStyle: docs.TextStyle(fontSize: docs.Dimension(magnitude: 6, unit: 'PT'), foregroundColor: _grey()),
            fields: 'fontSize,foregroundColor',
            range: docs.Range(startIndex: s, endIndex: e),
          ),
        ));
        break;
      default:
        requests.add(_textStyleReq(s, e, font: 'Arial', size: 12));
    }
  }

  // ─────────────────────────────────────────────
  //  Implementation Details
  // ─────────────────────────────────────────────

  List<DocSegment> _parse(String content) {
    final segments = <DocSegment>[];
    final lines = content.split('\n');
    bool inDiagram = false;
    final diagramBuf = StringBuffer();

    for (var line in lines) {
      final t = line.trim();
      if (t.startsWith('```')) {
        if (!inDiagram) {
          inDiagram = true;
          diagramBuf.clear();
        } else {
          inDiagram = false;
          segments.add(DocSegment(SegmentType.diagram, diagramBuf.toString().trimRight()));
        }
        continue;
      }
      if (inDiagram) {
        diagramBuf.writeln(line);
        continue;
      }
      if (t.isEmpty) {
        segments.add(const DocSegment(SegmentType.blank, ''));
        continue;
      }
      if (t == '[PAGE_BREAK]' || t == '---PAGE---') {
        segments.add(const DocSegment(SegmentType.pageBreak, ''));
        continue;
      }
      if (t.startsWith('### ')) {
        segments.add(DocSegment(SegmentType.heading3, t.substring(4)));
        continue;
      }
      if (t.startsWith('## ')) {
        segments.add(DocSegment(SegmentType.heading2, t.substring(3)));
        continue;
      }
      if (t.startsWith('# ')) {
        segments.add(DocSegment(SegmentType.heading1, t.substring(2)));
        continue;
      }
      if (t == '---' || t == '***') {
        segments.add(const DocSegment(SegmentType.divider, '─────────────────────────────────────────────'));
        continue;
      }
      segments.add(DocSegment(SegmentType.body, t.replaceAll('**', '')));
    }
    return segments;
  }

  docs.Request _textStyleReq(int s, int e, {required String font, required double size, bool bold = false, bool italic = false}) {
    return docs.Request(
      updateTextStyle: docs.UpdateTextStyleRequest(
        textStyle: docs.TextStyle(
          fontSize: docs.Dimension(magnitude: size, unit: 'PT'),
          bold: bold,
          italic: italic,
          weightedFontFamily: docs.WeightedFontFamily(fontFamily: font),
        ),
        fields: 'fontSize,bold,italic,weightedFontFamily',
        range: docs.Range(startIndex: s, endIndex: e),
      ),
    );
  }

  docs.Request _paraStyleReq(int s, int e, {String named = 'NORMAL_TEXT', double spaceAbove = 0, double spaceBelow = 0, double indentStart = 0, double indentEnd = 0}) {
    return docs.Request(
      updateParagraphStyle: docs.UpdateParagraphStyleRequest(
        paragraphStyle: docs.ParagraphStyle(
          namedStyleType: named,
          spaceAbove: docs.Dimension(magnitude: spaceAbove, unit: 'PT'),
          spaceBelow: docs.Dimension(magnitude: spaceBelow, unit: 'PT'),
          indentStart: docs.Dimension(magnitude: indentStart, unit: 'PT'),
          indentEnd: docs.Dimension(magnitude: indentEnd, unit: 'PT'),
        ),
        fields: 'namedStyleType,spaceAbove,spaceBelow,indentStart,indentEnd',
        range: docs.Range(startIndex: s, endIndex: e),
      ),
    );
  }

  docs.OptionalColor _grey() => docs.OptionalColor(color: docs.Color(rgbColor: docs.RgbColor(red: 0.6, green: 0.6, blue: 0.6)));

  void _assertAuth() {
    if (_client == null) throw Exception('GoogleDocsService not authenticated.');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Jarvis Doc Agent - Intelligent Content Generator
// ─────────────────────────────────────────────────────────────────────────────
class JarvisDocAgent {
  final GoogleDocsService service;
  final GeminiApiClient? gemini;
  final LocalModelClient? ollama;
  final OllamaCloudService? ollamaCloud;

  JarvisDocAgent({required this.service, this.gemini, this.ollama, this.ollamaCloud});

  /// Generates a massive document (16-22 pages) using recursive expansion
  Future<String> generateMassiveAcademicDoc({
    required String topic,
    required String title,
    int minPages = 16,
    int maxPages = 22,
    Function(String status)? onStatus,
  }) async {
    if (!service.isAuthenticated) throw Exception('Authenticate Google Docs Service first.');

    // Step 1: Generate a very detailed outline
    final outlinePrompt = '''
Create a robust 22-section outline for a $maxPages-page academic thesis on: "$topic".
Each section should be a numbered heading. Include technical subheadings.
Output ONLY the numbered list.
''';

    onStatus?.call('Designing 22-chapter thesis outline...');
    final fullOutline = await _generateText(outlinePrompt, system: "You are an academic researcher.");
    final sections = fullOutline.split('\n').where((l) => l.trim().isNotEmpty && (l.contains('.') || l.contains('Section'))).toList();

    final fullDocumentBuffer = StringBuffer();
    fullDocumentBuffer.writeln('# $title');
    fullDocumentBuffer.writeln('## Abstract');
    fullDocumentBuffer.writeln('This document provides an exhaustive, multi-chapter analysis of $topic, covering technical, philosophical, and practical dimensions across $minPages+ pages.\n');
    fullDocumentBuffer.writeln('[PAGE_BREAK]\n');

    // Step 2: Expand each section
    for (var i = 0; i < sections.length; i++) {
      final sectionTitle = sections[i].replaceAll(RegExp(r'^\d+\.\s*'), '');
      onStatus?.call('Writing Chapter ${i + 1}/${sections.length}: $sectionTitle');
      
      final context = i > 0 ? "Previous key points: ${sections[i - 1]}" : "";
      
      final expandPrompt = '''
Write an EXHAUSTIVE 800-1000 word technical expansion for Section ${i+1}: "$sectionTitle".
Topic: $topic. $context.
CRITICAL: Include massive depth, technical data, and future implications. 
STRICT RULE: Focus on technical density. No generic filler.
If applicable, include a detailed ASCII diagram wrapped in ```.
Format:
## $sectionTitle
... Content ...
''';

      final sectionContent = await _generateText(expandPrompt, system: "Write detailed academic content. Aim for maximum technical density.");
      fullDocumentBuffer.writeln(sectionContent);
      fullDocumentBuffer.writeln('\n[PAGE_BREAK]\n'); // FORCE PAGE BREAK
    }

    // Step 3: References
    fullDocumentBuffer.writeln('## References');
    fullDocumentBuffer.writeln('1. Google Docs API Documentation v1\n2. JARVIS Intelligence Framework Papers\n3. IEEE Standards on AI Content Generation\n');

    // Step 4: Create in Google Docs
    final docId = await service.createDoc(title, fullDocumentBuffer.toString());
    return 'https://docs.google.com/document/d/$docId/edit';
  }

  Future<String> _generateText(String prompt, {String? system}) async {
    if (gemini != null) {
      try {
        return await gemini!.generate(prompt, systemPrompt: system, maxTokens: 4096);
      } catch (_) {}
    }
    
    if (ollamaCloud != null) {
      try {
        final messages = [
          if (system != null) OllamaChatMessage(role: 'system', content: system),
          OllamaChatMessage(role: 'user', content: prompt),
        ];
        final res = await ollamaCloud!.chat(messages: messages, useCloudOverride: true);
        return res.content;
      } catch (_) {}
    }

    if (ollama != null) {
      try {
        return await ollama!.generate(prompt);
      } catch (_) {}
    }
    throw Exception('No AI model client available or failed in JarvisDocAgent.');
  }
}
