import 'package:flutter/material.dart';
import '../services/ollama_cloud_service.dart';

class OllamaProvider extends ChangeNotifier {
  final OllamaCloudService _service = OllamaCloudService();

  List<OllamaModel>      _models     = [];
  bool                   _loading    = false;
  bool                   _testing    = false;
  bool                   _streaming  = false;
  String?                _error;
  Map<String, dynamic>?  _testResult;
  String                 _chatResponse = '';

  List<OllamaModel>     get models        => _models;
  bool                  get loading        => _loading;
  bool                  get testing        => _testing;
  bool                  get streaming      => _streaming;
  String?               get error          => _error;
  Map<String, dynamic>? get testResult     => _testResult;
  String                get chatResponse   => _chatResponse;
  String                get selectedModel  => _service.selectedModel;
  bool                  get useCloud       => _service.useCloud;
  String                get apiKey         => _service.apiKey;
  bool                  get isConfigured   => _service.isConfigured;
  OllamaCloudService    get service        => _service;

  Future<void> init() async {
    await _service.init();
    notifyListeners();
  }

  Future<void> fetchModels() async {
    _loading = true;
    _error   = null;
    notifyListeners();
    try {
      _models = await _service.fetchAvailableModels();
    } catch (e) {
      _error = e.toString();
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> saveSettings({
    String? apiKey,
    String? baseUrl,
    String? localUrl,
    bool?   useCloud,
    String? selectedModel,
  }) async {
    await _service.saveSettings(
      apiKey:        apiKey,
      baseUrl:       baseUrl,
      localUrl:      localUrl,
      useCloud:      useCloud,
      selectedModel: selectedModel,
    );
    notifyListeners();
  }

  Future<void> syncSettings() async {
    await _service.init();
    notifyListeners();
  }

  Future<void> testConnection() async {
    _testing    = true;
    _testResult = null;
    notifyListeners();
    _testResult = await _service.testConnection();
    _testing    = false;
    notifyListeners();
  }

  // Streaming chat — tokens appear one by one
  Future<void> sendMessage(String prompt) async {
    _chatResponse = '';
    _streaming    = true;
    _error        = null;
    notifyListeners();
    try {
      await for (final chunk in _service.chatStream(
        messages: [OllamaChatMessage(role: 'user', content: prompt)],
      )) {
        _chatResponse += chunk;
        notifyListeners();
      }
    } catch (e) {
      _error = e.toString();
    }
    _streaming = false;
    notifyListeners();
  }
}
