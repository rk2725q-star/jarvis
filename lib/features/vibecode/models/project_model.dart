import 'generated_file.dart';

enum ProjectType { website, webapp, reactApp, flutterWeb, flutterAndroidApp, unknown }

enum DeploymentStatus { none, deploying, deployed, failed }

class ProjectModel {
  final String id;
  String name;
  String description;
  ProjectType type;
  List<GeneratedFile> files;
  String? githubRepo;
  String? vercelUrl;
  String? supabaseProjectId;
  DeploymentStatus deploymentStatus;
  DateTime createdAt;
  DateTime updatedAt;

  ProjectModel({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    required this.files,
    this.githubRepo,
    this.vercelUrl,
    this.supabaseProjectId,
    this.deploymentStatus = DeploymentStatus.none,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// Combines all HTML/CSS/JS files into a single preview HTML string
  String get combinedPreviewHtml {
    if (type == ProjectType.flutterAndroidApp) {
      return _buildMobileMockup();
    }

    final htmlFile = files.firstWhere(
      (f) => f.name.endsWith('.html'),
      orElse: () => GeneratedFile(
        name: 'index.html',
        path: 'index.html',
        content: '',
        language: 'html',
      ),
    );

    String cssContent = files
        .where((f) => f.name.endsWith('.css'))
        .map((f) => f.content)
        .join('\n');

    String jsContent = files
        .where((f) => f.name.endsWith('.js') && !f.name.contains('node_modules'))
        .map((f) => f.content)
        .join('\n');

    String html = htmlFile.content;

    // Inject CSS inline
    if (cssContent.isNotEmpty) {
      final styleTag = '<style>\n$cssContent\n</style>';
      if (html.contains('</head>')) {
        html = html.replaceFirst('</head>', '$styleTag\n</head>');
      } else {
        html = '$styleTag\n$html';
      }
    }

    // Inject JS inline
    if (jsContent.isNotEmpty) {
      final scriptTag = '<script>\n$jsContent\n</script>';
      if (html.contains('</body>')) {
        html = html.replaceFirst('</body>', '$scriptTag\n</body>');
      } else {
        html = '$html\n$scriptTag';
      }
    }

    return html;
  }

  String _buildMobileMockup() {
    final mainDart = files.firstWhere((f) => f.name == 'main.dart', orElse: () => files.first).content;
    
    return '''
    <!DOCTYPE html>
    <html>
    <head>
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <style>
        body { margin: 0; background: #0A0A0F; color: white; font-family: sans-serif; display: flex; align-items: center; justify-content: center; height: 100vh; overflow: hidden; }
        .phone { width: 320px; height: 640px; border: 8px solid #1E1E2E; border-radius: 32px; position: relative; overflow: hidden; background: #fff; box-shadow: 0 20px 50px rgba(0,0,0,0.5); }
        .top-bar { height: 100px; background: #7C3AED; color: white; display: flex; align-items: flex-end; padding: 16px; font-weight: bold; font-size: 20px; box-sizing: border-box; }
        .content { padding: 20px; color: #333; height: calc(100% - 100px); overflow-y: auto; }
        .status-bar { height: 24px; position: absolute; width: 100%; display: flex; justify-content: space-between; padding: 4px 20px; box-sizing: border-box; font-size: 10px; color: white; font-weight: bold; }
        .fab { width: 56px; height: 56px; border-radius: 50%; background: #7C3AED; position: absolute; bottom: 24px; right: 24px; box-shadow: 0 4px 10px rgba(0,0,0,0.3); display: flex; align-items: center; justify-content: center; color: white; font-size: 24px; }
        .code-label { font-size: 10px; color: #999; margin-top: 20px; display: block; }
        .code-peek { font-family: monospace; font-size: 8px; color: #777; background: #f5f5f5; padding: 8px; border-radius: 4px; border: 1px solid #eee; margin-top: 8px; white-space: pre-wrap; }
      </style>
    </head>
    <body>
      <div class="phone">
        <div class="status-bar">
          <span>9:41</span>
          <span>&#128246; &#128267;</span>
        </div>
        <div class="top-bar">$name</div>
        <div class="content">
          <h3>Android App Prototype</h3>
          <p>$description</p>
          <hr>
          <span class="code-label">FLUTTER (MAIN.DART) PEEK:</span>
          <div class="code-peek">${mainDart.length > 500 ? '${mainDart.substring(0, 500)}...' : mainDart}</div>
        </div>
        <div class="fab">+</div>
      </div>
    </body>
    </html>
    ''';
  }
}
