import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart'; // Added for kIsWeb

/// NVIDIA NIM API (OpenAI-compatible)
class NvidiaApiClient {
  static const String _remoteUrl = 'https://integrate.api.nvidia.com/v1';
  static const String _proxyUrl  = '/api/nvidia';
  
  String get _baseUrl => kIsWeb ? _proxyUrl : _remoteUrl;
  
  final String apiKey;
  final String model;

  NvidiaApiClient({
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
        },
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) {
        debugPrint('[Nvidia] Models fetch failed: ${res.statusCode} - ${res.body}');
        throw Exception('NVIDIA model fetch failed (${res.statusCode}): ${res.body}');
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final models = (data['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      return models.map((m) => m['id'] as String).toList();
    } catch (e) {
      debugPrint('[Nvidia] Models fetch error: $e');
      rethrow;
    }
  }

  Future<String> generate(String prompt, {String? systemPrompt, int? maxTokens, String? imageBase64}) async {
    final List<Map<String, dynamic>> messages;
    
    if (imageBase64 != null) {
      messages = [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': systemPrompt != null ? '$systemPrompt\n\n$prompt' : prompt},
            {
              'type': 'image_url',
              'image_url': {'url': 'data:image/jpeg;base64,$imageBase64'}
            }
          ]
        }
      ];
    } else {
      messages = [
        {'role': 'user', 'content': systemPrompt != null ? '$systemPrompt\n\n$prompt' : prompt},
      ];
    }

    try {
      if (_cleanKey.isEmpty) throw Exception('API Key is empty');

      final res = await http.post(
        Uri.parse('$_baseUrl/chat/completions'),
        headers: {
          'Authorization': 'Bearer $_cleanKey',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': 'JARVIS-AI-Flutter',
        },
        body: jsonEncode({
          'model': model,
          'messages': messages,
          'temperature': 0.5,
          'top_p': 1.0,
          'max_tokens': maxTokens ?? 1024,
        }),
      ).timeout(const Duration(seconds: 45));

      if (res.statusCode != 200) {
        debugPrint('[Nvidia] Generate failed: ${res.statusCode} - ${res.body}');
        throw Exception('NVIDIA error ${res.statusCode}: ${res.body}');
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return data['choices']?[0]?['message']?['content'] as String? ?? '';
    } catch (e) {
      debugPrint('[Nvidia] Generate error: $e');
      rethrow;
    }
  }

  Stream<String> generateStream(String prompt, {String? systemPrompt, int? maxTokens}) async* {
    final messages = [
      {'role': 'user', 'content': systemPrompt != null ? '$systemPrompt\n\n$prompt' : prompt},
    ];

    final client = http.Client();
    try {
      if (_cleanKey.isEmpty) throw Exception('API Key is empty');

      final req = http.Request('POST', Uri.parse('$_baseUrl/chat/completions'));
      req.headers['Authorization'] = 'Bearer $_cleanKey';
      req.headers['Content-Type'] = 'application/json';
      req.headers['Accept'] = 'text/event-stream';
      req.headers['User-Agent'] = 'JARVIS-AI-Flutter';
      
      req.body = jsonEncode({
        'model': model,
        'messages': messages,
        'temperature': 0.5,
        'top_p': 1.0,
        'max_tokens': maxTokens ?? 1024,
        'stream': true,
      });

      final resp = await client.send(req).timeout(const Duration(seconds: 20));
      
      if (resp.statusCode != 200) {
        final errBody = await resp.stream.bytesToString();
        debugPrint('[Nvidia] Stream failed: ${resp.statusCode} - $errBody');
        throw Exception('NVIDIA stream error ${resp.statusCode}: $errBody');
      }

      // Proactively handle potential empty or slow streams
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
            // Support both 'delta' (streaming) and 'message' (fallback) structures
            final text = choice?['delta']?['content'] as String? ?? 
                         choice?['text'] as String? ?? 
                         choice?['delta']?['text'] as String?;
            
            if (text != null && text.isNotEmpty) yield text;
          } catch (e) {
            debugPrint('[Nvidia] JSON parse error: $e for line: $trimmedLine');
          }
        } else {
          debugPrint('[Nvidia] Non-data line received: $trimmedLine');
        }
      }
    } catch (e) {
      debugPrint('[Nvidia] Stream error: $e');
      rethrow;
    } finally {
      client.close();
    }
  }
}
