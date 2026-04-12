import 'dart:io';

void main() {
  final files = [
    'lib/features/files/parsers/docx_parser.dart',
    'lib/features/files/parsers/pptx_parser.dart',
    'lib/features/files/parsers/xlsx_parser.dart',
  ];

  for (final path in files) {
    final file = File(path);
    if (file.existsSync()) {
      var content = file.readAsStringSync();
      // Add dart:convert if not imported
      if (!content.contains("import 'dart:convert';")) {
        content = "import 'dart:convert';\n$content";
      }
      // Replace String.fromCharCodes(something as List<int>) with utf8.decode(something as List<int>)
      // Sometimes it is file.content or relFile.content
      content = content.replaceAll('String.fromCharCodes', 'utf8.decode');
      file.writeAsStringSync(content);
    }
  }
}
