import 'dart:convert';
import 'package:http/http.dart' as http;

/// Ollama local/cloud provider using OpenAI-compatible API
class OllamaApiClient {
  final String baseUrl;
  final String model;
  final String? apiKey;

  OllamaApiClient({
    this.baseUrl = 'http://127.0.0.1:11434',
    this.model = 'llama3',
    this.apiKey,
  });

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (apiKey != null) 'Authorization': 'Bearer $apiKey',
  };

  String get _adjustedBaseUrl {
    var u = baseUrl.trim();
    if (u.endsWith('/')) u = u.substring(0, u.length - 1);
    if (u.endsWith('/api')) u = u.substring(0, u.length - 4);
    return u;
  }

  Future<List<String>> fetchModels() async {
    try {
      final res = await http.get(
        Uri.parse('$_adjustedBaseUrl/api/tags'),
        headers: _headers,
      ).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final models = (data['models'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        return models.map((m) => m['name'] as String).toList();
      }
    } catch (e) {
      // Endpoint doesn't support tags, or timeout
    }
    
    // Fallback if cloud endpoint model listing fails
    return [
      'deepseek-v3.1:671b-cloud',
      'deepseek-v3',
      'llama3',
      'llama3.1',
      model // Include currently set model
    ];
  }

  Future<String> generate(String prompt, {String? systemPrompt}) async {
    final messages = [
      if (systemPrompt != null) {'role': 'system', 'content': systemPrompt},
      {'role': 'user', 'content': prompt},
    ];

    final res = await http.post(
      Uri.parse('$_adjustedBaseUrl/api/chat'),
      headers: _headers,
      body: jsonEncode({
        'model': model,
        'messages': messages,
        'stream': false,
      }),
    ).timeout(const Duration(seconds: 120));

    if (res.statusCode != 200) {
      throw Exception('Ollama error ${res.statusCode}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data['message']?['content'] as String? ?? '';
  }

  Stream<String> generateStream(String prompt, {String? systemPrompt}) async* {
    final messages = [
      if (systemPrompt != null) {'role': 'system', 'content': systemPrompt},
      {'role': 'user', 'content': prompt},
    ];

    final client = http.Client();
    try {
      final req = http.Request('POST', Uri.parse('$_adjustedBaseUrl/api/chat'));
      req.headers.addAll(_headers);
      req.body = jsonEncode({
        'model': model, 
        'messages': messages, 
        'stream': true
      });

      final resp = await client.send(req);
      await for (final chunk in resp.stream.transform(utf8.decoder)) {
        try {
          final data = jsonDecode(chunk) as Map<String, dynamic>;
          final text = data['message']?['content'] as String?;
          if (text != null && text.isNotEmpty) yield text;
          if (data['done'] == true) break;
        } catch (_) {}
      }
    } finally {
      client.close();
    }
  }
}
