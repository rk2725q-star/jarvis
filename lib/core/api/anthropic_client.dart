import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class AnthropicApiClient {
  final String apiKey;
  final String model;
  final String baseUrl;

  AnthropicApiClient({
    required String apiKey,
    this.model = 'claude-3-5-sonnet-20241022',
    this.baseUrl = 'https://api.anthropic.com/v1',
  }) : apiKey = apiKey.trim();

  Future<List<String>> fetchModels() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/models'),
        headers: {
          'x-api-key': apiKey,
          'anthropic-version': '2023-06-01',
          'content-type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final List<dynamic> data = json['data'] ?? [];
        return data.map((m) => m['id'].toString()).toList();
      }
    } catch (e) {
      debugPrint('[Anthropic] Failed to fetch models: $e');
    }
    
    // Fallback if API fails or isn't supported yet
    return [
      'claude-sonnet-4-5',
      'claude-opus-4-5',
      'claude-3-7-sonnet-20250219',
      'claude-3-5-sonnet-20241022',
      'claude-3-5-haiku-20241022',
      'claude-3-opus-20240229',
      'claude-3-sonnet-20240229',
      'claude-2.1',
    ];
  }

  Stream<String> generateStream(String prompt, {String? systemPrompt, int maxTokens = 16000}) async* {
    final client = http.Client();
    try {
      debugPrint('[Anthropic] key (prefix)="${apiKey.substring(0, 10)}..." model=$model (Stream)');
      final request = http.Request('POST', Uri.parse('$baseUrl/messages'));
      request.headers.addAll({
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        'content-type': 'application/json',
      });
      request.body = jsonEncode({
        'model': model,
        'max_tokens': maxTokens,
        'system': systemPrompt ?? 'You are a helpful AI assistant.',
        'messages': [
          {'role': 'user', 'content': prompt}
        ],
        'stream': true,
      });

      final streamedResponse = await client.send(request);

      if (streamedResponse.statusCode != 200) {
        final body = await streamedResponse.stream.bytesToString();
        throw Exception('Anthropic API Error: ${streamedResponse.statusCode} $body');
      }

      final stream = streamedResponse.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      await for (final line in stream) {
        if (line.startsWith('data: ')) {
          final data = line.substring(6).trim();
          if (data == '[DONE]') break;
          try {
            final json = jsonDecode(data);
            if (json['type'] == 'content_block_delta') {
              final text = json['delta']['text'];
              if (text != null && text.isNotEmpty) yield text;
            }
          } catch (_) {}
        }
      }
    } finally {
      client.close();
    }
  }

  Future<String> generate(String prompt, {String? systemPrompt, int maxTokens = 16000}) async {
    debugPrint('[Anthropic] key (prefix)="${apiKey.substring(0, 10)}..." model=$model (Static)');
    final response = await http.post(
      Uri.parse('$baseUrl/messages'),
      headers: {
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        'content-type': 'application/json',
      },
      body: jsonEncode({
        'model': model,
        'max_tokens': maxTokens,
        'system': systemPrompt ?? 'You are a helpful AI assistant.',
        'messages': [
          {'role': 'user', 'content': prompt}
        ],
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Anthropic API Error: ${response.statusCode} ${response.body}');
    }

    final json = jsonDecode(response.body);
    if (json['content'] != null && (json['content'] as List).isNotEmpty) {
      return json['content'][0]['text'] ?? '';
    }
    return '';
  }
}
