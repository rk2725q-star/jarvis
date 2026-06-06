import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart'; // Relocated from below
import '../core/security/secure_storage_service.dart';

// ─────────────────────────────────────────────
// DATA MODELS
// ─────────────────────────────────────────────

class OllamaModel {
  final String name;
  final String id;
  final String size;
  final String modifiedAt;
  final bool isCloud;

  OllamaModel({
    required this.name,
    required this.id,
    required this.size,
    required this.modifiedAt,
    required this.isCloud,
  });

  factory OllamaModel.fromJson(
    Map<String, dynamic> json, {
    bool? isCloudOverride,
  }) {
    final name = json['name'] as String? ?? json['model'] as String? ?? '';
    return OllamaModel(
      name: name,
      id: json['digest'] as String? ?? json['id'] as String? ?? '',
      size: _formatSize(json['size'] as int? ?? 0),
      modifiedAt: json['modified_at'] as String? ?? '',
      isCloud:
          isCloudOverride ??
          (name.contains('-cloud') || (json['details']?['format'] == null)),
    );
  }

  static String _formatSize(int bytes) {
    if (bytes == 0) return 'Cloud';
    if (bytes > 1e12) return '${(bytes / 1e12).toStringAsFixed(1)} TB';
    if (bytes > 1e9) return '${(bytes / 1e9).toStringAsFixed(1)} GB';
    if (bytes > 1e6) return '${(bytes / 1e6).toStringAsFixed(0)} MB';
    return '$bytes B';
  }

  String get displayName =>
      name.replaceAll('-cloud', '').replaceAll(':latest', '');
  String get tag => isCloud ? 'cloud' : 'local';
}

class OllamaChatMessage {
  final String role; // 'user' | 'assistant' | 'system'
  final String content;
  OllamaChatMessage({required this.role, required this.content});
  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}

class OllamaResponse {
  final String content;
  final bool done;
  final int? totalDuration;
  final int? evalCount;

  OllamaResponse({
    required this.content,
    required this.done,
    this.totalDuration,
    this.evalCount,
  });
}

// ─────────────────────────────────────────────
// MAIN SERVICE
// ─────────────────────────────────────────────

class OllamaCloudService {
  static const String _prefKeyMode = 'ollama_use_cloud';
  static const String _prefKeyModel = 'ollama_selected_model';

  String _apiKey = '';
  String _cloudBaseUrl = kIsWeb
      ? Uri.base.resolve('/api/ollama').toString().replaceAll(RegExp(r'/$'), '')
      : 'https://ollama.com';
  String _localUrl = 'http://127.0.0.1:11434';
  bool _useCloud = true;
  String _selectedModel = 'gpt-oss:120b';
  List<OllamaModel> _availableModels = [];
  final SecureStorageService _secureStorage = SecureStorageService();

  // Reusable client for better performance (connection pooling)
  final http.Client _client = http.Client();

  // ── Getters ───────────────────────────────
  String get selectedModel => _selectedModel;
  List<OllamaModel> get availableModels => _availableModels;
  bool get useCloud => _useCloud;
  String get apiKey => _apiKey;
  String get cloudBaseUrl => _cloudBaseUrl;
  bool get isConfigured => _apiKey.isNotEmpty || !_useCloud;

  // ── Init / persist ────────────────────────
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _apiKey = await _secureStorage.getApiKey('ollamaCloud') ?? '';

    var savedCloudUrl =
        await _secureStorage.getBaseUrl('ollamaCloud') ??
        'https://ollama.com';
    
    // Dynamic migration: if they had the old api.ollama.com default, migrate it to ollama.com
    if (savedCloudUrl == 'https://api.ollama.com' || savedCloudUrl == 'https://api.ollama.com/') {
      savedCloudUrl = 'https://ollama.com';
      await _secureStorage.saveBaseUrl('ollamaCloud', 'https://ollama.com');
    }

    if (kIsWeb &&
        (savedCloudUrl == 'https://ollama.com' ||
            savedCloudUrl.isEmpty ||
            savedCloudUrl == '/api/ollama')) {
      _cloudBaseUrl = Uri.base
          .resolve('/api/ollama')
          .toString()
          .replaceAll(RegExp(r'/$'), '');
    } else {
      _cloudBaseUrl = savedCloudUrl;
    }

    _localUrl =
        await _secureStorage.getBaseUrl('ollamaLocal') ??
        'http://127.0.0.1:11434';
    _useCloud = prefs.getBool(_prefKeyMode) ?? true;
    _selectedModel = prefs.getString(_prefKeyModel) ?? 'gpt-oss:120b';
  }

  Future<void> saveSettings({
    String? apiKey,
    String? baseUrl,
    String? localUrl,
    bool? useCloud,
    String? selectedModel,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (apiKey != null) {
      _apiKey = apiKey;
      await _secureStorage.saveApiKey('ollamaCloud', apiKey);
    }
    if (baseUrl != null) {
      var url = baseUrl.trim().isEmpty
          ? 'https://ollama.com'
          : baseUrl.trim();
      if (url == 'https://api.ollama.com' || url == 'https://api.ollama.com/') {
        url = 'https://ollama.com';
      }
      _cloudBaseUrl = url;
      await _secureStorage.saveBaseUrl('ollamaCloud', _cloudBaseUrl);
    }
    if (localUrl != null) {
      _localUrl = localUrl;
      await _secureStorage.saveBaseUrl('ollamaLocal', localUrl);
    }
    if (useCloud != null) {
      _useCloud = useCloud;
      await prefs.setBool(_prefKeyMode, useCloud);
    }
    if (selectedModel != null) {
      _selectedModel = selectedModel;
      await prefs.setString(_prefKeyModel, selectedModel);
    }
  }

  // Add this method — called by ai_router for cloud URL override
  void setBaseUrl(String url) {
    if (url.isNotEmpty) {
      _cloudBaseUrl = url;
    }
  }

  // Add this method — called by ai_router for local URL override
  void setLocalUrl(String url) {
    if (url.isNotEmpty) {
      _localUrl = url;
      // Ensure no trailing slash for consistency
      if (_localUrl.endsWith('/')) {
        _localUrl = _localUrl.substring(0, _localUrl.length - 1);
      }
    }
  }

  // ── Fetch models ──────────────────────────
  Future<bool> isLocalAvailable() async {
    try {
      final res = await _client
          .get(Uri.parse('$_localUrl/api/tags'))
          .timeout(const Duration(seconds: 1));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<List<OllamaModel>> fetchAvailableModels() async {
    final List<OllamaModel> models = [];

    // Always try local
    try {
      final localModels = await _fetchLocalModels();
      models.addAll(localModels);
    } catch (_) {}

    // Try cloud if key provided
    if (_apiKey.isNotEmpty) {
      try {
        final cloudModels = await _fetchCloudModels();
        // Use a set to track names for deduplication
        final existingNames = models.map((m) => m.name).toSet();
        for (final m in cloudModels) {
          if (!existingNames.contains(m.name)) {
            models.add(m);
          }
        }
      } catch (e) {
        if (models.isEmpty) rethrow;
      }
    }

    _availableModels = models;
    return models;
  }

  Future<List<OllamaModel>> _fetchLocalModels() async {
    try {
      final res = await _client
          .get(Uri.parse('$_localUrl/api/tags'))
          .timeout(const Duration(seconds: 4));
      if (res.statusCode != 200) return [];
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final list = json['models'] as List<dynamic>? ?? [];
      return list
          .map(
            (e) => OllamaModel.fromJson(
              e as Map<String, dynamic>,
              isCloudOverride: false,
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<OllamaModel>> _fetchCloudModels() async {
    final res = await _client
        .get(
          Uri.parse('$_cloudBaseUrl/api/tags'),
          headers: {
            'Authorization': 'Bearer $_apiKey',
            'Content-Type': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 12));

    if (res.statusCode == 401) throw Exception('Invalid API key');
    if (res.statusCode != 200) {
      throw Exception('Cloud API returned ${res.statusCode}');
    }

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final list = json['models'] as List<dynamic>? ?? [];
    return list
        .map(
          (e) => OllamaModel.fromJson(
            e as Map<String, dynamic>,
            isCloudOverride: true,
          ),
        )
        .toList();
  }

  // ── Chat (non-streaming) ──────────────────
  Future<OllamaResponse> chat({
    required List<OllamaChatMessage> messages,
    String? model,
    String? systemPrompt,
    bool? useCloudOverride,
    String? imageBase64,
  }) async {
    final targetModel = model ?? _selectedModel;
    final allMessages = <Map<String, dynamic>>[];
    final goCloud = useCloudOverride ?? _useCloud;

    // --- Auto-detect OpenAI-compatible models on Ollama Cloud ---
    // Models like kimi-k2.6, deepseek-v4-flash/pro, minimax-m3 need /v1/chat/completions
    final bool useOpenAiEndpoint =
        goCloud &&
        (targetModel.contains('kimi') ||
            targetModel.contains('deepseek-v4') ||
            targetModel.contains('deepseek-r2') ||
            targetModel.contains('qwen') ||
            targetModel.contains('command') ||
            targetModel.contains('mistral') ||
            targetModel.contains('mixtral') ||
            targetModel.contains('minimax') ||
            targetModel.contains('m3'));

    if (systemPrompt != null) {
      allMessages.add({'role': 'system', 'content': systemPrompt});
    }

    if (useOpenAiEndpoint) {
      for (int i = 0; i < messages.length; i++) {
        final m = messages[i];
        if (imageBase64 != null && m.role == 'user' && i == messages.length - 1) {
          allMessages.add({
            'role': 'user',
            'content': [
              {'type': 'text', 'text': m.content},
              {
                'type': 'image_url',
                'image_url': {
                  'url': 'data:image/jpeg;base64,$imageBase64',
                }
              }
            ]
          });
        } else {
          allMessages.add(m.toJson());
        }
      }
    } else {
      // Handle Image Support for Ollama Vision Models (llava, moondream, etc.)
      for (var m in messages) {
        final msgJson = m.toJson();
        if (imageBase64 != null && m.role == 'user') {
          msgJson['images'] = [imageBase64];
        }
        allMessages.add(msgJson);
      }
    }

    final http.Response res;

    if (goCloud) {
      if (_apiKey.isEmpty) {
        throw Exception(
          'Ollama Cloud Key is required. Please enter it in Settings.',
        );
      }

      if (useOpenAiEndpoint) {
        // OpenAI-compatible path for newer models
        final body = jsonEncode({
          'model': targetModel,
          'messages': allMessages,
          'stream': false,
        });
        res = await _client
            .post(
              Uri.parse('$_cloudBaseUrl/v1/chat/completions'),
              headers: {
                'Authorization': 'Bearer $_apiKey',
                'Content-Type': 'application/json',
              },
              body: body,
            )
            .timeout(const Duration(seconds: 120));

        if (res.statusCode == 401) throw Exception('API key invalid or expired');
        if (res.statusCode == 404) throw Exception('Model "$targetModel" not found on cloud');
        if (res.statusCode != 200) throw Exception('Ollama error ${res.statusCode}: ${res.body}');

        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final content = data['choices']?[0]?['message']?['content'] as String? ?? '';
        return OllamaResponse(content: content, done: true);
      } else {
        // Legacy Ollama /api/chat path
        final body = jsonEncode({
          'model': targetModel,
          'messages': allMessages,
          'stream': false,
        });
        res = await _client
            .post(
              Uri.parse('$_cloudBaseUrl/api/chat'),
              headers: {
                'Authorization': 'Bearer $_apiKey',
                'Content-Type': 'application/json',
              },
              body: body,
            )
            .timeout(const Duration(seconds: 120));
      }
    } else {
      final body = jsonEncode({
        'model': targetModel,
        'messages': allMessages,
        'stream': false,
      });
      res = await _client
          .post(
            Uri.parse('$_localUrl/api/chat'),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 30));
    }

    if (res.statusCode == 401) throw Exception('API key invalid or expired');
    if (res.statusCode == 404) {
      throw Exception('Model "$targetModel" not found');
    }
    if (res.statusCode != 200) {
      throw Exception('Ollama error ${res.statusCode}: ${res.body}');
    }

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final message = json['message'] as Map<String, dynamic>? ?? {};

    return OllamaResponse(
      content: message['content'] as String? ?? '',
      done: json['done'] as bool? ?? true,
      totalDuration: json['total_duration'] as int?,
      evalCount: json['eval_count'] as int?,
    );
  }

  // ── Streaming chat ────────────────────────
  Stream<String> chatStream({
    required List<OllamaChatMessage> messages,
    String? model,
    String? systemPrompt,
    bool? useCloudOverride,
    String? imageBase64,
  }) async* {
    final targetModel = model ?? _selectedModel;
    final allMessages = <Map<String, dynamic>>[];
    final goCloud = useCloudOverride ?? _useCloud;

    // --- Auto-detect OpenAI-compatible models on Ollama Cloud ---
    // Models like kimi-k2.6, deepseek-v4-flash/pro, minimax-m3 need /v1/chat/completions
    final bool useOpenAiEndpoint =
        goCloud &&
        (targetModel.contains('kimi') ||
            targetModel.contains('deepseek-v4') ||
            targetModel.contains('deepseek-r2') ||
            targetModel.contains('qwen') ||
            targetModel.contains('command') ||
            targetModel.contains('mistral') ||
            targetModel.contains('mixtral') ||
            targetModel.contains('minimax') ||
            targetModel.contains('m3'));

    if (systemPrompt != null) {
      allMessages.add({'role': 'system', 'content': systemPrompt});
    }

    if (useOpenAiEndpoint) {
      for (int i = 0; i < messages.length; i++) {
        final m = messages[i];
        if (imageBase64 != null && m.role == 'user' && i == messages.length - 1) {
          allMessages.add({
            'role': 'user',
            'content': [
              {'type': 'text', 'text': m.content},
              {
                'type': 'image_url',
                'image_url': {
                  'url': 'data:image/jpeg;base64,$imageBase64',
                }
              }
            ]
          });
        } else {
          allMessages.add(m.toJson());
        }
      }
    } else {
      for (var m in messages) {
        final msgJson = m.toJson();
        if (imageBase64 != null && m.role == 'user') {
          msgJson['images'] = [imageBase64];
        }
        allMessages.add(msgJson);
      }
    }

    final String endpoint;
    if (goCloud) {
      endpoint = useOpenAiEndpoint
          ? '$_cloudBaseUrl/v1/chat/completions'
          : '$_cloudBaseUrl/api/chat';
    } else {
      endpoint = '$_localUrl/api/chat';
    }

    final body = jsonEncode({
      'model': targetModel,
      'messages': allMessages,
      'stream': true,
    });

    final request = http.Request('POST', Uri.parse(endpoint))
      ..headers['Content-Type'] = 'application/json'
      ..headers['Accept'] = 'application/json'
      ..body = body;

    if (goCloud) {
      if (_apiKey.isEmpty) throw Exception('Ollama Cloud Key set but empty');
      request.headers['Authorization'] = 'Bearer $_apiKey';
    }

    try {
      final streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 120));

      if (streamed.statusCode != 200) {
        final errBody = await streamed.stream.bytesToString();
        throw Exception('Server error ${streamed.statusCode}: $errBody');
      }

      await for (final line
          in streamed.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        if (line.trim().isEmpty) continue;
        try {
          String jsonStr = line.trim();
          if (jsonStr.startsWith('data: ')) {
            jsonStr = jsonStr.substring(6).trim();
            if (jsonStr == '[DONE]') break;
          }
          final json = jsonDecode(jsonStr) as Map<String, dynamic>;

          // Try Ollama format first
          final message = json['message'] as Map<String, dynamic>?;
          if (message != null) {
            final content = message['content'] as String?;
            if (content != null && content.isNotEmpty) yield content;
            if (json['done'] == true) break;
          } else {
            // OpenAI SSE format (kimi, deepseek-v4 etc.)
            final choices = json['choices'] as List<dynamic>?;
            if (choices != null && choices.isNotEmpty) {
              final choice = choices[0] as Map<String, dynamic>?;
              final delta = choice?['delta'] as Map<String, dynamic>?;
              final text =
                  delta?['content'] as String? ?? choice?['text'] as String?;
              if (text != null && text.isNotEmpty) yield text;
              if (choice?['finish_reason'] != null) break;
            }
          }
        } catch (_) {}
      }
    } finally {
      // Don't close persistent client
    }
  }

  // ── Web Search ───────────────────────────
  Future<List<Map<String, dynamic>>> webSearch(
    String query, {
    int maxResults = 5,
  }) async {
    if (_apiKey.isEmpty) throw Exception('API key required for web search');

    final res = await _client
        .post(
          Uri.parse('https://ollama.com/api/web_search'),
          headers: {
            'Authorization': 'Bearer $_apiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'query': query, 'max_results': maxResults}),
        )
        .timeout(const Duration(seconds: 15));

    if (res.statusCode != 200) {
      throw Exception('Web search failed: ${res.statusCode} ${res.body}');
    }

    final dynamic data = jsonDecode(res.body);
    if (data is List) {
      return data.cast<Map<String, dynamic>>();
    } else if (data is Map && data.containsKey('results')) {
      final results = data['results'];
      if (results is List) return results.cast<Map<String, dynamic>>();
    }

    // Fallback or empty
    return [];
  }

  // ── Single prompt shortcut ────────────────
  Future<String> generate(String prompt, {String? model}) async {
    final res = await chat(
      messages: [OllamaChatMessage(role: 'user', content: prompt)],
      model: model,
    );
    return res.content;
  }

  Future<String> generateImage(String prompt, {String? model}) async {
    if (_apiKey.isEmpty) {
      throw Exception('Ollama Cloud API Key is required for image generation.');
    }

    final targetModel = model ?? _selectedModel;
    final body = jsonEncode({
      'model': targetModel.contains('minimax') || targetModel.contains('m3') ? 'minimax-m3' : targetModel,
      'prompt': prompt,
      'n': 1,
      'size': '1024x1024',
      'response_format': 'b64_json',
    });

    final res = await _client.post(
      Uri.parse('$_cloudBaseUrl/v1/images/generations'),
      headers: {
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
      },
      body: body,
    ).timeout(const Duration(seconds: 90));

    if (res.statusCode != 200) {
      throw Exception('Ollama Cloud Image Gen error ${res.statusCode}: ${res.body}');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final images = (data['data'] as List?)?.cast<Map>() ?? [];
    if (images.isEmpty) throw Exception('Image generation returned no data');

    final b64 = images.first['b64_json'] as String?;
    if (b64 != null) {
      return 'data:image/png;base64,$b64';
    }

    final url = images.first['url'] as String?;
    if (url != null) {
      return url;
    }

    throw Exception('No base64 or URL found in response');
  }

  // ── Test connection ───────────────────────
  Future<Map<String, dynamic>> testConnection() async {
    try {
      final start = DateTime.now();
      final response = await generate('Reply with exactly: OK');
      final ms = DateTime.now().difference(start).inMilliseconds;
      return {
        'success': true,
        'model': _selectedModel,
        'response': response.trim(),
        'latency_ms': ms,
        'mode': _useCloud ? 'cloud' : 'local',
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }
}
