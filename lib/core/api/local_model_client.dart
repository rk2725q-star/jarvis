import 'dart:convert';
import 'package:http/http.dart' as http;

/// Local model client (llama.cpp server / LM Studio / etc.)
class LocalModelClient {
  final String baseUrl;
  final String? apiKey;

  LocalModelClient({
    this.baseUrl = 'http://127.0.0.1:8080',
    this.apiKey,
  });

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (apiKey != null) 'Authorization': 'Bearer $apiKey',
  };

  Future<String> generate(String prompt) async {
    final res = await http.post(
      Uri.parse('$baseUrl/completion'),
      headers: _headers,
      body: jsonEncode({
        'prompt': prompt,
        'n_predict': 1024,
        'temperature': 0.7,
        'stop': ['\n\n\n'],
      }),
    ).timeout(const Duration(seconds: 120));

    if (res.statusCode != 200) {
      throw Exception('Local model error ${res.statusCode}');
    }
    final data = jsonDecode(res.body) as Map;
    return data['content'] as String? ?? '';
  }

  Stream<String> generateStream(String prompt) async* {
    final client = http.Client();
    try {
      final req = http.Request('POST', Uri.parse('$baseUrl/completion'));
      req.headers.addAll(_headers);
      req.body = jsonEncode({
        'prompt': prompt,
        'n_predict': 1024,
        'temperature': 0.7,
        'stream': true,
      });

      final resp = await client.send(req);
      await for (final line in resp.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (line.startsWith('data: ')) {
          final jsonStr = line.substring(6).trim();
          try {
            final data = jsonDecode(jsonStr) as Map;
            final text = data['content'] as String?;
            if (text != null && text.isNotEmpty) yield text;
            if (data['stop'] == true) break;
          } catch (_) {}
        }
      }
    } finally {
      client.close();
    }
  }

  Future<bool> isAvailable() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 3));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
