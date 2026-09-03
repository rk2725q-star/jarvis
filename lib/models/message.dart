import 'package:hive/hive.dart';

part 'message.g.dart';

@HiveType(typeId: 0)
class Message extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String content;

  @HiveField(2)
  bool isUser;

  @HiveField(3)
  DateTime timestamp;

  @HiveField(4)
  String? provider;

  @HiveField(5)
  String? model;

  @HiveField(6)
  bool isStreaming;

  @HiveField(7)
  String sessionId;

  @HiveField(8)
  int? tokenCount;

  Message({
    required this.id,
    required this.content,
    required this.isUser,
    required this.timestamp,
    required this.sessionId,
    this.provider,
    this.model,
    this.isStreaming = false,
    this.tokenCount,
  });

  Message copyWith({
    String? content,
    bool? isStreaming,
    String? provider,
    String? model,
    int? tokenCount,
  }) {
    return Message(
      id: id,
      content: content ?? this.content,
      isUser: isUser,
      timestamp: timestamp,
      sessionId: sessionId,
      provider: provider ?? this.provider,
      model: model ?? this.model,
      isStreaming: isStreaming ?? this.isStreaming,
      tokenCount: tokenCount ?? this.tokenCount,
    );
  }

  // ── Equality ──
  // Without this, Dart uses identity comparison (`==` on Object). When the
  // chat list rebuilds after a notify, Flutter's element diff sees the new
  // MessageBubble as "different" from the old one and DESTROYS the entire
  // _AIBubble widget tree (including our throttle Timer) on every chunk.
  // With value-equality, the same content → same Message → same element →
  // the State (and Timer) survives, and the markdown throttle actually works.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Message) return false;
    return id == other.id &&
        content == other.content &&
        isUser == other.isUser &&
        timestamp == other.timestamp &&
        provider == other.provider &&
        model == other.model &&
        isStreaming == other.isStreaming &&
        sessionId == other.sessionId &&
        tokenCount == other.tokenCount;
  }

  @override
  int get hashCode => Object.hash(
        id,
        content,
        isUser,
        timestamp,
        provider,
        model,
        isStreaming,
        sessionId,
        tokenCount,
      );
}
