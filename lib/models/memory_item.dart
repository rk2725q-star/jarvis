import 'package:hive/hive.dart';

part 'memory_item.g.dart';

@HiveType(typeId: 2)
class MemoryItem extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String content;

  @HiveField(2)
  DateTime createdAt;

  @HiveField(3)
  double importance;

  @HiveField(4)
  String category;

  MemoryItem({
    required this.id,
    required this.content,
    required this.createdAt,
    required this.importance,
    required this.category,
  });
}
