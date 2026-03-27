class GeneratedFile {
  final String name;
  final String path;
  String content;
  final String language;

  GeneratedFile({
    required this.name,
    required this.path,
    required this.content,
    required this.language,
  });

  factory GeneratedFile.fromJson(Map<String, dynamic> json) {
    return GeneratedFile(
      name: json['name'] ?? '',
      path: json['path'] ?? '',
      content: json['content'] ?? '',
      language: json['language'] ?? 'plaintext',
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'path': path,
    'content': content,
    'language': language,
  };
}
