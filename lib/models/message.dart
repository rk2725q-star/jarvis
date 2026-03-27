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
}
