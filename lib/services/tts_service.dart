import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool _isPlaying = false;

  bool get isPlaying => _isPlaying;

  Future<void> init() async {
    // en-IN allows better pronunciation of Indian/Tamil names and terms
    await _tts.setLanguage("en-IN");
    await _tts.setSpeechRate(0.55); // Slightly faster, more natural speed
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.05); // Slightly clearer/crisper tone
  }

  void setHandlers({VoidCallback? onStart, VoidCallback? onComplete, Function(String)? onError}) {
    _tts.setStartHandler(() {
      _isPlaying = true;
      if (onStart != null) onStart();
    });

    _tts.setCompletionHandler(() {
      _isPlaying = false;
      if (onComplete != null) onComplete();
    });

    _tts.setErrorHandler((msg) {
      _isPlaying = false;
      if (onError != null) onError(msg);
    });
  }

  Future<void> speak(String text) async {
    if (text.isEmpty) return;
    
    // Sanitize markdown and special tags: remove #, *, _, `, XML tags etc. but keep Emojis
    String cleanText = text
      .replaceAll(RegExp(r'<[^>]*>'), '') // Strip out custom tags like <SCHEDULE_REMINDER>
      .replaceAll(RegExp(r'#+\s'), '') // Headings
      .replaceAll(RegExp(r'[*_]{1,3}'), '') // Bold/Italic
      .replaceAll(RegExp(r'`{1,3}[^`]*`{1,3}'), '') // Code blocks
      .replaceAll(RegExp(r'\[([^\]]+)\]\([^)]+\)'), r'$1') // Links
      .replaceAll(RegExp(r'^[-*+]\s', multiLine: true), '') // List markers
      .replaceAll(RegExp(r'\n+'), ' ') // Newlines to spaces
      .trim();

    if (cleanText.isEmpty) return;
    
    // Check for Tamil characters: Unicode range U+0B80 to U+0BFF
    if (RegExp(r'[\u0B80-\u0BFF]').hasMatch(cleanText)) {
      await _tts.setLanguage("ta-IN");
    } else {
      // Default back to English for other responses
      await _tts.setLanguage("en-IN");
    }

    _isPlaying = true;
    await _tts.speak(cleanText);
  }

  Future<void> stop() async {
    await _tts.stop();
    _isPlaying = false;
  }
}
