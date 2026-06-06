class JarvisSkill {
  final String id;
  final String name;
  final String description;
  final String systemInstruction;
  final List<String> triggerKeywords;
  final DateTime createdAt;
  bool isActive;

  JarvisSkill({
    required this.id,
    required this.name,
    required this.description,
    required this.systemInstruction,
    required this.triggerKeywords,
    required this.createdAt,
    this.isActive = true,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'systemInstruction': systemInstruction,
        'triggerKeywords': triggerKeywords,
        'createdAt': createdAt.toIso8601String(),
        'isActive': isActive,
      };

  factory JarvisSkill.fromJson(Map<String, dynamic> json) => JarvisSkill(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String,
        systemInstruction: json['systemInstruction'] as String,
        triggerKeywords: List<String>.from(json['triggerKeywords'] as List),
        createdAt: DateTime.parse(json['createdAt'] as String),
        isActive: json['isActive'] as bool? ?? true,
      );
}
