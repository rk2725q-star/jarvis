import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart'; // Added for kIsWeb

/// OpenRouter API (OpenAI-compatible)
class OpenRouterClient {
  static const String _remoteUrl = 'https://openrouter.ai/api/v1';
  static const String _proxyUrl  = '/api/openrouter';
  
  String get _baseUrl {
    if (kIsWeb) {
      final baseUri = Uri.base;
      // In web, handle proxy gracefully or directly return OpenRouter if no proxy setup
      // Usually, openrouter allows CORS from anywhere via HTTP-Referer, but in case they need proxy:
      try {
        if (baseUri.host.isEmpty) return _remoteUrl;
        return baseUri.resolve(_proxyUrl).toString().replaceAll(RegExp(r'/$'), '');
      } catch (_) {
        return _remoteUrl;
      }
    }
    return _remoteUrl;
  }
  
  final String apiKey;
  final String model;

  OpenRouterClient({
    required this.apiKey,
    required this.model,
  });

  String get _cleanKey => apiKey.trim();

  Future<List<String>> fetchModels() async {
    try {
      if (_cleanKey.isEmpty) throw Exception('API Key is empty');
      
      final res = await http.get(
        Uri.parse('$_baseUrl/models'),
        headers: {
          'Authorization': 'Bearer $_cleanKey',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': 'JARVIS-AI-Flutter',
          'HTTP-Referer': 'https://jarvis.ai', // Optional: Replace with actual referrer
          'X-Title': 'JARVIS', // Optional
        },
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) {
        debugPrint('[OpenRouter] Models fetch failed: ${res.statusCode} - ${res.body}');
        throw Exception('OpenRouter model fetch failed (${res.statusCode}): ${res.body}');
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final models = (data['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      return models.map((m) => m['id'] as String).toList();
    } catch (e) {
      debugPrint('[OpenRouter] Models fetch error: $e');
      rethrow;
    }
  }

  Future<String> generate(String prompt, {String? systemPrompt, int? maxTokens, String? imageBase64}) async {
    final List<Map<String, dynamic>> messages = [];
    
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      messages.add({'role': 'system', 'content': systemPrompt});
    }

    if (imageBase64 != null) {
      messages.add({
        'role': 'user',
        'content': [
          {'type': 'text', 'text': prompt},
          {
            'type': 'image_url',
            'image_url': {'url': 'data:image/jpeg;base64,$imageBase64'}
          }
        ]
      });
    } else {
      messages.add({'role': 'user', 'content': prompt});
    }

    try {
      if (_cleanKey.isEmpty) throw Exception('API Key is empty');

        final body = <String, dynamic>{
          'model': model,
          'messages': messages,
        };
        
        // Removed max_tokens completely so OpenRouter handles native limit bounds.
        // body['max_tokens'] = ...

        final res = await http.post(
          Uri.parse('$_baseUrl/chat/completions'),
          headers: {
            'Authorization': 'Bearer $_cleanKey',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'User-Agent': 'JARVIS-AI-Flutter',
            'HTTP-Referer': 'https://jarvis.ai', // Optional: Replace with actual referrer
            'X-Title': 'JARVIS', // Optional
          },
          body: jsonEncode(body),
      ).timeout(const Duration(seconds: 45));

      if (res.statusCode != 200) {
        debugPrint('[OpenRouter] Generate failed: ${res.statusCode} - ${res.body}');
        throw Exception('OpenRouter error ${res.statusCode}: ${res.body}');
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return data['choices']?[0]?['message']?['content'] as String? ?? '';
    } catch (e) {
      debugPrint('[OpenRouter] Generate error: $e');
      rethrow;
    }
  }

  Stream<String> generateStream(String prompt, {String? systemPrompt, int? maxTokens}) async* {
    final List<Map<String, dynamic>> messages = [];
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      messages.add({'role': 'system', 'content': systemPrompt});
    }
    messages.add({'role': 'user', 'content': prompt});

    final client = http.Client();
    try {
      if (_cleanKey.isEmpty) throw Exception('API Key is empty');

      final req = http.Request('POST', Uri.parse('$_baseUrl/chat/completions'));
      req.headers['Authorization'] = 'Bearer $_cleanKey';
      req.headers['Content-Type'] = 'application/json';
      req.headers['Accept'] = 'text/event-stream';
      req.headers['User-Agent'] = 'JARVIS-AI-Flutter';
      req.headers['HTTP-Referer'] = 'https://jarvis.ai'; // Optional: Replace with actual referrer
      req.headers['X-Title'] = 'JARVIS'; // Optional
      
      final body = <String, dynamic>{
        'model': model,
        'messages': messages,
        'stream': true,
      };
      
      req.body = jsonEncode(body);

      final resp = await client.send(req).timeout(const Duration(seconds: 300)); // Raised from 20s to allow long responses
      
      if (resp.statusCode != 200) {
        final errBody = await resp.stream.bytesToString();
        debugPrint('[OpenRouter] Stream failed: ${resp.statusCode} - $errBody');
        throw Exception('OpenRouter stream error ${resp.statusCode}: $errBody');
      }

      await for (final line in resp.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        
        final trimmedLine = line.trim();
        if (trimmedLine.isEmpty) continue;
        
        if (trimmedLine.startsWith('data: ')) {
          final jsonStr = trimmedLine.substring(6).trim();
          if (jsonStr == '[DONE]') break;
          
          try {
            final data = jsonDecode(jsonStr) as Map<String, dynamic>;
            final choice = data['choices']?[0];
            final text = choice?['delta']?['content'] as String? ?? 
                         choice?['text'] as String? ?? 
                         choice?['delta']?['text'] as String?;
            
            if (text != null && text.isNotEmpty) yield text;
          } catch (e) {
            debugPrint('[OpenRouter] JSON parse error: $e for line: $trimmedLine');
          }
        }
      }
    } catch (e) {
      debugPrint('[OpenRouter] Stream error: $e');
      rethrow;
    } finally {
      client.close();
    }
  }
}
