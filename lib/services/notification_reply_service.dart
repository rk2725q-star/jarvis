import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

/// A completely self-contained, background-safe AI caller for notification replies.
/// Does NOT use AIRouter (which extends ChangeNotifier — forbidden in isolates).
/// Fallback chain: Gemini → Nvidia → Ollama Cloud
/// All calls are non-streaming (simple HTTP POST) for maximum reliability.
class NotificationReplyService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const String _systemPrompt =
      "You are JARVIS. The user sent you a direct notification reply. "
      "Be extremely warm and concise. Max 2 sentences, no markdown, no emojis.";

  /// Entry point: tries each provider in order, returns first success.
  static Future<String> generateReply(String userReply, String notifTitle) async {
    final prompt = "The user replied '$userReply' to your notification: '$notifTitle'. Acknowledge it warmly in 1-2 short sentences.";
    final prefs = await SharedPreferences.getInstance();

    // 1. Try Gemini
    try {
      final geminiKey = await _storage.read(key: 'api_gemini');
      final geminiModel = prefs.getString('provider_gemini_model') ?? 'gemini-1.5-flash';
      if (geminiKey != null && geminiKey.isNotEmpty) {
        debugPrint('[NotifReply] Trying Gemini ($geminiModel)...');
        final result = await _callGemini(geminiKey, geminiModel, prompt);
        if (result.isNotEmpty) {
          debugPrint('[NotifReply] Gemini success: $result');
          return result;
        }
      }
    } catch (e) {
      debugPrint('[NotifReply] Gemini failed: $e — falling back...');
    }

    // 2. Try NVIDIA
    try {
      final nvidiaKey = await _storage.read(key: 'api_nvidia');
      final nvidiaModel = prefs.getString('provider_nvidia_model') ?? 'meta/llama-3.1-70b-instruct';
      if (nvidiaKey != null && nvidiaKey.isNotEmpty) {
        debugPrint('[NotifReply] Trying NVIDIA ($nvidiaModel)...');
        final result = await _callNvidia(nvidiaKey, nvidiaModel, prompt);
        if (result.isNotEmpty) {
          debugPrint('[NotifReply] NVIDIA success: $result');
          return result;
        }
      }
    } catch (e) {
      debugPrint('[NotifReply] NVIDIA failed: $e — falling back...');
    }

    // 3. Try Ollama Cloud
    try {
      // SecureStorageService forces lowercase: provider.toLowerCase()
      final ollamaKey = await _storage.read(key: 'api_ollamacloud') ?? '';
      final ollamaUrl = await _storage.read(key: 'url_ollamacloud') ?? 'http://127.0.0.1:11434';
      final ollamaModel = prefs.getString('provider_ollamaCloud_model') ?? 'llama3';
      
      // Ollama does NOT strictly require an API key (e.g. standard local or ngrok proxy)
      debugPrint('[NotifReply] Trying Ollama Cloud ($ollamaModel) at $ollamaUrl...');
      final result = await _callOllamaCloud(ollamaKey, ollamaUrl, ollamaModel, prompt);
      if (result.isNotEmpty) {
        debugPrint('[NotifReply] Ollama success: $result');
        return result;
      }
    } catch (e) {
      debugPrint('[NotifReply] Ollama Cloud failed: $e');
    }

    // All providers failed
    return "Got your message! I'll catch up with you soon.";
  }

  // ── Direct Gemini REST call (non-streaming) ────────────────────────────────
  static Future<String> _callGemini(String apiKey, String model, String prompt) async {
    final body = jsonEncode({
      'contents': [
        {
          'parts': [{'text': prompt}],
          'role': 'user',
        }
      ],
      'systemInstruction': {
        'parts': [{'text': _systemPrompt}]
      },
      'generationConfig': {
        'maxOutputTokens': 150,
        'temperature': 0.7,
      }
    });

    final modelPath = model.startsWith('models/') ? model : 'models/$model';
    final res = await http.post(
      Uri.parse('https://generativelanguage.googleapis.com/v1beta/$modelPath:generateContent'),
      headers: {
        'Content-Type': 'application/json',
        'x-goog-api-key': apiKey,
      },
      body: body,
    ).timeout(const Duration(seconds: 20));

    if (res.statusCode != 200) {
      throw Exception('Gemini HTTP ${res.statusCode}: ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data['candidates']?[0]?['content']?['parts']?[0]?['text'] as String? ?? '';
  }

  // ── Direct NVIDIA REST call ─────────────────────────────────────────────────
  static Future<String> _callNvidia(String apiKey, String model, String prompt) async {
    final res = await http.post(
      Uri.parse('https://integrate.api.nvidia.com/v1/chat/completions'),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': model,
        'messages': [
          {'role': 'system', 'content': _systemPrompt},
          {'role': 'user', 'content': prompt},
        ],
        'temperature': 0.7,
        'max_tokens': 150,
        'stream': false,
      }),
    ).timeout(const Duration(seconds: 25));

    if (res.statusCode != 200) {
      throw Exception('NVIDIA HTTP ${res.statusCode}: ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data['choices']?[0]?['message']?['content'] as String? ?? '';
  }

  // ── Direct Ollama Cloud REST call ────────────────────────────────────────
  static Future<String> _callOllamaCloud(String apiKey, String baseUrl, String model, String prompt) async {
    final cleanUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final res = await http.post(
      Uri.parse('$cleanUrl/api/chat'),
      headers: {
        'Content-Type': 'application/json',
        if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        'model': model,
        'messages': [
          {'role': 'system', 'content': _systemPrompt},
          {'role': 'user', 'content': prompt},
        ],
        'stream': false,
      }),
    ).timeout(const Duration(seconds: 25));

    if (res.statusCode != 200) {
      throw Exception('Ollama HTTP ${res.statusCode}: ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data['message']?['content'] as String? ?? '';
  }
}
