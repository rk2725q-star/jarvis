import 'package:hive/hive.dart';

part 'session.g.dart';

@HiveType(typeId: 1)
class Session extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String title;

  @HiveField(2)
  DateTime createdAt;

  @HiveField(3)
  DateTime updatedAt;

  @HiveField(4)
  String? lastMessage;

  Session({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.lastMessage,
  });

  Session copyWith({
    String? title,
    DateTime? updatedAt,
    String? lastMessage,
  }) {
    return Session(
      id: id,
      title: title ?? this.title,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastMessage: lastMessage ?? this.lastMessage,
    );
  }
}
