class DiagramTrigger {
  static const List<String> _diagramPhrases = [
    'diagram',
    'flowchart',
    'visualize',
    'architecture map',
  ];

  /// Returns true if the message is explicitly asking to draw a diagram
  static bool isDiagramRequest(String message) {
    final lower = message.toLowerCase().trim();

    if (lower.startsWith('/diagram') || lower.startsWith('/visualize')) {
      return true;
    }

    final hasAction =
        lower.contains('draw') ||
        lower.contains('visualize') ||
        lower.contains('map out') ||
        lower.contains('flowchart');
    final hasSubject =
        lower.contains('diagram') ||
        lower.contains('architecture') ||
        lower.contains('flowchart') ||
        lower.contains('visualize');

    if (hasAction && hasSubject) {
      if (message.length > 500) {
        final endChars = lower.substring(
          lower.length - (200 > lower.length ? lower.length : 200),
        );
        final startChars = lower.substring(
          0,
          200 > lower.length ? lower.length : 200,
        );

        final intentInStart =
            (startChars.contains('draw') || startChars.contains('visualize')) &&
            (startChars.contains('diagram') ||
                startChars.contains('flowchart') ||
                startChars.contains('architecture'));
        final intentInEnd =
            (endChars.contains('draw') || endChars.contains('visualize')) &&
            (endChars.contains('diagram') ||
                endChars.contains('flowchart') ||
                endChars.contains('architecture'));

        return intentInStart || intentInEnd;
      }
      return true;
    }
    return false;
  }

  /// Extracts a clean title for the AppBar from the request
  static String extractTitle(String message) {
    final lower = message.toLowerCase();
    for (final keyword in _diagramPhrases) {
      if (lower.contains(keyword)) {
        final cleaned = message
            .toLowerCase()
            .replaceAll(keyword, '')
            .replaceAll(RegExp(r'[^\w\s]'), '')
            .trim();
        final words = cleaned
            .split(' ')
            .where((w) => w.isNotEmpty)
            .take(4)
            .join(' ');
        return words.isEmpty ? 'Diagram' : words;
      }
    }
    return 'Diagram';
  }
}
