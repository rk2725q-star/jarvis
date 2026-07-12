class ToolCall {
  final String id;
  final String name;
  final Map<String, dynamic> arguments;

  ToolCall({required this.id, required this.name, required this.arguments});
}

class AIResponse {
  final String text;
  final ToolCall? toolCall;

  AIResponse({this.text = '', this.toolCall});

  bool get hasToolCall => toolCall != null;
}
