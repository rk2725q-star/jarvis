import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../../core/router/ai_router.dart';
import 'models/generated_file.dart';
import 'models/project_model.dart';

class ChatMessage {
  final String role; // 'user' | 'assistant'
  final String content;
  final DateTime timestamp;
  final bool isSystem;

  ChatMessage({
    required this.role,
    required this.content,
    DateTime? timestamp,
    this.isSystem = false,
  }) : timestamp = timestamp ?? DateTime.now();
}

enum BuildPhase {
  idle,
  ideation,
  planning,
  scaffolding,
  generation,
  healing,
  verification,
  integration,
  polish,
  complete,
  failed,
}

class BuildEvent {
  final BuildPhase phase;
  final String message;
  final double progress;
  final String? detail;

  BuildEvent({
    required this.phase,
    required this.message,
    required this.progress,
    this.detail,
  });
}

// ═══════════════════════════════════════════════════════════
// VIBECODE CONTROLLER — ANTIGRAVITY ARCHITECTURE v2
// ═══════════════════════════════════════════════════════════

class VibeCodeController extends ChangeNotifier {
  final AIRouter router;
  final _uuid = const Uuid();

  // ── State ──────────────────────────────────────────────
  ProjectModel? currentProject;
  List<ChatMessage> chatHistory = [];
  List<BuildEvent> buildLogs = [];

  bool isGenerating = false;
  bool isDeploying = false;

  BuildPhase currentPhase = BuildPhase.idle;
  double buildProgress = 0.0;
  String thinkingMessage = '';
  String errorMessage = '';
  String? projectPlan;
  String? selectedFilePath;

  AIProvider? preferredProvider;
  bool _showWorkspace = false;
  bool get showWorkspace => _showWorkspace;
  set showWorkspace(bool val) {
    _showWorkspace = val;
    notifyListeners();
  }

  // Integration credentials
  String? _githubToken;
  String? _vercelToken;
  String? _supabaseUrl;
  String? _supabaseAnonKey;

  // ── Getters ────────────────────────────────────────────
  GeneratedFile? get selectedFile {
    if (selectedFilePath == null || currentProject == null) return null;
    try {
      return currentProject!.files.firstWhere((f) => f.path == selectedFilePath);
    } catch (_) {
      return null;
    }
  }

  bool get hasProject => currentProject != null;
  bool get isGithubConnected => _githubToken?.isNotEmpty == true;
  bool get isVercelConnected => _vercelToken?.isNotEmpty == true;
  bool get isSupabaseConnected =>
      _supabaseUrl?.isNotEmpty == true && _supabaseAnonKey?.isNotEmpty == true;

  VibeCodeController({required this.router});

  // ═══════════════════════════════════════════════════════
  // CORE: ANTIGRAVITY GENERATION ENGINE
  // ═══════════════════════════════════════════════════════

  // ═══════════════════════════════════════════════════════
  // MODIFIED CHAT: PROJECT-AWARE ARCHITECT
  // ═══════════════════════════════════════════════════════

  /// Intelligently routes user messages to either build logic or discussion
  Future<void> processChat(String message) async {
    if (isGenerating) return;

    // Identify intent: BUILD | MODIFICATION | DISCUSSION | GREETING
    final intentPrompt = '''Analyze the user message.
Current state: ${hasProject ? "Current project built." : "No project active."}

Message: "$message"

Classify as:
1. "BUILD": User wants to create a NEW project from scratch (e.g., "Build an app", "Create a site").
2. "MODIFICATION": (Only if project exists) User wants to CHANGE code.
3. "DISCUSSION": User is asking a question about code, doubt, or explanation.
4. "GREETING": Just saying hi, asking how you are, or small talk.

Output ONLY the category word.''';

    try {
      final intent = (await _callAI(system: intentPrompt, user: message)).trim().toUpperCase();
      
      if (intent.contains('BUILD') || (!hasProject && !intent.contains('GREETING') && !intent.contains('DISCUSSION'))) {
        await generateProject(message);
      } else if (intent.contains('MODIFICATION') && hasProject) {
        await modifyProject(message);
      } else {
        // Discussion or Greeting fallback
        await architecturalChat(message);
      }
    } catch (_) {
      if (hasProject) {
        await modifyProject(message);
      } else {
        await generateProject(message);
      }
    }
  }

  /// General chat that is aware of the current project code and history
  Future<void> architecturalChat(String message) async {
    if (isGenerating) return;

    _addChat('user', message);
    isGenerating = true; 
    notifyListeners();

    try {
      final context = _getProjectContext();
      
      // Build a multi-turn history string for the prompt
      final history = chatHistory.length > 1 
          ? chatHistory.take(chatHistory.length - 1).map((m) => '${m.role.toUpperCase()}: ${m.content}').join('\n')
          : 'No previous history.';

      final systemPrompt = '''You are the JARVIS VibeCode Architect. 
You are a brilliant software engineer who built this current project.
Your goal is to assist the user with their codebase, explain patterns, or propose fixes.

CURRENT PROJECT CODEBASE:
$context

RECENT CONVERSATION HISTORY:
$history

RULES:
- Be technical and helpful.
- Reference specific filenames.
- Explain "how-to" rather than just providing snippets.
- Use a helpful, conversational tone.''';

      // Use the SHARED AIRouter with the EXACT same fallback logic as main Jarvis
      final response = await router.generateDirectResponse(
        prompt: message, 
        systemOverride: systemPrompt,
        providerOverride: preferredProvider,
      );

      _addChat('assistant', response);
    } catch (e) {
      _addChat('assistant', '❌ **Chat Error**: $e');
    } finally {
      isGenerating = false;
      notifyListeners();
    }
  }

  String _getProjectContext() {
    if (currentProject == null) return 'No project active yet.';
    final files = currentProject!.files.map((f) => '--- ${f.path} ---\n${f.content}').join('\n\n');
    return 'Project Title: ${currentProject!.name}\nType: ${currentProject!.type.name}\n\nFILES:\n$files';
  }

  /// STEP 1 — Full project generation with total logic completeness
  Future<void> generateProject(String userPrompt) async {
    isGenerating = true;
    errorMessage = '';
    buildLogs.clear();
    _addChat('user', userPrompt);
    notifyListeners();

    try {
      // ── PHASE 1: DEEP INTENT ANALYSIS ──────────────────
      _log(BuildPhase.ideation, '🧠 Analyzing intent and technology requirements...', 0.08);

      final intentSummary = await _callAI(
        system: '''You are a senior full-stack architect. Analyze the user's request.
A "Complete App" MUST include:
1. Dynamic logic (No static HTML templates).
2. Data state management (arrays, local storage, or API).
3. Complete UI with transitions.
4. Functional components (buttons that actually do things).

Output JSON only:
{
  "app_type": "...",
  "tech_stack": [...],
  "required_logic": ["navigation", "state management", "form handling", "real data simulation"],
  "suggested_files": ["index.html", "style.css", "app.js", "data_service.js"]
}''',
        user: userPrompt,
      );

      Map<String, dynamic> intent = {};
      try {
        intent = jsonDecode(_cleanJson(intentSummary));
      } catch (_) {
        intent = {
          'app_type': 'webapp',
          'tech_stack': ['html', 'css', 'js'],
          'suggested_files': ['index.html', 'style.css', 'app.js'],
          'ui_style': 'glassmorphism',
        };
      }

      // ── PHASE 2: ARCHITECTURE PLAN ─────────────────────
      _log(BuildPhase.planning, '📐 Designing file architecture and component structure...', 0.18);

      final plan = await _callAI(
        system: _plannerPrompt(),
        user: 'Build: $userPrompt\nTech: ${jsonEncode(intent)}',
      );
      projectPlan = plan;

      // ── PHASE 3: FILE-BY-FILE GENERATION ───────────────
      _log(BuildPhase.scaffolding, '🏗️ Scaffolding project structure...', 0.28);

      final suggestedFiles = (intent['suggested_files'] as List?)?.cast<String>() ??
          ['index.html', 'style.css', 'app.js'];

      final List<GeneratedFile> generatedFiles = [];

      for (int i = 0; i < suggestedFiles.length; i++) {
        final filePath = suggestedFiles[i];
        final progress = 0.30 + ((i / suggestedFiles.length) * 0.45);

        _log(
          BuildPhase.generation,
          '⚡ Generating $filePath... (${i + 1}/${suggestedFiles.length})',
          progress,
        );

        final fileContent = await _generateSingleFile(
          filePath: filePath,
          userPrompt: userPrompt,
          plan: plan,
          intent: intent,
          existingFiles: generatedFiles,
        );

        if (fileContent.trim().isNotEmpty) {
          generatedFiles.add(GeneratedFile(
            name: filePath.split('/').last,
            path: filePath,
            content: fileContent,
            language: _detectLanguage(filePath),
          ));
        }
      }

      // ── PHASE 4: SELF-HEALING VERIFICATION ─────────────
      _log(BuildPhase.healing, '🩺 Running self-healing diagnostics...', 0.78);
      final healedFiles = await _selfHealFiles(generatedFiles, userPrompt);

      // ── PHASE 5: INTEGRATION INJECTION ─────────────────
      _log(BuildPhase.integration, '🔌 Injecting active integrations...', 0.88);
      final integratedFiles = _injectActiveIntegrations(healedFiles);

      // ── PHASE 6: FINALIZE ───────────────────────────────
      _log(BuildPhase.polish, '✨ Applying final polish and verification...', 0.95);

      currentProject = ProjectModel(
        id: _uuid.v4(),
        name: _extractProjectName(userPrompt),
        description: userPrompt,
        files: integratedFiles,
        type: _detectProjectType(intent),
      );

      selectedFilePath = currentProject!.files.isNotEmpty
          ? currentProject!.files.first.path
          : null;
      _showWorkspace = true;

      _log(BuildPhase.complete, '✅ Genesis complete! ${integratedFiles.length} files generated.', 1.0);

      _addChat(
        'assistant',
        '✅ **Project Built Successfully!**\n\n'
        '**${currentProject!.name}** is ready with ${integratedFiles.length} files.\n\n'
        '${isSupabaseConnected ? "🟢 Supabase client injected\n" : ""}'
        '${isGithubConnected ? "🐙 Ready to push to GitHub\n" : ""}'
        '${isVercelConnected ? "▲ Ready to deploy to Vercel\n" : ""}'
        '\nSwitch to **WORKSPACE** tab to preview and edit!',
      );
    } catch (e, stack) {
      debugPrint('VibeCode Error: $e\n$stack');
      errorMessage = e.toString();
      _log(BuildPhase.failed, '❌ Build failed: $e', 1.0);
      _addChat('assistant',
          '❌ **Build Failed**\n\nError: $e\n\nTry rephrasing your request or switching providers in Settings.');
    } finally {
      isGenerating = false;
      notifyListeners();
    }
  }

  /// STEP 2 — Intelligent project modification
  Future<void> modifyProject(String userRequest) async {
    if (currentProject == null) {
      await generateProject(userRequest);
      return;
    }

    isGenerating = true;
    errorMessage = '';
    _addChat('user', userRequest);
    notifyListeners();

    try {
      _log(BuildPhase.ideation, '🔍 Analyzing modification scope...', 0.15);

      // Identify WHICH files need to change
      final impactAnalysis = await _callAI(
        system: '''Analyze existing files and user request. Return JSON ONLY:
{
  "files_to_modify": ["index.html"],
  "files_to_add": [],
  "files_to_delete": [],
  "modification_summary": "brief description"
}''',
        user:
            'Files: ${currentProject!.files.map((f) => f.path).join(", ")}\nRequest: $userRequest',
      );

      Map<String, dynamic> impact = {};
      try {
        impact = jsonDecode(_cleanJson(impactAnalysis));
      } catch (_) {
        impact = {
          'files_to_modify': currentProject!.files.map((f) => f.path).toList(),
          'files_to_add': <String>[],
          'files_to_delete': <String>[],
        };
      }

      final filesToModify = (impact['files_to_modify'] as List?)?.cast<String>() ?? [];
      final filesToAdd = (impact['files_to_add'] as List?)?.cast<String>() ?? [];
      final filesToDelete = (impact['files_to_delete'] as List?)?.cast<String>() ?? [];

      // Delete files
      for (final path in filesToDelete) {
        currentProject!.files.removeWhere((f) => f.path == path);
      }

      // Modify existing files
      for (int i = 0; i < filesToModify.length; i++) {
        final path = filesToModify[i];
        final progress = 0.25 + ((i / (filesToModify.length + filesToAdd.length)) * 0.55);
        _log(BuildPhase.generation, '🛠️ Modifying $path...', progress);

        final existingFile = currentProject!.files.firstWhere(
          (f) => f.path == path,
          orElse: () => GeneratedFile(name: path.split('/').last, path: path, content: '', language: _detectLanguage(path)),
        );

        final newContent = await _callAI(
          system: '''You are a code editor. Modify the given file according to the user request.
Return ONLY the complete new file content. No explanations, no markdown fences.
File: $path
Language: ${existingFile.language}''',
          user: 'Current content:\n${existingFile.content}\n\nModification request: $userRequest',
        );

        final idx = currentProject!.files.indexWhere((f) => f.path == path);
        if (idx != -1) {
          currentProject!.files[idx].content = _stripCodeFences(newContent);
        }
      }

      // Add new files
      for (int i = 0; i < filesToAdd.length; i++) {
        final path = filesToAdd[i];
        _log(BuildPhase.generation, '➕ Creating $path...', 0.7 + (i / filesToAdd.length * 0.15));

        final newContent = await _generateSingleFile(
          filePath: path,
          userPrompt: userRequest,
          plan: projectPlan ?? '',
          intent: {},
          existingFiles: currentProject!.files,
        );

        currentProject!.files.add(GeneratedFile(
          name: path.split('/').last,
          path: path,
          content: newContent,
          language: _detectLanguage(path),
        ));
      }

      _log(BuildPhase.complete, '✨ Modifications applied successfully!', 1.0);
      _addChat('assistant',
          '✨ **Updated!** ${impact['modification_summary'] ?? 'Changes applied successfully.'}');
    } catch (e) {
      errorMessage = e.toString();
      _log(BuildPhase.failed, '❌ Modification failed: $e', 1.0);
      _addChat('assistant', '❌ **Update Failed**\n\nError: $e');
    } finally {
      isGenerating = false;
      notifyListeners();
    }
  }

  // ═══════════════════════════════════════════════════════
  // CORE AI HELPERS
  // ═══════════════════════════════════════════════════════

  /// Generate a single file with retry logic
  Future<String> _generateSingleFile({
    required String filePath,
    required String userPrompt,
    required String plan,
    required Map<String, dynamic> intent,
    required List<GeneratedFile> existingFiles,
  }) async {
    final language = _detectLanguage(filePath);
    final existingContext = existingFiles.isNotEmpty
        ? 'Already generated files:\n${existingFiles.map((f) => "--- ${f.path} ---\n${f.content.substring(0, f.content.length.clamp(0, 500))}...").join("\n")}'
        : '';

    const maxRetries = 3;
    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        final content = await _callAI(
          system: _fileGenerationPrompt(filePath, language, plan, existingContext),
          user: 'App description: $userPrompt\nGenerate ONLY the complete $filePath file content.',
          providerOverride: preferredProvider,
        );

        final cleaned = _stripCodeFences(content);
        if (cleaned.trim().length > 50) return cleaned;

        throw Exception('Generated content too short (${cleaned.length} chars)');
      } catch (e) {
        if (attempt == maxRetries - 1) rethrow;
        await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
      }
    }
    return '';
  }

  /// True self-healing: detect issues and fix them
  Future<List<GeneratedFile>> _selfHealFiles(
    List<GeneratedFile> files,
    String userPrompt,
  ) async {
    final healedFiles = List<GeneratedFile>.from(files);

    for (int i = 0; i < healedFiles.length; i++) {
      final file = healedFiles[i];
      final issues = _detectCodeIssues(file);

      if (issues.isEmpty) continue;

      _log(BuildPhase.healing, '🩹 Fixing ${file.path}: ${issues.join(", ")}', 0.78 + (i / files.length * 0.08));

      try {
        final fixed = await _callAI(
          system: '''You are a code debugger. Fix the issues in the file.
Return ONLY the fixed file content. No explanations, no markdown.
Issues found: ${issues.join(", ")}''',
          user: 'File: ${file.path}\nContent:\n${file.content}',
        );

        healedFiles[i] = GeneratedFile(
          name: file.name,
          path: file.path,
          content: _stripCodeFences(fixed),
          language: file.language,
        );
      } catch (_) {
        // Keep original if healing fails
      }
    }

    return healedFiles;
  }

  List<String> _detectCodeIssues(GeneratedFile file) {
    final issues = <String>[];
    final content = file.content;

    if (content.trim().isEmpty) {
      issues.add('empty file');
      return issues;
    }

    if (file.language == 'html') {
      if (!content.contains('<!DOCTYPE') && !content.contains('<html')) {
        issues.add('missing HTML structure');
      }
      if (!content.contains('</body>') || !content.contains('</html>')) {
        issues.add('unclosed HTML tags');
      }
      // Check for placeholder text
      if (content.contains('Lorem ipsum') || content.contains('placeholder text')) {
        issues.add('contains placeholder text');
      }
    }

    if (file.language == 'css') {
      final openBraces = '{'.allMatches(content).length;
      final closeBraces = '}'.allMatches(content).length;
      if ((openBraces - closeBraces).abs() > 2) {
        issues.add('unbalanced CSS braces');
      }
    }

    if (file.language == 'javascript') {
      if (content.contains('// TODO') || content.contains('// FIXME')) {
        issues.add('contains TODO placeholders');
      }
    }

    return issues;
  }

  /// Inject active integrations into generated files
  List<GeneratedFile> _injectActiveIntegrations(List<GeneratedFile> files) {
    final result = List<GeneratedFile>.from(files);
    final htmlIdx = result.indexWhere(
        (f) => f.language == 'html' && (f.path.contains('index') || result.length == 1));

    if (htmlIdx == -1) return result;

    String html = result[htmlIdx].content;
    String injections = '';

    // Supabase injection
    if (isSupabaseConnected) {
      injections += '''
  <!-- Supabase Client (Auto-injected by Jarvis) -->
  <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
  <script>
    const SUPABASE_URL = '$_supabaseUrl';
    const SUPABASE_KEY = '$_supabaseAnonKey';
    const supabase = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY);
    window.db = supabase; // Global access
    console.log('[Jarvis] Supabase connected:', SUPABASE_URL);
  </script>''';
    }

    if (injections.isNotEmpty) {
      if (html.contains('</head>')) {
        html = html.replaceFirst('</head>', '$injections\n</head>');
      } else {
        html = '$injections\n$html';
      }
      result[htmlIdx] = GeneratedFile(
        name: result[htmlIdx].name,
        path: result[htmlIdx].path,
        content: html,
        language: 'html',
      );
    }

    return result;
  }

  Future<String> _callAI({
    required String system,
    required String user,
    AIProvider? providerOverride,
  }) async {
    return await router.generateDirectResponse(
      prompt: user,
      systemOverride: system,
      providerOverride: providerOverride ?? preferredProvider,
    );
  }

  // ═══════════════════════════════════════════════════════
  // PROMPT BUILDERS
  // ═══════════════════════════════════════════════════════

  String _plannerPrompt() {
    return '''You are a senior full-stack architect. Create a concise technical plan.

RULES:
- Output markdown plan only
- Be specific about what each file will contain
- Specify exact CSS variables, color palette, fonts
- For HTML: must be complete SPA with all features
- For CSS: specify glassmorphism styles, animations, responsive breakpoints
- For JS: specify all functions, event listeners, data structures

DESIGN SYSTEM:
- Colors: #7C3AED (primary), #0A0A0F (bg), white text
- Font: Inter or system-ui
- Style: Premium dark glassmorphism with subtle gradients''';
  }

  String _fileGenerationPrompt(
    String filePath,
    String language,
    String plan,
    String existingContext,
  ) {
    final rules = <String>[];

    if (language == 'html') {
      rules.addAll([
        'Generate a COMPLETE HTML5 document with ALL sections fully implemented',
        'Include inline styles for critical CSS if style.css is separate',
        'Every feature must be working, no TODO comments',
        'Navigation must be functional with smooth scroll',
        'Forms must have validation',
        'Include real, meaningful content (no Lorem Ipsum)',
      ]);
    } else if (language == 'css') {
      rules.addAll([
        'Generate COMPLETE CSS with ALL styles implemented',
        'Use CSS custom properties (variables) for theming',
        'Include responsive breakpoints for mobile, tablet, desktop',
        'Add smooth transitions and hover effects',
        'Glassmorphism: backdrop-filter, rgba backgrounds, subtle borders',
        'Include animations with @keyframes',
      ]);
    } else if (language == 'javascript') {
      rules.addAll([
        'Generate COMPLETE JavaScript with ALL functions implemented',
        'No placeholder functions — every function must have real logic',
        'Use modern ES6+ syntax',
        'Add proper error handling',
        'Initialize all components on DOMContentLoaded',
      ]);
    }

    return '''You are an expert $language developer. Generate production-ready code.

ARCHITECTURAL PLAN:
$plan

$existingContext

FILE TO GENERATE: $filePath

CRITICAL RULES (VIOLATION = FAILURE):
${rules.map((r) => '- $r').join('\n')}
- Return ONLY the raw $language code — NO markdown, NO backticks, NO explanations
- The output must be immediately usable without any editing
- Minimum 100 lines for HTML/CSS, minimum 50 lines for JS

PREMIUM DESIGN REQUIREMENTS:
- Background: #0A0A0F or similar deep dark
- Primary: #7C3AED (purple), #06B6D4 (cyan accents)  
- Glass cards: rgba(255,255,255,0.05) + backdrop-filter: blur(20px)
- Borders: 1px solid rgba(255,255,255,0.1)
- Shadows: 0 8px 32px rgba(0,0,0,0.4)''';
  }

  // ═══════════════════════════════════════════════════════
  // INTEGRATIONS
  // ═══════════════════════════════════════════════════════

  void connectSupabase({required String url, required String anonKey}) {
    _supabaseUrl = url;
    _supabaseAnonKey = anonKey;
    if (currentProject != null) {
      currentProject!.files = _injectActiveIntegrations(currentProject!.files);
    }
    _addChat('assistant',
        '🟢 **Supabase Connected!**\n`$url`\n\nAll future builds will auto-inject the Supabase client. Existing projects updated.');
    notifyListeners();
  }

  void connectGithub(String token) {
    _githubToken = token;
    _addChat('assistant', '🐙 **GitHub Connected!** Ready to push your projects.');
    notifyListeners();
  }

  void connectVercel(String token) {
    _vercelToken = token;
    _addChat('assistant', '▲ **Vercel Connected!** One-tap deployment enabled.');
    notifyListeners();
  }

  Future<Map<String, dynamic>> testSupabaseConnection() async {
    if (!isSupabaseConnected) return {'success': false, 'error': 'Not connected'};
    try {
      final res = await http.get(
        Uri.parse('$_supabaseUrl/rest/v1/'),
        headers: {
          'apikey': _supabaseAnonKey!,
          'Authorization': 'Bearer $_supabaseAnonKey',
        },
      );
      return {'success': res.statusCode < 400, 'status': res.statusCode};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> exportToGithub({
    required String repoName,
    required String description,
    bool isPrivate = false,
  }) async {
    if (!isGithubConnected || currentProject == null) {
      return {'success': false, 'error': 'GitHub not connected or no project'};
    }
    isDeploying = true;
    notifyListeners();

    try {
      // Create repo
      final createRes = await http.post(
        Uri.parse('https://api.github.com/user/repos'),
        headers: {
          'Authorization': 'Bearer $_githubToken',
          'Accept': 'application/vnd.github.v3+json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'name': repoName,
          'description': description,
          'private': isPrivate,
          'auto_init': false,
        }),
      );

      if (createRes.statusCode != 201) {
        throw Exception('Repo creation failed: ${createRes.body}');
      }

      final repoFullName = jsonDecode(createRes.body)['full_name'];

      // Push each file
      for (final file in currentProject!.files) {
        await http.put(
          Uri.parse('https://api.github.com/repos/$repoFullName/contents/${file.path}'),
          headers: {
            'Authorization': 'Bearer $_githubToken',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'message': '🚀 Initial commit via Jarvis VibeCode',
            'content': base64Encode(utf8.encode(file.content)),
          }),
        );
      }

      currentProject!.githubRepo = repoFullName;
      isDeploying = false;
      notifyListeners();

      _addChat('assistant',
          '🐙 **Pushed to GitHub!**\nhttps://github.com/$repoFullName');

      return {'success': true, 'url': 'https://github.com/$repoFullName'};
    } catch (e) {
      isDeploying = false;
      notifyListeners();
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> deployToVercel({required String projectName}) async {
    if (!isVercelConnected || currentProject == null) {
      return {'success': false, 'error': 'Vercel not connected or no project'};
    }
    isDeploying = true;
    notifyListeners();

    try {
      final files = currentProject!.files
          .map((f) => {
                'file': f.path,
                'data': base64Encode(utf8.encode(f.content)),
                'encoding': 'base64',
              })
          .toList();

      final res = await http.post(
        Uri.parse('https://api.vercel.com/v13/deployments'),
        headers: {
          'Authorization': 'Bearer $_vercelToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'name': projectName.replaceAll(RegExp(r'[^a-z0-9-]'), '-').toLowerCase(),
          'files': files,
          'projectSettings': {'framework': null},
        }),
      );

      if (res.statusCode != 200 && res.statusCode != 201) {
        throw Exception('Vercel API error ${res.statusCode}: ${res.body}');
      }

      final body = jsonDecode(res.body);
      final deployUrl = 'https://${body['url']}';

      currentProject!.vercelUrl = deployUrl;
      currentProject!.deploymentStatus = DeploymentStatus.deployed;
      isDeploying = false;
      notifyListeners();

      _addChat('assistant', '▲ **Deployed to Vercel!**\n$deployUrl');

      return {'success': true, 'url': deployUrl};
    } catch (e) {
      currentProject?.deploymentStatus = DeploymentStatus.failed;
      isDeploying = false;
      notifyListeners();
      return {'success': false, 'error': e.toString()};
    }
  }

  // ═══════════════════════════════════════════════════════
  // FILE MANAGEMENT
  // ═══════════════════════════════════════════════════════

  void selectFile(String path) {
    selectedFilePath = path;
    notifyListeners();
  }

  void updateFileContent(String path, String newContent) {
    final idx = currentProject?.files.indexWhere((f) => f.path == path) ?? -1;
    if (idx != -1) {
      currentProject!.files[idx].content = newContent;
      notifyListeners();
    }
  }

  void addFile(GeneratedFile f) {
    currentProject?.files.add(f);
    notifyListeners();
  }

  void deleteFile(String path) {
    currentProject?.files.removeWhere((f) => f.path == path);
    if (selectedFilePath == path) {
      selectedFilePath = currentProject?.files.isNotEmpty == true
          ? currentProject!.files.first.path
          : null;
    }
    notifyListeners();
  }

  void resetProject() {
    currentProject = null;
    chatHistory = [];
    selectedFilePath = null;
    projectPlan = null;
    buildLogs = [];
    _showWorkspace = false;
    notifyListeners();
  }

  void setProvider(AIProvider? provider) {
    preferredProvider = provider;
    notifyListeners();
  }

  void setShowWorkspace(bool val) {
    _showWorkspace = val;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════
  // UTILITIES
  // ═══════════════════════════════════════════════════════

  void _log(BuildPhase phase, String message, double progress) {
    currentPhase = phase;
    buildProgress = progress;
    thinkingMessage = message;
    buildLogs.add(BuildEvent(phase: phase, message: message, progress: progress));
    notifyListeners();
  }

  void _addChat(String role, String content) {
    chatHistory.add(ChatMessage(role: role, content: content));
    notifyListeners();
  }

  String _cleanJson(String raw) {
    // Remove markdown code fences
    String cleaned = raw.trim();
    if (cleaned.startsWith('```')) {
      cleaned = cleaned.replaceFirst(RegExp(r'^```[a-z]*\n?'), '');
      cleaned = cleaned.replaceFirst(RegExp(r'\n?```$'), '');
    }
    // Find outermost JSON object
    final firstBrace = cleaned.indexOf('{');
    final lastBrace = cleaned.lastIndexOf('}');
    if (firstBrace != -1 && lastBrace > firstBrace) {
      return cleaned.substring(firstBrace, lastBrace + 1);
    }
    return cleaned.trim();
  }

  String _stripCodeFences(String content) {
    String cleaned = content.trim();
    // Remove ```html, ```css, ```js, ```javascript, ```dart etc.
    if (cleaned.startsWith('```')) {
      cleaned = cleaned.replaceFirst(RegExp(r'^```[a-zA-Z]*\n?'), '');
      cleaned = cleaned.replaceFirst(RegExp(r'\n?```\s*$'), '');
    }
    return cleaned.trim();
  }

  String _detectLanguage(String filePath) {
    if (filePath.endsWith('.html')) return 'html';
    if (filePath.endsWith('.css')) return 'css';
    if (filePath.endsWith('.js')) return 'javascript';
    if (filePath.endsWith('.dart')) return 'dart';
    if (filePath.endsWith('.json')) return 'json';
    if (filePath.endsWith('.md')) return 'markdown';
    if (filePath.endsWith('.ts')) return 'typescript';
    if (filePath.endsWith('.tsx') || filePath.endsWith('.jsx')) return 'jsx';
    if (filePath.endsWith('.py')) return 'python';
    return 'text';
  }

  ProjectType _detectProjectType(Map<String, dynamic> intent) {
    final type = intent['app_type']?.toString().toLowerCase() ?? '';
    if (type.contains('flutter') || type.contains('android')) {
      return ProjectType.flutterAndroidApp;
    }
    return ProjectType.website;
  }

  String _extractProjectName(String prompt) {
    // Try to extract a meaningful name from the prompt
    final words = prompt.split(' ');
    if (words.length <= 3) return prompt;

    // Look for "build a X" or "create a X" patterns
    for (final pattern in ['build a ', 'create a ', 'make a ', 'generate a ']) {
      final idx = prompt.toLowerCase().indexOf(pattern);
      if (idx != -1) {
        final after = prompt.substring(idx + pattern.length);
        final nameWords = after.split(' ').take(3).toList();
        return nameWords
            .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
            .join(' ');
      }
    }

    return words.take(4).map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase()).join(' ');
  }

  // Support legacy widgets
  bool get isThinking => isGenerating;
}
