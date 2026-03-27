import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

/// Gemini AI provider — supports text, streaming AND vision (image) inputs
class GeminiApiClient {
  static const String _baseUrl = 'https://generativelanguage.googleapis.com/v1beta';
  final String apiKey;
  final String model;

  GeminiApiClient({required this.apiKey, this.model = 'gemini-1.5-flash'});

  Future<List<String>> fetchModels() async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/models'),
        headers: {
          'Content-Type': 'application/json',
          'x-goog-api-key': apiKey,
        },
      );
      if (res.statusCode != 200) throw Exception('${res.statusCode}');
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final models = (data['models'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      return models
          .map((m) => (m['name'] as String).replaceFirst('models/', ''))
          .where((n) => n.contains('gemini') && !n.contains('embedding') && !n.contains('vision'))
          .toList();
    } catch (e) {
      debugPrint('[Gemini] fetchModels error: $e');
      return ['gemini-2.5-flash', 'gemini-2.0-flash', 'gemini-1.5-flash', 'gemini-1.5-pro'];
    }
  }

  // ── Build content parts (optionally with image) ──────────────────────────
  List<Map<String, dynamic>> _buildParts(String prompt, {String? imageBase64}) {
    final parts = <Map<String, dynamic>>[];
    if (imageBase64 != null && imageBase64.isNotEmpty) {
      parts.add({
        'inlineData': {
          'mimeType': 'image/jpeg',
          'data': imageBase64,
        }
      });
    }
    parts.add({'text': prompt});
    return parts;
  }

  Map<String, dynamic> _buildBody({
    required String prompt,
    String? systemPrompt,
    int? maxTokens,
    String? imageBase64,
  }) {
    return {
      'contents': [
        {
          'parts': _buildParts(prompt, imageBase64: imageBase64),
          'role': 'user',
        }
      ],
      if (systemPrompt != null)
        'systemInstruction': {
          'parts': [{'text': systemPrompt}]
        },
      'generationConfig': {
        'temperature': 0.4, // Lower for agentic precision
        'maxOutputTokens': maxTokens ?? 256, // Short for action decisions
      }
    };
  }

  // ── Non-streaming generate (used by agent loop) ───────────────────────────
  Future<String> generate(String prompt, {
    String? systemPrompt,
    int? maxTokens,
    String? imageBase64,
  }) async {
    final body = jsonEncode(_buildBody(
      prompt: prompt,
      systemPrompt: systemPrompt,
      maxTokens: maxTokens,
      imageBase64: imageBase64,
    ));

    final modelPath = model.startsWith('models/') ? model : 'models/$model';
    final res = await http.post(
      Uri.parse('$_baseUrl/$modelPath:generateContent'),
      headers: {
        'Content-Type': 'application/json',
        'x-goog-api-key': apiKey,
      },
      body: body,
    );

    if (res.statusCode != 200) {
      throw Exception('Gemini error ${res.statusCode}: ${res.body}');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final candidates = (data['candidates'] as List?)?.cast<Map>() ?? [];
    if (candidates.isEmpty) throw Exception('Gemini returned no candidates');
    final text = candidates.first['content']?['parts']?[0]?['text'] as String?;
    if (text == null) throw Exception('Gemini returned no text');
    return text;
  }

  // ── Streaming generate (used by chat UI) ─────────────────────────────────
  Stream<String> generateStream(String prompt, {
    String? systemPrompt,
    int? maxTokens,
    String? imageBase64,
  }) async* {
    final body = jsonEncode(_buildBody(
      prompt: prompt,
      systemPrompt: systemPrompt,
      maxTokens: maxTokens ?? 2048,
      imageBase64: imageBase64,
    ));

    final modelPath = model.startsWith('models/') ? model : 'models/$model';
    final req = http.Request(
      'POST',
      Uri.parse('$_baseUrl/$modelPath:streamGenerateContent?alt=sse'),
    );
    req.headers['Content-Type'] = 'application/json';
    req.headers['x-goog-api-key'] = apiKey;
    req.body = body;

    final client = http.Client();
    try {
      final resp = await client.send(req);
      if (resp.statusCode != 200) {
        throw Exception('Gemini stream error ${resp.statusCode}');
      }
      await for (final line in resp.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (line.startsWith('data: ')) {
          final jsonStr = line.substring(6).trim();
          if (jsonStr == '[DONE]') break;
          try {
            final data = jsonDecode(jsonStr) as Map<String, dynamic>;
            final text = data['candidates']?[0]?['content']?['parts']?[0]?['text'] as String?;
            if (text != null && text.isNotEmpty) yield text;
          } catch (e) {
            // Skip malformed SSE chunks
          }
        }
      }
    } finally {
      client.close();
    }
  }
}
