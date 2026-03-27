class DiagramTrigger {
  static const List<String> _keywords = [
    'draw', 'diagram', 'chart', 'visualize', 'show me how',
    'flowchart', 'architecture', 'flow of', 'explain visually',
    'how does', 'how do', 'steps of', 'process of',
    'map out', 'sketch', 'illustrate', 'layout',
  ];

  /// Returns true if the message is asking for a diagram
  static bool isDiagramRequest(String message) {
    final lower = message.toLowerCase();
    return _keywords.any((k) => lower.contains(k));
  }

  /// Extracts a clean title for the AppBar from the request
  static String extractTitle(String message) {
    final lower = message.toLowerCase();
    for (final keyword in _keywords) {
      if (lower.contains(keyword)) {
        final cleaned = message
            .toLowerCase()
            .replaceAll(keyword, '')
            .replaceAll(RegExp(r'[^\w\s]'), '')
            .trim();
        final words = cleaned.split(' ')
            .where((w) => w.isNotEmpty)
            .take(4)
            .join(' ');
        return words.isEmpty ? 'Diagram' : words;
      }
    }
    return 'Diagram';
  }
}
