import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

/// Anthropic Claude API Client for Zeera Synthesis
class ClaudeApiClient {
  static const String _remoteUrl = 'https://api.anthropic.com/v1';
  
  final String apiKey;
  final String model;

  ClaudeApiClient({
    required this.apiKey,
    required this.model,
  });

  String get _cleanKey => apiKey.trim();

  Future<String> generate({
    required String prompt,
    String? systemPrompt,
    int? maxTokens,
  }) async {
    try {
      if (_cleanKey.isEmpty) throw Exception('Anthropic API Key is empty');

      final response = await http.post(
        Uri.parse('$_remoteUrl/messages'),
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': _cleanKey,
          'anthropic-version': '2023-06-01',
          'anthropic-dangerous-direct-browser-access': 'true',
        },
        body: jsonEncode({
          'model': model.isNotEmpty ? model : 'claude-3-5-sonnet-20241022',
          'max_tokens': maxTokens ?? 4096,
          'system': ?systemPrompt,
          'messages': [
            {'role': 'user', 'content': prompt}
          ],
        }),
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode != 200) {
        debugPrint('[Claude] Generate failed: ${response.statusCode} - ${response.body}');
        throw Exception('Anthropic error ${response.statusCode}: ${response.body}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final content = data['content'] as List?;
      if (content != null && content.isNotEmpty) {
        return content[0]['text'] as String? ?? '';
      }
      return '';
    } catch (e) {
      debugPrint('[Claude] Generate error: $e');
      rethrow;
    }
  }

  Stream<String> generateStream({
    required String prompt,
    String? systemPrompt,
    int? maxTokens,
  }) async* {
    final client = http.Client();
    try {
      if (_cleanKey.isEmpty) throw Exception('Anthropic API Key is empty');

      final request = http.Request('POST', Uri.parse('$_remoteUrl/messages'));
      request.headers['Content-Type'] = 'application/json';
      request.headers['x-api-key'] = _cleanKey;
      request.headers['anthropic-version'] = '2023-06-01';
      request.headers['anthropic-dangerous-direct-browser-access'] = 'true';
      request.headers['Accept'] = 'text/event-stream';

      request.body = jsonEncode({
        'model': model.isNotEmpty ? model : 'claude-3-5-sonnet-20241022',
        'max_tokens': maxTokens ?? 4096,
        'system': ?systemPrompt,
        'messages': [
          {'role': 'user', 'content': prompt}
        ],
        'stream': true,
      });

      final response = await client.send(request).timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        final errBody = await response.stream.bytesToString();
        debugPrint('[Claude] Stream failed: ${response.statusCode} - $errBody');
        throw Exception('Anthropic stream error ${response.statusCode}: $errBody');
      }

      await for (final line in response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (line.isEmpty) continue;
        if (line.startsWith('data: ')) {
          final jsonStr = line.substring(6).trim();
          if (jsonStr.isEmpty) continue;
          
          try {
            final data = jsonDecode(jsonStr) as Map<String, dynamic>;
            final type = data['type'];
            
            if (type == 'content_block_delta') {
              final delta = data['delta'];
              if (delta != null && delta['text'] != null) {
                yield delta['text'] as String;
              }
            } else if (type == 'message_stop') {
              break;
            }
          } catch (e) {
            // Ignore parse errors for keep-alive messages
          }
        }
      }
    } catch (e) {
      debugPrint('[Claude] Stream error: $e');
      rethrow;
    } finally {
      client.close();
    }
  }
}
