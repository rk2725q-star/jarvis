import 'package:uuid/uuid.dart';

class Assignment {
  final String id;
  final String title;
  final String description;
  final DateTime dueDate;
  final bool isCompleted;
  final String? googleDocId;

  Assignment({
    String? id,
    required this.title,
    required this.description,
    required this.dueDate,
    this.isCompleted = false,
    this.googleDocId,
  }) : id = id ?? const Uuid().v4();

  Assignment copyWith({
    String? title,
    String? description,
    DateTime? dueDate,
    bool? isCompleted,
    String? googleDocId,
  }) {
    return Assignment(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      dueDate: dueDate ?? this.dueDate,
      isCompleted: isCompleted ?? this.isCompleted,
      googleDocId: googleDocId ?? this.googleDocId,
    );
  }
}
