// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    hide Message;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

/// NetlessService — JARVIS offline AI powered by Gemma 4 E2B-it
/// Downloads ~1.5 GB once, then works 100% offline forever.
class NetlessService extends ChangeNotifier {
  // ── Singleton ─────────────────────────────────────────────────────────────
  static final NetlessService _instance = NetlessService._();
  factory NetlessService() => _instance;
  NetlessService._();

  // ── Notification IDs ──────────────────────────────────────────────────────
  static const int _notifId = 7001;
  static const String _channelId = 'netless_download';
  static const String _channelName = 'Netless Model Download';
  final FlutterLocalNotificationsPlugin _notif = FlutterLocalNotificationsPlugin();

  // ── HuggingFace model URL ─────────────────────────────────────────────────
  static const String _hfModelUrl =
      'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm';
  static const String _modelFileName = 'gemma4_e2b_it.litertlm';
  static const String _prefKeyPath = 'netless_model_path';
  static const String _prefKeyLoaded = 'netless_model_loaded';

  // ── Public state ──────────────────────────────────────────────────────────
  bool _isLoaded = false;
  bool _isLoading = false;
  bool _isDownloading = false;
  bool _isUnloading = false;
  double _downloadProgress = 0.0;
  String _status = 'Not initialised';
  String? _modelPath;
  InferenceModel? _model;

  bool get isLoaded => _isLoaded;
  bool get isLoading => _isLoading;
  bool get isDownloading => _isDownloading;
  bool get isUnloading => _isUnloading;
  double get downloadProgress => _downloadProgress;
  String get status => _status;
  bool get isAvailable => _isLoaded && _model != null;
  String? get modelPath => _modelPath;
  bool get hasFile => _modelPath != null && File(_modelPath!).existsSync();

  // ── Init (call on app start) ──────────────────────────────────────────────
  Future<void> init() async {
    await _ensureNotifChannel();
    final prefs = await SharedPreferences.getInstance();
    _modelPath = prefs.getString(_prefKeyPath);

    if (_modelPath != null && File(_modelPath!).existsSync()) {
      _status = 'Model downloaded. Tap to load.';
    } else {
      _modelPath = null;
      _status = 'Tap to download Gemma 4 E2B-it (~2.5 GB)';
    }
    notifyListeners();
  }

  // ── Notification channel setup ────────────────────────────────────────────
  Future<void> _ensureNotifChannel() async {
    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    await _notif.initialize(
      settings: const InitializationSettings(android: androidInit),
    );
    // Create progress notification channel
    final androidPlugin = _notif
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: 'Shows Netless (Gemma 4 E2B-it) download progress',
        importance: Importance.low,
        showBadge: false,
        playSound: false,
        enableVibration: false,
      ),
    );
  }

  Future<void> _showProgressNotif(int percent, String text) async {
    await _notif.show(
      id: _notifId,
      title: '🧠 JARVIS Netless Download',
      body: text,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelShowBadge: false,
          importance: Importance.low,
          priority: Priority.low,
          onlyAlertOnce: true,
          showProgress: true,
          maxProgress: 100,
          progress: percent,
          ongoing: true,
          autoCancel: false,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );
  }

  Future<void> _showDoneNotif(String text, {bool isError = false}) async {
    await _notif.cancel(id: _notifId);
    await _notif.show(
      id: _notifId + 1,
      title: isError ? '❌ Netless Download Failed' : '✅ JARVIS Netless Ready!',
      body: text,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.high,
          priority: Priority.high,
          autoCancel: true,
        ),
      ),
    );
  }

  // ── Download + auto-load ──────────────────────────────────────────────────
  Future<void> downloadAndLoad() async {
    if (_isDownloading || _isLoading) return;

    _isDownloading = true;
    _downloadProgress = 0;
    _setStatus('Starting download…');

    try {
      final dir = await getApplicationDocumentsDirectory();
      final savePath = '${dir.path}/$_modelFileName';
      final file = File(savePath);

      // Resume partially downloaded file
      int startByte = file.existsSync() ? file.lengthSync() : 0;
      if (startByte > 0) {
        _setStatus('Resuming download from ${(startByte / 1e6).toStringAsFixed(0)} MB…');
      }

      final client = http.Client();
      final request = http.Request('GET', Uri.parse(_hfModelUrl));
      if (startByte > 0) request.headers['Range'] = 'bytes=$startByte-';
      final response = await client.send(request);

      if (response.statusCode != 200 && response.statusCode != 206) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final totalBytes = (response.contentLength ?? 0) + startByte;
      int received = startByte;
      int lastNotifPercent = -1;

      final sink = file.openWrite(mode: startByte > 0 ? FileMode.append : FileMode.write);

      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (totalBytes > 0) {
          _downloadProgress = received / totalBytes;
          final percent = (_downloadProgress * 100).floor();
          final receivedMB = (received / 1e6).toStringAsFixed(1);
          final totalMB = (totalBytes / 1e6).toStringAsFixed(0);
          final statusText = 'Downloading… $receivedMB / $totalMB MB';
          _setStatus(statusText);
          // Update notification every 1%
          if (percent != lastNotifPercent) {
            lastNotifPercent = percent;
            _showProgressNotif(percent, '$receivedMB MB / $totalMB MB');
          }
        }
      }

      await sink.flush();
      await sink.close();
      client.close();

      _modelPath = savePath;
      _isDownloading = false;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKeyPath, savePath);

      _setStatus('Download complete — loading model…');
      notifyListeners();
      await _showProgressNotif(100, 'Download complete! Loading…');

      await loadModel();
    } catch (e) {
      _isDownloading = false;
      final msg = 'Download failed: $e';
      _setStatus(msg);
      await _showDoneNotif(msg, isError: true);
      debugPrint('[Netless] $e');
      notifyListeners();
    }
  }

  // ── Load model ────────────────────────────────────────────────────────────
  Future<void> loadModel() async {
    if (_isLoaded || _isLoading) return;
    if (_modelPath == null || !File(_modelPath!).existsSync()) {
      _setStatus('No model file found. Please download first.');
      return;
    }

    _isLoading = true;
    _setStatus('Loading Gemma 4 E2B-it into memory…');

    try {
      await FlutterGemma.initialize();

      await FlutterGemma.installModel(
        modelType: ModelType.gemma4,
        fileType: ModelFileType.litertlm,
      ).fromFile(_modelPath!).install();

      // Lower maxTokens to prevent OOM and use auto backend for better device compatibility
      _model = await FlutterGemma.getActiveModel(
        maxTokens: 1024,
        preferredBackend: PreferredBackend.auto,
      );

      _isLoaded = true;
      _isLoading = false;
      _setStatus('✅ Netless ready — Gemma 4 E2B-it (offline)');

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKeyLoaded, true);

      await _showDoneNotif('Gemma 4 E2B-it loaded. JARVIS works offline now!');
      debugPrint('[Netless] Model loaded from $_modelPath');
    } catch (e) {
      _isLoaded = false;
      _isLoading = false;
      _setStatus('Load failed: $e');
      await _showDoneNotif('Failed to load model: $e', isError: true);
      debugPrint('[Netless] Load error: $e');
      notifyListeners();
    }
  }

  // ── Unload model (free RAM) ───────────────────────────────────────────────
  Future<void> unloadModel() async {
    if (!_isLoaded && _model == null) return;
    _isUnloading = true;
    _setStatus('Unloading model from memory…');

    try {
      await _model?.close();
      _model = null;
      _isLoaded = false;
      _isUnloading = false;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKeyLoaded, false);
      _setStatus('Model unloaded. Storage file kept — tap Load to use again.');
      debugPrint('[Netless] Model unloaded');
    } catch (e) {
      _isUnloading = false;
      _setStatus('Unload error: $e');
      debugPrint('[Netless] Unload error: $e');
    }
    notifyListeners();
  }

  // ── Delete model file (free storage) ─────────────────────────────────────
  Future<void> deleteModel() async {
    await unloadModel();
    if (_modelPath != null && File(_modelPath!).existsSync()) {
      await File(_modelPath!).delete();
    }
    _modelPath = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKeyPath);
    await prefs.remove(_prefKeyLoaded);
    _setStatus('Model deleted. Download again to use Netless.');
    notifyListeners();
  }

  // ── Inference (streaming) ─────────────────────────────────────────────────
  Stream<String> generateStream(String prompt, {String? systemPrompt}) async* {
    if (!isAvailable) {
      yield '⚠️ Netless model is not loaded. Please load it from Settings → Netless.';
      return;
    }

    InferenceChat? chat;
    try {
      chat = await _model!.createChat(
        temperature: 0.7,
        topK: 40,
        randomSeed: 42,
        systemInstruction: systemPrompt ??
            'You are JARVIS, an intelligent offline AI assistant. '
                'Be concise, helpful, and friendly.',
      );

      await chat.addQueryChunk(Message.text(text: prompt, isUser: true));

      await for (final response in chat.generateChatResponseAsync()) {
        if (response is TextResponse && response.token.isNotEmpty) {
          yield response.token;
        }
      }
    } catch (e) {
      debugPrint('[Netless] Inference error: $e');
      yield '\n\n⚠️ Netless error: $e';
    } finally {
      await chat?.close();
    }
  }

  /// Non-streaming — collects all tokens
  Future<String> generate(String prompt, {String? systemPrompt}) async {
    final buf = StringBuffer();
    await for (final tok in generateStream(prompt, systemPrompt: systemPrompt)) {
      buf.write(tok);
    }
    return buf.toString();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  void _setStatus(String msg) {
    _status = msg;
    notifyListeners();
  }

  String get storageInfo {
    if (_modelPath == null) return 'Not downloaded';
    final file = File(_modelPath!);
    if (!file.existsSync()) return 'File missing';
    final mb = file.lengthSync() / 1e6;
    return '${mb.toStringAsFixed(0)} MB on device';
  }
}
