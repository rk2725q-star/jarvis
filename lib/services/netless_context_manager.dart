import 'package:jarvis_ai/services/netless_service.dart';

class ChatMessage {
  final int index;
  final String role;
  final String content;
  final DateTime timestamp;

  ChatMessage({
    required this.index,
    required this.role,
    required this.content,
    required this.timestamp,
  });
}

class NetlessContextManager {
  static const int gemmaMaxTokens = 1024;
  static const int safeLimit = 800; // leave room for response
  static const int charsPerToken = 3; // Tamil+English mixed = ~3 chars/token
  static const int summaryMaxChars = 400; // summary budget

  final List<ChatMessage> _history = [];
  String _rollingsummary = '';
  int _messageCounter = 0;

  // ─── PUBLIC API ───────────────────────────────────────────────

  /// Call this before every Netless request
  Future<String> prepareContext(
    String newUserMessage,
    NetlessService netless,
  ) async {
    _messageCounter++;

    // Tag message with index for direct access
    _history.add(
      ChatMessage(
        index: _messageCounter,
        role: 'user',
        content: newUserMessage,
        timestamp: DateTime.now(),
      ),
    );

    // Compress if needed
    if (_estimatedTokens() > safeLimit) {
      await _compressHistory(netless);
    }

    return _buildPayload();
  }

  /// Add assistant response to history
  void addAssistantResponse(String content) {
    _history.add(
      ChatMessage(
        index: _messageCounter,
        role: 'assistant',
        content: content,
        timestamp: DateTime.now(),
      ),
    );
  }

  /// Direct access by message index (e.g. "refer to message 3")
  ChatMessage? getByIndex(int index) {
    for (final m in _history) {
      if (m.index == index) return m;
    }
    return null;
  }

  /// Parse user intent for message references
  /// e.g. "like you said in message 2" → returns that message
  ChatMessage? parseReference(String userMessage) {
    // Pattern: "message 3", "#3", "response 3", "third message"
    final numericPattern = RegExp(r'message\s+(\d+)|#(\d+)|response\s+(\d+)');
    final ordinalMap = {
      'first': 1,
      'second': 2,
      'third': 3,
      'fourth': 4,
      'fifth': 5,
      'last': _messageCounter,
    };

    final numMatch = numericPattern.firstMatch(userMessage.toLowerCase());
    if (numMatch != null) {
      final idx = int.tryParse(
        numMatch.group(1) ?? numMatch.group(2) ?? numMatch.group(3) ?? '',
      );
      if (idx != null) return getByIndex(idx);
    }

    for (final entry in ordinalMap.entries) {
      if (userMessage.toLowerCase().contains(entry.key)) {
        return getByIndex(entry.value);
      }
    }
    return null;
  }

  // ─── PRIVATE ──────────────────────────────────────────────────

  int _estimatedTokens() {
    int chars = _rollingsummary.length;
    for (final msg in _history) {
      chars += msg.content.length;
    }
    return chars ~/ charsPerToken;
  }

  Future<void> _compressHistory(NetlessService netless) async {
    if (_history.length < 4) return;

    // Keep last 2 messages fresh, compress the rest
    final toCompress = _history.sublist(0, _history.length - 2);
    _history.removeRange(0, _history.length - 2);

    final block = toCompress
        .map((m) => '[${m.index}] ${m.role}: ${_truncate(m.content, 200)}')
        .join('\n');

    // Use a TINY summarization prompt — must fit in tokens itself!
    final summaryPrompt = 'Summarize in 2 sentences:\n$block';

    try {
      final newSummary = await netless.generate(summaryPrompt);

      // Merge with existing rolling summary
      if (_rollingsummary.isNotEmpty) {
        _rollingsummary = _truncate(
          'Previous: $_rollingsummary | Now: $newSummary',
          summaryMaxChars,
        );
      } else {
        _rollingsummary = _truncate(newSummary, summaryMaxChars);
      }
    } catch (_) {
      // If summarization itself fails, just drop old messages
      _rollingsummary = _truncate(
        'Earlier conversation (${toCompress.length} messages) omitted.',
        summaryMaxChars,
      );
    }
  }

  String _buildPayload() {
    final buffer = StringBuffer();

    // Inject rolling summary as system context
    if (_rollingsummary.isNotEmpty) {
      buffer.writeln('[SYSTEM SUMMARY: $_rollingsummary]');
      buffer.writeln('---');
    }

    // Append recent messages
    for (final msg in _history) {
      buffer.writeln('${msg.role.toUpperCase()}: ${msg.content}');
    }

    return _truncate(buffer.toString(), safeLimit * charsPerToken);
  }

  String _truncate(String text, int maxChars) {
    if (text.length <= maxChars) return text;
    return '${text.substring(text.length - maxChars)}…';
  }

  // Expose for UI token meter
  int get estimatedTokens => _estimatedTokens();
  int get messageCount => _messageCounter;
  String get summary => _rollingsummary;
}
