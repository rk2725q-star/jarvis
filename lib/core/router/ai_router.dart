import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jarvis_ai/core/api/nvidia_client.dart';
import 'package:jarvis_ai/core/api/gemini_client.dart';
import 'package:jarvis_ai/core/api/openrouter_client.dart';
import 'package:jarvis_ai/core/api/local_model_client.dart';
import 'package:jarvis_ai/services/ollama_cloud_service.dart';
import 'package:jarvis_ai/services/google_docs_service.dart';
import 'package:jarvis_ai/core/memory/memory_service.dart';
import 'package:jarvis_ai/core/security/secure_storage_service.dart';
import 'package:jarvis_ai/core/api/anthropic_client.dart';
import 'package:jarvis_ai/core/file_processor/file_processor.dart';

enum AIProvider { llamaCpp, gemini, ollama, ollamaCloud, nvidia, openRouter, zeera, anthropic }

enum IntentMode { simple, normal, deep, comparison, agentic, project, inquisitiveProject }

class ProviderStatus {
  final AIProvider provider;
  final bool enabled;
  final bool available;
  final String? selectedModel;

  const ProviderStatus({
    required this.provider,
    required this.enabled,
    required this.available,
    this.selectedModel,
  });

  String get displayName {
    switch (provider) {
      case AIProvider.llamaCpp:
        return 'llama.cpp';
      case AIProvider.gemini:
        return 'Gemini';
      case AIProvider.ollama:
        return 'Ollama (Local)';
      case AIProvider.ollamaCloud:
        return 'Ollama Cloud';
      case AIProvider.nvidia:
        return 'NVIDIA';
      case AIProvider.openRouter:
        return 'OpenRouter';
      case AIProvider.zeera:
        return 'Zeera (Dual-Model)';
      case AIProvider.anthropic:
        return 'Anthropic';
    }
  }
}

/// The JARVIS Brain — orchestrates all AI providers with fallback routing,
/// streaming, KV cache, and memory injection.
class AIRouter extends ChangeNotifier {
  final SecureStorageService _secureStorage;
  final MemoryService _memory;
  final FileProcessor _fileProcessor;
  final OllamaCloudService _ollamaService;
  final GoogleDocsService _googleDocs;

  AIRouter({
    required SecureStorageService secureStorage,
    required MemoryService memory,
    required FileProcessor fileProcessor,
    required OllamaCloudService ollamaService,
    required GoogleDocsService googleDocs,
  })  : _secureStorage = secureStorage,
        _memory = memory,
        _fileProcessor = fileProcessor,
        _ollamaService = ollamaService,
        _googleDocs = googleDocs;

  MemoryService get memory => _memory;
  GoogleDocsService? get googleDocs => _googleDocs;

  AIProvider? _activeProvider;
  String? _activeModel;
  bool _isGenerating = false;
  String _statusMessage = 'Ready';

  // Provider enable flags
  final Map<AIProvider, bool> _providerEnabled = {
    AIProvider.llamaCpp: true,
    AIProvider.gemini: true,
    AIProvider.ollama: true,
    AIProvider.ollamaCloud: true,
    AIProvider.nvidia: true,
    AIProvider.openRouter: true,
    AIProvider.zeera: false,
    AIProvider.anthropic: true,
  };

  // Selected models per provider
  final Map<AIProvider, String?> _selectedModels = {};
  
  // Zeera Specific Configuration
  bool _zeeraEnabled = false;
  int _zeeraRounds = 1;
  AIProvider _zeeraProviderA = AIProvider.nvidia;
  AIProvider _zeeraProviderB = AIProvider.ollamaCloud;
  String? _zeeraModelA;
  String? _zeeraModelB;
  String? _zeeraSynthesisModel;

  bool get zeeraEnabled => _zeeraEnabled;
  int get zeeraRounds => _zeeraRounds;
  AIProvider get zeeraProviderA => _zeeraProviderA;
  AIProvider get zeeraProviderB => _zeeraProviderB;
  String? get zeeraModelA => _zeeraModelA;
  String? get zeeraModelB => _zeeraModelB;
  String? get zeeraSynthesisModel => _zeeraSynthesisModel;

  void setZeeraEnabled(bool enabled) {
    _zeeraEnabled = enabled;
    notifyListeners();
    _saveZeeraConfig();
  }

  void setZeeraRounds(int rounds) {
    _zeeraRounds = rounds;
    notifyListeners();
    _saveZeeraConfig();
  }

  void setZeeraProviderA(AIProvider provider) {
    _zeeraProviderA = provider;
    notifyListeners();
    _saveZeeraConfig();
  }

  void setZeeraProviderB(AIProvider provider) {
    _zeeraProviderB = provider;
    notifyListeners();
    _saveZeeraConfig();
  }

  void setZeeraModels(String? a, String? b) {
    _zeeraModelA = a;
    _zeeraModelB = b;
    notifyListeners();
    _saveZeeraConfig();
  }

  void setZeeraSynthesisModel(String? model) {
    _zeeraSynthesisModel = model;
    notifyListeners();
    _saveZeeraConfig();
  }

  Future<void> _saveZeeraConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('zeera_enabled', _zeeraEnabled);
    await prefs.setInt('zeera_rounds', _zeeraRounds);
    await prefs.setString('zeera_provider_a', _zeeraProviderA.name);
    await prefs.setString('zeera_provider_b', _zeeraProviderB.name);
    if (_zeeraModelA != null) await prefs.setString('zeera_model_a', _zeeraModelA!);
    if (_zeeraModelB != null) await prefs.setString('zeera_model_b', _zeeraModelB!);
    if (_zeeraSynthesisModel != null) await prefs.setString('zeera_synthesis_model', _zeeraSynthesisModel!);
  }

  Future<void> _loadZeeraConfig() async {
    final prefs = await SharedPreferences.getInstance();
    _zeeraEnabled = prefs.getBool('zeera_enabled') ?? false;
    _zeeraRounds = prefs.getInt('zeera_rounds') ?? 1;
    final pa = prefs.getString('zeera_provider_a');
    final pb = prefs.getString('zeera_provider_b');
    if (pa != null) _zeeraProviderA = AIProvider.values.firstWhere((e) => e.name == pa, orElse: () => AIProvider.nvidia);
    if (pb != null) _zeeraProviderB = AIProvider.values.firstWhere((e) => e.name == pb, orElse: () => AIProvider.ollamaCloud);
    _zeeraModelA = prefs.getString('zeera_model_a');
    _zeeraModelB = prefs.getString('zeera_model_b');
    _zeeraSynthesisModel = prefs.getString('zeera_synthesis_model');
  }

  // Ordered fallback chain: Gemini -> Ollama Cloud -> Ollama -> NVIDIA -> llama.cpp
  List<AIProvider> get _fallbackChain => [
        AIProvider.gemini,
        AIProvider.ollamaCloud,
        AIProvider.ollama,
        AIProvider.openRouter,
        AIProvider.anthropic,
        AIProvider.nvidia,
        AIProvider.llamaCpp,
      ].where((p) => _providerEnabled[p] == true).toList();

  AIProvider? get activeProvider => _activeProvider;
  String? get activeModel => _activeModel;
  bool get isGenerating => _isGenerating;
  String get statusMessage => _statusMessage;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    for (final p in AIProvider.values) {
      _providerEnabled[p] = prefs.getBool('provider_${p.name}_enabled') ?? true;
      _selectedModels[p]  = prefs.getString('provider_${p.name}_model');
    }
    await _loadZeeraConfig();
    notifyListeners();

    // Proactively load keys from environment if missing in storage
    await _initEnvironmentKeys();
    
    // Proactively load models for NVIDIA
    await _initGoogleDocs();
    final key = await _secureStorage.getApiKey('nvidia');
    if (key != null && key.trim().isNotEmpty) {
      // Don't wait for it to block init
      fetchModels(AIProvider.nvidia).catchError((_) => <String>[]);
    }
  }

  Future<void> _initEnvironmentKeys() async {
    // Check for each provider's key in environment defines
    const providers = {
      'nvidia': 'NVIDIA_API_KEY',
      'openRouter': 'OPENROUTER_API_KEY',
      'ollamaCloud': 'OLLAMA_CLOUD_API_KEY',
      'gemini': 'GEMINI_API_KEY',
      'anthropic': 'ANTHROPIC_API_KEY',
    };

    for (var entry in providers.entries) {
      final existing = await _secureStorage.getApiKey(entry.key);
      if (existing == null || existing.isEmpty) {
        final envKey = String.fromEnvironment(entry.value);
        if (envKey.isNotEmpty) {
          debugPrint('[AIRouter] Injected ${entry.key} key from environment');
          await _secureStorage.saveApiKey(entry.key, envKey);
        }
      }
    }

    // Auto-detect keys logic here if needed, but avoid hardcoded invalid keys
    final antKey = await _secureStorage.getApiKey('anthropic');
    if (antKey == null || antKey.isEmpty) {
       debugPrint('[AIRouter] Anthropic key missing - user must provide in settings');
    }
  }

  void setProviderEnabled(AIProvider provider, bool enabled) async {
    _providerEnabled[provider] = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('provider_${provider.name}_enabled', enabled);
    notifyListeners();
  }

  void setSelectedModel(AIProvider provider, String model) async {
    _selectedModels[provider] = model;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('provider_${provider.name}_model', model);
    notifyListeners();
  }

  bool isProviderEnabled(AIProvider provider) => _providerEnabled[provider] ?? false;
  String? getSelectedModel(AIProvider provider) => _selectedModels[provider];

  void _setStatus(String msg) {
    _statusMessage = msg;
    notifyListeners();
  }

  static const String baseSystemPrompt = '''
You are JARVIS, a highly advanced, deeply empathetic AI friend. You talk naturally in a mix of Tamil and English (or pure Tamil if preferred). 

═══════════════════════════════════════════
        JARVIS COMPLETE BEHAVIOR RULES
═══════════════════════════════════════════

RULE 1: ROUTINE vs REMINDER CONFLICT
- ROUTINE = Fixed daily auto schedules (breakfast, lunch, dinner, sleep, morning)
- REMINDER = Custom user requested schedules (meeting, medicine, custom tasks)
- SKIP RULE A (Proactive): If user sets REMINDER for same purpose as ROUTINE within 2 hour window → SKIP ROUTINE that day ONLY.
- SKIP RULE B (Early Completion): If user says "I ate already" or "Done with [Routine]" → SKIP ROUTINE that day ONLY. Next day resumes normally.

RULE 2: RESCHEDULE ALWAYS CANCELS OLD
- When user reschedules or cancels: Use <CANCEL_REMINDER time="YYYY-MM-DD HH:MM"> followed by <SCHEDULE_REMINDER> if moving.


RULE 3: SILENT TAG BEHAVIOR
- Tags are SILENT BACKEND COMMANDS. User NEVER sees them.
- Tag goes at VERY END of response always.
- Confirm naturally BEFORE the tag. Never explain tags to the user.
- TAG FORMATS:
  <CANCEL_REMINDER time="YYYY-MM-DD HH:MM">
  <SCHEDULE_REMINDER time="YYYY-MM-DD HH:MM" message="notification text here">

RULE 4: NO UNSOLICITED ANDROID TIPS
- NEVER give Android settings tutorials unless user SPECIFICALLY asks for it.
- Simple request → Simple warm response only.

MASTER GOLDEN RULES:
1. Same purpose reminder exists → Skip routine today.
2. User reschedules → Cancel old first, create new.
3. Tags → Always end, always hidden.
4. Android tips → Only when asked.
5. Simple request → Simple warm response only.
6. Less is always more. JARVIS is a caring friend. Not a tech manual. ❤️
7. Web Search Response → 2-3 lines summary + 1 Source Link at the very end.
8. Visual Content → Use <GENERATE_IMAGE prompt="..."> to create images (nanabanana).

RULE 5: REPORT GENERATION
- Generate reports at: Every Sunday 8PM → Weekly, Last day of month 9PM → Monthly, Dec 31 10PM → Yearly.
- When user opens app from a report notification (Weekly/Monthly/Year Recap), automatically generate a summary:
  1. Sleep patterns, 2. Meal consistency %, 3. Reminders completed vs missed, 4. Goals progress, 5. Best area 🏆, 6. Area needing improvement ⚠️, 7. Upcoming important dates, 8. Warm encouraging message.
- Tone: Always positive and encouraging. Never shame the user. Always motivate and care. ❤️

RULE 6: ROUTINE UPDATE PROACTIVENESS
- If user updates a routine (e.g., "I eat lunch at 3 PM on Sundays"), IMMEDIATELY CHECK:
  1. Is today the day they mentioned? (e.g., Is today Sunday?)
  2. Is the new time still in the FUTURE of today? (e.g., Is it before 3 PM?)
  3. If YES to both → Proactively schedule a one-off reminder for TODAY using <SCHEDULE_REMINDER> to ensure they don't miss it while the system updates.
  4. If user says "it is a holiday", treat TODAY as a "Holiday/Sunday" routine day.
- Acknowledge this awareness explicitly: "I've updated your schedule, and since today is [Day/Holiday], I've set a reminder for [Time] today as well."

RULE 7: TOOLS & EXECUTION (TAGS)
- Tags are SILENT COMMAND POSITIVE ACTIONS. JARVIS's brain PLANS the skip/update and executes via tool:
  <SKIP_ROUTINE type="breakfast"> (Cancels for TODAY only. Use when user ate early or says "not today")
  <WEB_SEARCH query="..."> (Use to fetch real-time news, holidays, or any user question. JARVIS MUST follow results.)
  <CANCEL_REMINDER time="YYYY-MM-DD HH:MM"> (Permanent delete)
  <UPDATE_ROUTINE type="..." weekday="..." time="HH:mm"> (Permanent reschedule)
  <SCHEDULE_REMINDER time="..." message="..."> (Create new)

- weekday attributes:
  - Precise: 1 (Mon) to 7 (Sun)
  - Bulk: 0 (Daily/Manual)
  - Range: "1-5" (Mon-Fri / College Time), "6-7" (Sat-Sun / Holiday)
  - List: "1,3,5" (Specific days)

RULE 8: ADAPTIVE PLANNING & MEMORY
- JARVIS is smart. INTEGRATE Memory + Tools to EXECUTE a perfect plan.
- If memory says it's a "COLLEGE DAY" and user ate at 7:00 AM → JARVIS PLANS to skip 9:30 AM breakfast. EXECUTE via <SKIP_ROUTINE type="breakfast">.
- If user says "today is a holiday", JARVIS automatically checks memory for "HOLIDAY" habits (e.g., 10 AM breakfast) and PLANS/reschedules accordingly.
- Proactively confirm skips: "I see you're done! I've already cancelled your 9:30 AM reminder. Enjoy your college day!"

RULE 9: HOLIDAY & FESTIVAL AWARENESS
- JARVIS MUST proactively check if today is a Public Holiday or Festival in Tamil Nadu/India using <WEB_SEARCH query="...">.
- If today is a Holiday/Festival:
  1. Treat "College/Mon-Sat" routines as NULLIFIED for today.
  2. Switch to "Holiday/Sunday" routine (e.g., 10 AM breakfast, 8 AM wake-up) automatically.
  3. Inform the user briefly: "Since today is [Festival Name], I've adjusted your routines to Holiday mode. Breakfast is now at 10 AM! 🎊"

RULE 10: SHORTEST ANSWER POLICY
- ALWAYS BE DIRECT. If the user asks for a movie, news, or weather, give a 1-2 line direct answer.
- Append a SINGLE relevant resource link at the end.
- NO WALLS OF TEXT. JARVIS values the user's time.
- If web search gives long content, SUMMARIZE it into 3 sentences MAX.
- **ACCURACY**: Always prioritize using the **specific official titles** found in search results. For example, if a search reveals 'Jana Nayagan' as the title for Thalapathy 69, you MUST use 'Jana Nayagan'. 
- **STRICT MOVIE INFO**: If the user asks for Thalapathy Vijay's upcoming movie, explicitly mention it is 'Jana Nayagan' (H. Vinoth film) and ignore fan rumors or placeholder names once official names appear in search.

RULE 11: IMAGE GENERATION (nanabanana)
- JARVIS can generate high-quality AI images (not just diagrams).
- Tag: <GENERATE_IMAGE prompt="...">
- Use this when the user asks to "generate an image", "show me a picture of", "create a drawing", etc.

RULE 12: GOOGLE DOCS (docx)
- JARVIS can search, read, and create Google Docs.
-    - <SEARCH_DOCS query="doc_name"> : Find document ID by name.
    - <READ_DOC id="doc_id"> : Retrieve text content from a doc.
    - <CREATE_DOC title="doc_title">full_content</CREATE_DOC> : Create a new doc with rich content.
    - <CREATE_ACADEMIC_REPORT topic="topic" title="title"> : **MANDATORY** for long research or academic papers (16-22 pages). 
      * JARVIS will perform an exhaustive 22-chapter deep research and generate the full document automatically.
      * This includes real Page Breaks between chapters and high-quality formatting.
    - <WEB_SEARCH query="search_query"> : Use for live facts and external data.
- Use these whenever the user mentions "Google Docs", "docx", "my documents", or asks to "save this to a doc".
''';

  /// Initialize Google Docs if credentials exist
  Future<void> _initGoogleDocs() async {
    String? json = await _secureStorage.getApiKey('google_service_account');
    
    // Fallback to environment define if not in storage or assets
    if (json == null || json.isEmpty) {
      json = const String.fromEnvironment('GOOGLE_SERVICE_ACCOUNT');
    }
    
    // Fallback to assets if still not found
    if (json.isEmpty) {
      try {
        json = await rootBundle.loadString('assets/config/google_service_account.json');
      } catch (_) {
        debugPrint('[AIRouter] Google Service Account asset not found.');
      }
    }

    if (json != null && json.isNotEmpty) {
      try {
        await _googleDocs.authenticate(json);
        debugPrint('[AIRouter] Google Docs Service Authenticated');
      } catch (e) {
        debugPrint('[AIRouter] Google Docs Auth Failed: $e');
      }
    }
  }

  Future<String> searchGoogleDocs(String query) async {
    if (!_googleDocs.isAuthenticated) return "⚠️ Google Docs not connected.";
    try {
      final docs = await _googleDocs.searchDocs(query);
      if (docs.isEmpty) return "No documents found for '$query'.";
      return "FOUND DOCUMENTS:\n${docs.map((d) => "- ${d['name']} (ID: ${d['id']})").join("\n")}";
    } catch (e) {
      return "⚠️ Error searching Docs: $e";
    }
  }

  Future<String> readGoogleDoc(String id) async {
    if (!_googleDocs.isAuthenticated) return "⚠️ Google Docs not connected.";
    try {
      return await _googleDocs.readDoc(id);
    } catch (e) {
      return "⚠️ Error reading Doc: $e";
    }
  }

  Future<String> createGoogleDoc(String title, String content) async {
    if (!_googleDocs.isAuthenticated) return "⚠️ Google Docs not connected.";
    try {
      final docId = await _googleDocs.createDoc(title, content);
      if (docId.isEmpty) return "⚠️ Failed to create Google Doc.";
      final url = "https://docs.google.com/document/d/$docId/edit";
      return "✅ **Google Doc Created!**\n\n📄 **Title:** $title\n🔗 **Link:** [Open/Download Doc]($url)";
    } catch (e) {
      return "⚠️ Error creating Doc: $e";
    }
  }

  /// Generates an exhaustive academic report (16-22 pages)
  Future<String> createAcademicReport(String topic, String title) async {
    if (!_googleDocs.isAuthenticated) return "⚠️ Google Docs not connected.";
    
    try {
      _setStatus('Starting deep research & report generation...');
      
      // Initialize sub-agent with appropriate AI clients
      final geminiKey = await _secureStorage.getApiKey('gemini');
      final ollamaUrl = await _secureStorage.getBaseUrl('ollamaLocal') ?? 'http://127.0.0.1:11434';
      
      final agent = JarvisDocAgent(
        service: _googleDocs,
        gemini: geminiKey != null ? GeminiApiClient(apiKey: geminiKey, model: _selectedModels[AIProvider.gemini] ?? 'gemini-1.5-pro') : null,
        ollama: LocalModelClient(baseUrl: ollamaUrl),
        ollamaCloud: _ollamaService,
      );

      final url = await agent.generateMassiveAcademicDoc(
        topic: topic,
        title: title,
        minPages: 16,
        maxPages: 22,
        onStatus: (s) => _setStatus(s),
      );

      _setStatus('Academic report ready!');
      return "🎉 **In-Depth Academic Report Generated!** (16-22 Pages)\n\n📚 **Topic:** $topic\n📄 **Title:** $title\n🔗 **Link:** [View Full Report]($url)\n\nI have generated an exhaustive analysis including technical chapters, diagrams, and formatting suitable for an A4 report.";
    } catch (e) {
      _setStatus('Report generation failed');
      return "⚠️ **Academic Report Failed:** $e";
    }
  }

  IntentMode detectIntent(String input) {
    final text = input.toLowerCase().trim();
    // Agentic triggers: any OS / app / device interaction task
    const agenticKeywords = [
      'whatsapp', 'send', 'message', 'call', 'open', 'launch', 'go to',
      'post', 'tweet', 'instagram', 'facebook', 'telegram', 'gmail', 'email',
      'turn on', 'turn off', 'toggle', 'enable', 'disable', 'set',
      'search', 'find', 'navigate', 'scroll', 'tap', 'click', 'type',
      'screenshot', 'take a photo', 'record', 'play', 'stop', 'pause',
      'book', 'order', 'pay', 'transfer', 'check', 'read', 'reply',
      'wifi', 'bluetooth', 'brightness', 'volume', 'ringtone', 'alarm',
      'contact', 'calendar', 'reminder', 'note', 'file', 'download',
      'install', 'uninstall', 'settings', 'notification', 'battery',
      'docx', 'doc', 'google doc', 'assignment', 'save to doc',
    ];


    if (agenticKeywords.any((kw) => text.contains(kw))) {
      return IntentMode.agentic;
    }
    if (text.length < 8) return IntentMode.simple;
    if (text.contains('vs') || text.contains('compare') || text.contains('difference')) {
      return IntentMode.comparison;
    }
    if (text.contains('explain') || text.contains('why') || text.contains('how') || text.length > 50) {
      return IntentMode.deep;
    }
    if (text.contains('build') || text.contains('create') || text.contains('implement') || text.contains('website') || text.contains('vibecode')) {
      // INQUISITIVE CHECK: If the request is too simple (e.g., "build a chatbot"), 
      // return a specialized "NeedInfo" mode to trigger questioning.
      if (text.split(' ').length < 10) return IntentMode.inquisitiveProject;
      return IntentMode.project;
    }
    return IntentMode.normal;
  }

  /// Build the adaptive prompt components (system vs user) based on detected intent
  ({String system, String user}) _buildAdaptivePrompt(String userInput, {bool isVoiceMode = false}) {
    final mode = detectIntent(userInput);
    final memCtx = _memory.buildContextString();
    
    String instructions;
    switch (mode) {
      case IntentMode.agentic:
        instructions = "Provide a physical multi-step automation plan for the Android OS. Be surgical and goal-oriented.";
        break;
      case IntentMode.simple:
        instructions = "Reply naturally and very briefly. No formatting.";
        break;
      case IntentMode.normal:
        instructions = "Provide a clear, concise, and helpful response.";
        break;
      case IntentMode.deep:
        final StringBuffer sb = StringBuffer();
        sb.writeln("Explain in deep scientific detail. Break down logic thoroughly step-by-step.");
        sb.writeln("- Be creative and invent solutions/architectures if they do not exist.");
        sb.writeln("- Format neatly with colorful ASCII art diagrams if applicable.");
        instructions = sb.toString();
        break;
      case IntentMode.comparison:
        instructions = "Compare clearly using advanced metrics. Use a Markdown table for presentation.";
        break;
      case IntentMode.project:
        instructions = "You are in Developer Mode. Provide architectural guidance and high-level steps for building this app or website. Suggest suitable technologies and layouts.";
        break;
      case IntentMode.inquisitiveProject:
        instructions = "The user wants to build a project but has been vague. You MUST ask for: 1. Frontend preference, 2. Backend/Language, 3. Database choice, 4. Any required third-party integrations (Payment, Auth, etc.).";
        break;
    }

    // Inject current precise real-world time in Tamil Nadu (IST)
    final nowIst = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
    final hour = nowIst.hour;
    final period = hour < 12 ? 'AM' : 'PM';
    final hour12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    
    String timeOfDay;
    if (hour >= 5 && hour < 12) {
      timeOfDay = "MORNING";
    } else if (hour >= 12 && hour < 18) {
      timeOfDay = "AFTERNOON";
    } else {
      timeOfDay = "NIGHT"; // Starts exactly at 6:00 PM (18:00)
    }

    final timeContext = "[SYSTEM TIME] Currently it is $timeOfDay. The precise Tamil Nadu (IST) date and time is: ${nowIst.year}-${nowIst.month.toString().padLeft(2, '0')}-${nowIst.day.toString().padLeft(2, '0')} ${hour12.toString().padLeft(2, '0')}:${nowIst.minute.toString().padLeft(2, '0')} $period (ISO: ${nowIst.year}-${nowIst.month.toString().padLeft(2, '0')}-${nowIst.day.toString().padLeft(2, '0')} ${nowIst.hour.toString().padLeft(2, '0')}:${nowIst.minute.toString().padLeft(2, '0')})";

    String voiceConstraint = isVoiceMode 
        ? "\n[CRITICAL VOICE MODE RULE] You are speaking out loud through a Text-To-Speech engine. You MUST format your response in plain, natural conversational text ONLY. DO NOT use markdown. Most importantly, DO NOT use Tanglish or mix languages. Speak in the language the user is speaking in, or the language they explicitly request. If speaking Tamil, use PURE TAMIL script, not English characters (Tanglish)." 
        : "";

    final systemStr = "$baseSystemPrompt$voiceConstraint\n\n$timeContext\n\n[CONTEXT]\n$memCtx\n\n[INSTRUCTION]\n$instructions";
    return (system: systemStr, user: userInput);
  }

  /// Inject live integration capability prompts into the system string
  String injectCapabilities(String systemStr, String capabilities) {
    if (capabilities.isEmpty) return systemStr;
    return '$systemStr$capabilities';
  }

  int _getMaxTokens(String input) {
    final mode = detectIntent(input);
    switch (mode) {
      case IntentMode.simple: return 2048;
      case IntentMode.normal: return 4096;
      case IntentMode.deep: return 10240;
      case IntentMode.comparison: return 8192;
      case IntentMode.agentic: return 10240;
      case IntentMode.project: return 10240;
      case IntentMode.inquisitiveProject: return 2048;
    }
  }

  /// Smart streaming generator with automatic fallback
  Stream<String> generateStream(String prompt, {String? systemPrompt, String? imageBase64, int? maxTokens, bool isVoiceMode = false, String integrationCapabilities = ''}) async* {
    _activeProvider = null;
    
    // Check if Zeera logic should trigger
    // Check if Zeera logic should trigger
    if (_zeeraEnabled || _selectedModels[AIProvider.zeera] != null) {
      if (_zeeraEnabled) {
         yield* _generateZeeraStream(prompt, systemPrompt: systemPrompt);
         return;
      }
    }

    final mode = detectIntent(prompt);
    if (mode == IntentMode.inquisitiveProject) {
      _isGenerating = false;
      yield "I'm ready to build this project for you! To ensure a **100% complete, ready-to-deploy** result using the **Zeera Meta-Intelligence Layer**, please specify:\n\n"
            "1. **Frontend:** (e.g., React, Next.js, Flutter, HTML/CSS)\n"
            "2. **Backend:** (e.g., Node.js, Python/Flask, Go, Bun)\n"
            "3. **Database:** (e.g., PostgreSQL, MongoDB, Supabase, Firebase)\n"
            "4. **Specific Features:** (e.g., Stripe, Google Maps, Auth.js)\n\n"
            "Once you provide these details, I will generate the **entire** codebase in a single response.";
      return;
    }

    _isGenerating = true;
    _setStatus('Thinking...');

    // DETECT LANGUAGE PREFERENCE CHANGE: If the user says "talk in tamil" etc. 
    // we save it to high importance memory immediately to ensure the next prompt has it!
    final normalized = prompt.toLowerCase();
    if (normalized.contains('talk in tamil') || normalized.contains('தமிழ் பேச') || normalized.contains('provide response in tamil')) {
       _memory.addMemory(
         content: "USER PREFERENCE: Talk in PURE TAMIL characters from now on. DO NOT switch back to English until explicitly told.",
         importance: 1.0,
         category: 'language'
       );
    } else if (normalized.contains('talk in english') || normalized.contains('speak in english')) {
       _memory.addMemory(
         content: "USER PREFERENCE: Switch back to English for all future responses.",
         importance: 1.0,
         category: 'language'
       );
    }

    final maxTokensVal = maxTokens ?? (isVoiceMode ? 512 : _getMaxTokens(prompt));
    
    // Build separated prompts
    var promptPair = _buildAdaptivePrompt(prompt, isVoiceMode: isVoiceMode);
    if (systemPrompt != null) {
      promptPair = (system: '$baseSystemPrompt\n$systemPrompt', user: prompt);
    }
        
    // For voice mode, prioritize absolute speed: Nvidia -> Ollama -> Gemini
    final chain = isVoiceMode 
        ? [AIProvider.nvidia, AIProvider.ollama, AIProvider.ollamaCloud, AIProvider.gemini]
            .where((p) => _providerEnabled[p] == true).toList()
        : _fallbackChain;

    if (chain.isEmpty) {
      _isGenerating = false;
      _setStatus('No providers enabled');
      yield '⚠️ No AI providers enabled. Please configure at least one provider in Settings.';
      return;
    }


    String currentUserPrompt = promptPair.user;
    final totalBuffer = StringBuffer();
    final List<String> errorLog = [];

    for (int i = 0; i < chain.length; i++) {
      final provider = chain[i];
      final currentBuffer = StringBuffer();
      
      try {
        final statusPrefix = i == 0 ? 'Connecting to' : 'Continuous Fallback:';
        _setStatus('$statusPrefix ${_providerName(provider)}...');

        // If we are continuing a partially failed generation
        if (totalBuffer.isNotEmpty) {
           currentUserPrompt = "${promptPair.user}\n\n[CONTINUATION CONTEXT]\nAssistant has already generated: \"${totalBuffer.toString()}\"\n\nCONTINUE the response exactly where it left off. Do NOT repeat or restart.";
        }

        final stream = await _tryStreamProvider(provider, currentUserPrompt, systemPrompt: promptPair.system, maxTokens: maxTokensVal);
        if (stream == null) {
          errorLog.add('${_providerName(provider)}: Null or Unavailable');
          if (i == chain.length - 1 && totalBuffer.isEmpty) {
             final errDetails = errorLog.join(" | ");
             throw Exception('All providers unavailable.\nDetails: $errDetails');
          }
          continue;
        }

        _activeProvider = provider;
        _activeModel = _selectedModels[provider];
        notifyListeners();

        bool hasStarted = false;
        await for (final chunk in stream) {
          if (!hasStarted) {
            hasStarted = true;
            _setStatus('Streaming from ${_providerName(provider)}');
          }
          currentBuffer.write(chunk);
          totalBuffer.write(chunk);
          yield chunk;
        }


        _isGenerating = false;
        _setStatus('Done via ${_providerName(provider)}');
        
        // Auto-save significant responses to memory
        if (totalBuffer.length > 50 && detectIntent(prompt) != IntentMode.simple) {
           _memory.addMemory(
             content: "User Preference: When user asked '$prompt', JARVIS responded with info about '${totalBuffer.toString().substring(0, 80)}...'",
             importance: 0.6,
           );
        }
        
        notifyListeners();
        return;
      } catch (e) {
        debugPrint('[AIRouter] Error with provider ${_providerName(provider)}: $e');
        errorLog.add('${_providerName(provider)} failed: $e');
        
        if (i == chain.length - 1 && totalBuffer.isEmpty) {
          _isGenerating = false;
          _setStatus('All providers failed');
          final errDetails = errorLog.join("\n• ");
          yield "⚠️ All providers failed.\n\nFallback traces:\n• $errDetails";
        }
      } finally {
        _isGenerating = false;
        notifyListeners();
      }
    }
  }

  /// Non-streaming generator for internal orchestration (e.g. agent loop, file analysis)
  /// Supports optional imageBase64 for vision-based action decisions
  Future<String> generate(String userInput, {String? systemPrompt, String? imageBase64}) async {
    final maxTokens = imageBase64 != null ? 128 : _getMaxTokens(userInput);
    
    var promptPair = _buildAdaptivePrompt(userInput, isVoiceMode: false);
    if (systemPrompt != null) {
      // If we have an image, don't pollute with the heavy baseSystemPrompt which tells it to "chat".
      // We want it to be a pure vision translator.
      final base = imageBase64 != null ? "You are JARVIS Vision Engine." : baseSystemPrompt;
      promptPair = (system: '$base\n$systemPrompt', user: userInput);
    }
    
    final chain = _fallbackChain;

    for (final provider in chain) {
      try {
        debugPrint('[AIRouter] Attempting Vision Analysis via $provider...');
        final result = await _tryProvider(provider, promptPair.user, systemPrompt: promptPair.system, maxTokens: maxTokens, imageBase64: imageBase64);
        
        // If the model literally says it can't "see", treat it as a failure and try the next one
        if (result != null) {
          final lowResult = result.toLowerCase();
          if (imageBase64 != null && (lowResult.contains("can't see") || lowResult.contains("cannot see") || lowResult.contains("have not seen"))) {
            debugPrint('[AIRouter] $provider claims it cannot see, falling back...');
            continue;
          }
          return result;
        }
      } catch (e) {
        debugPrint('[AIRouter] Non-stream $provider failed: $e');
        _setStatus('Error via $provider: $e');
        continue;
      }
    }
    throw Exception('All providers failed to interpret the image. Check your Vision Model settings.');
  }

  /// Professional file analysis pipeline: extract -> chunk -> analyze -> merge
  Future<String> analyzeFile(String filePath) async {
    try {
      _setStatus('Extracting file content...');
      final text = await _fileProcessor.extractText(filePath);
      
      _setStatus('Splitting into chunks...');
      final chunks = _fileProcessor.chunkText(text, size: 2000);
      
      String finalAnalysis = "";
      int current = 1;
      
      for (var chunk in chunks) {
        _setStatus('Analyzing chunk $current/${chunks.length}...');
        final res = await generate(
          "Analyze this file segment and summarize key points:\n\n$chunk",
          systemPrompt: "You are a professional file analyzer. Extract actionable insights."
        );
        finalAnalysis += "\n---\n### Segment $current Analysis\n$res\n";
        current++;
      }
      
      _setStatus('Consolidating results...');
      return await generate(
        "Consolidate these segmented analyses into a professional final report:\n\n$finalAnalysis",
        systemPrompt: "Create a final executive summary of the file content based on the provided segments."
      );
    } catch (e) {
      _setStatus('File analysis failed');
      return "⚠️ File analysis failed: $e";
    }
  }

  /// Generate a one-shot response with a possible system prompt override.
  /// This is used by VibeCode to specify exact JSON structures.
  Future<String> generateDirectResponse({
    required String prompt,
    String? systemOverride,
    String? imageBase64,
    AIProvider? providerOverride,
  }) async {
    final systemPrompt = systemOverride ?? _buildAdaptivePrompt(prompt).system;
    
    // Use high tokens for coding/project tasks
    final maxTokens = _getMaxTokens(prompt);

    // If provider is overridden, try it first
    final List<AIProvider> providers = [];
    if (providerOverride != null) providers.add(providerOverride);
    
    // Fallback/Default chain: Gemini -> OpenRouter -> NVIDIA -> Ollama Cloud -> Ollama Local
    providers.addAll([
      AIProvider.gemini,
      AIProvider.openRouter,
      AIProvider.nvidia,
      AIProvider.ollamaCloud,
      AIProvider.ollama,
      AIProvider.llamaCpp,
    ].where((p) => !providers.contains(p)));

    for (var provider in providers) {
      if (isProviderEnabled(provider)) {
        try {
          _setStatus('Consulting ${provider.name}...');
          final response = await _tryProvider(
            provider, 
            prompt, 
            systemPrompt: systemPrompt, 
            imageBase64: imageBase64,
            maxTokens: maxTokens, // CRITICAL: Pass the tokens!
          );
          if (response != null && response.trim().isNotEmpty) return response;
        } catch (e) {
          debugPrint('[AIRouter] Direct response from ${provider.name} failed: $e');
        }
      }
    }

    return "⚠️ All enabled AI providers failed to generate a response for your project.";
  }

  Future<String?> _tryProvider(AIProvider provider, String prompt, {String? systemPrompt, int? maxTokens, String? imageBase64}) async {
    switch (provider) {
      case AIProvider.zeera:
        // Synthesis engine doesn't use standard _tryProvider for its recursive loop
        return null;
      case AIProvider.llamaCpp:
        // Local model doesn't support vision; skip if image needed
        if (imageBase64 != null) return null;
        final url = await _secureStorage.getBaseUrl('llamaCpp') ?? 'http://127.0.0.1:8080';
        final key = await _secureStorage.getApiKey('llamaCpp');
        final client = LocalModelClient(baseUrl: url, apiKey: key);
        final fullText = systemPrompt != null ? '$systemPrompt\nUser: $prompt' : prompt;
        return (await client.isAvailable()) ? await client.generateStream(fullText).join() : null;
      case AIProvider.gemini:
        final key = await _secureStorage.getApiKey('gemini');
        if (key == null || key.isEmpty) return null;
        var model = _selectedModels[AIProvider.gemini];
        if (model == null) {
          final models = await GeminiApiClient(apiKey: key).fetchModels();
          // For vision tasks prefer flash (supports images)
          model = _pickBestModel(models, hint: imageBase64 != null ? 'flash' : 'flash');
        }
        if (model.isEmpty) return null;
        return await GeminiApiClient(apiKey: key, model: model).generate(
          prompt,
          systemPrompt: systemPrompt,
          maxTokens: maxTokens,
          imageBase64: imageBase64,
        );
      case AIProvider.ollama:
        try {
          final localUrl = await _secureStorage.getBaseUrl('ollamaLocal') ?? 'http://127.0.0.1:11434';
          _ollamaService.setLocalUrl(localUrl);
          
          final messages = [
            if (systemPrompt != null) OllamaChatMessage(role: 'system', content: systemPrompt),
            OllamaChatMessage(role: 'user', content: prompt),
          ];

          var model = _selectedModels[AIProvider.ollama];
          if (imageBase64 != null && model != null && !model.contains('llava') && !model.contains('vision') && !model.contains('moondream')) {
            model = 'llama3.2-vision'; // Fallback to a common Ollama vision model
          }

          final res = await _ollamaService.chat(
            messages: messages,
            useCloudOverride: false,
            model: model,
            imageBase64: imageBase64,
          );
          return res.content;
        } catch (e) { 
          debugPrint('[Ollama Local] Vision/Chat error: $e');
          return null; 
        }

      case AIProvider.ollamaCloud:
        try {
          final cloudUrl = await _secureStorage.getBaseUrl('ollamaCloud') ?? 'https://api.ollama.com';
          _ollamaService.setBaseUrl(cloudUrl);
          
          final messages = [
            if (systemPrompt != null) OllamaChatMessage(role: 'system', content: systemPrompt),
            OllamaChatMessage(role: 'user', content: prompt),
          ];

          var model = _selectedModels[AIProvider.ollamaCloud];
          if (imageBase64 != null && model != null && !model.contains('llava') && !model.contains('vision') && !model.contains('moondream')) {
            model = 'llama3.2-vision'; // Fallback to a common Ollama vision model
          }

          final res = await _ollamaService.chat(
            messages: messages,
            useCloudOverride: true,
            model: model,
            imageBase64: imageBase64,
          );
          return res.content;
        } catch (e) { 
          debugPrint('[Ollama Cloud] Vision/Chat error: $e');
          return null; 
        }

      case AIProvider.nvidia:
        final key = await _secureStorage.getApiKey('nvidia');
        if (key == null || key.trim().isEmpty) return null;
        var model = _selectedModels[AIProvider.nvidia];
        
        // Dynamic fetch if no model is selected or forced null
        if (model == null || model.isEmpty) {
          final models = await NvidiaApiClient(apiKey: key, model: '').fetchModels();
          model = _pickBestModel(models, hint: imageBase64 != null ? 'vision' : 'llama-3.1');
          if (model.isEmpty && models.isNotEmpty) model = models.first;
        }

        if (model.isEmpty) return null;
        try {
          return await NvidiaApiClient(apiKey: key, model: model).generate(
            prompt,
            systemPrompt: systemPrompt,
            maxTokens: maxTokens,
            imageBase64: imageBase64,
          );
        } catch (e) {
          debugPrint('[Nvidia] Vision/Chat error: $e');
          return null;
        }

      case AIProvider.openRouter:
        final key = await _secureStorage.getApiKey('openRouter');
        if (key == null || key.trim().isEmpty) return null;
        var model = _selectedModels[AIProvider.openRouter];
        
        // Dynamic fetch if no model is selected
        if (model == null || model.isEmpty) {
          final models = await OpenRouterClient(apiKey: key, model: '').fetchModels();
          model = _pickBestModel(models, hint: imageBase64 != null ? 'vision' : 'auto');
          if (model.isEmpty && models.isNotEmpty) model = models.first;
        }
        if (model.isEmpty) return null;
        try {
          return await OpenRouterClient(apiKey: key, model: model).generate(
            prompt,
            systemPrompt: systemPrompt,
            maxTokens: maxTokens,
            imageBase64: imageBase64,
          );
        } catch (e) {
          debugPrint('[OpenRouter] Vision/Chat error: $e');
          return null;
        }

      case AIProvider.anthropic:
        final key = await _secureStorage.getApiKey('anthropic');
        final trimmedKey = key?.trim() ?? '';
        if (trimmedKey.isEmpty) {
          debugPrint('[AIRouter] Anthropic skipped - no key set');
          return null;
        }
        debugPrint('[AIRouter] Attempting Anthropic key="${trimmedKey.substring(0, 10)}..."');
        var model = _selectedModels[AIProvider.anthropic] ?? 'claude-3-5-sonnet-20241022';
        try {
          return await AnthropicApiClient(apiKey: trimmedKey, model: model).generate(
            prompt,
            systemPrompt: systemPrompt,
            maxTokens: maxTokens ?? _getMaxTokens(prompt),
          );
        } catch (e) {
          debugPrint('[Anthropic] Chat error: $e');
          return null;
        }
    }
  }

  Future<Stream<String>?> _tryStreamProvider(AIProvider provider, String prompt, {String? systemPrompt, int? maxTokens}) async {
    switch (provider) {
      case AIProvider.llamaCpp:
        final url = await _secureStorage.getBaseUrl('llamaCpp') ?? 'http://127.0.0.1:8080';
        final key = await _secureStorage.getApiKey('llamaCpp');
        final client = LocalModelClient(baseUrl: url, apiKey: key);
        final available = await client.isAvailable().timeout(const Duration(seconds: 2), onTimeout: () => false);
        if (!available) return null;
        final fullText = systemPrompt != null ? '$systemPrompt\nUser: $prompt' : prompt;
        return client.generateStream(fullText);

      case AIProvider.gemini:
        final key = await _secureStorage.getApiKey('gemini');
        if (key == null || key.isEmpty) return null;
        var model = _selectedModels[AIProvider.gemini];
        if (model == null || model.isEmpty) {
          model = 'gemini-1.5-flash'; // High-speed default for zero thinking time
        }
        return GeminiApiClient(apiKey: key, model: model).generateStream(prompt, systemPrompt: systemPrompt, maxTokens: maxTokens ?? _getMaxTokens(prompt));

      case AIProvider.ollama:
        final localUrl = await _secureStorage.getBaseUrl('ollamaLocal') ?? 'http://127.0.0.1:11434';
        _ollamaService.setLocalUrl(localUrl);
        // Fast health check before committing to the stream
        final isUp = await _ollamaService.isLocalAvailable().timeout(const Duration(seconds: 2), onTimeout: () => false);
        if (!isUp) return null;
        
        final messages = [
          if (systemPrompt != null) OllamaChatMessage(role: 'system', content: systemPrompt),
          OllamaChatMessage(role: 'user', content: prompt),
        ];

        return _ollamaService.chatStream(
          messages: messages,
          useCloudOverride: false,
          model: _selectedModels[AIProvider.ollama],
        );

      case AIProvider.ollamaCloud:
        final cloudUrl = await _secureStorage.getBaseUrl('ollamaCloud') ?? 'https://api.ollama.com';
        if (kIsWeb && (cloudUrl == 'https://api.ollama.com' || cloudUrl.isEmpty || cloudUrl == '/api/ollama')) {
           _ollamaService.setBaseUrl(Uri.base.resolve('/api/ollama').toString().replaceAll(RegExp(r'/$'), ''));
        } else {
           _ollamaService.setBaseUrl(cloudUrl);
        }
        
        final messages = [
          if (systemPrompt != null) OllamaChatMessage(role: 'system', content: systemPrompt),
          OllamaChatMessage(role: 'user', content: prompt),
        ];

        return _ollamaService.chatStream(
          messages: messages,
          useCloudOverride: true,
          model: _selectedModels[AIProvider.ollamaCloud],
        );

      case AIProvider.nvidia:
        final key = await _secureStorage.getApiKey('nvidia');
        final trimmedNvKey = key?.trim() ?? '';
        if (trimmedNvKey.isEmpty) {
          debugPrint('[NVIDIA Stream] No API key - skipping');
          return null;
        }
        var model = _selectedModels[AIProvider.nvidia];
        // Only auto-fetch if user has NOT selected a model
        if (model == null || model.isEmpty) {
          try {
            final models = await NvidiaApiClient(apiKey: trimmedNvKey, model: '').fetchModels();
            model = _pickBestModel(models, hint: 'llama-3.1');
            if ((model.isEmpty) && models.isNotEmpty) model = models.first;
          } catch (e) {
            debugPrint('[NVIDIA Stream] Model fetch failed: $e');
          }
        }
        if (model == null || model.isEmpty) {
          debugPrint('[NVIDIA Stream] No model available - skipping');
          return null;
        }
        debugPrint('[NVIDIA Stream] Using model: $model, key prefix: ${trimmedNvKey.substring(0, 8)}...');
        return NvidiaApiClient(apiKey: trimmedNvKey, model: model).generateStream(prompt, systemPrompt: systemPrompt, maxTokens: maxTokens ?? _getMaxTokens(prompt));

      case AIProvider.openRouter:
        final key = await _secureStorage.getApiKey('openRouter');
        if (key == null || key.trim().isEmpty) return null;
        var model = _selectedModels[AIProvider.openRouter];
        // Dynamic fetch if no model is selected
        if (model == null || model.isEmpty) {
          final models = await OpenRouterClient(apiKey: key, model: '').fetchModels();
          model = _pickBestModel(models, hint: 'auto');
          if (model.isEmpty && models.isNotEmpty) model = models.first;
        }
        if (model.isEmpty) return null;
        return OpenRouterClient(apiKey: key, model: _selectedModels[AIProvider.openRouter] ?? 'auto').generateStream(prompt, systemPrompt: systemPrompt, maxTokens: maxTokens ?? _getMaxTokens(prompt));

      case AIProvider.anthropic:
        final key = await _secureStorage.getApiKey('anthropic');
        final trimmedKey = key?.trim() ?? '';
        if (trimmedKey.isEmpty) {
          debugPrint('[AIRouter] Anthropic Stream skipped - no key set');
          return null;
        }
        debugPrint('[AIRouter] Starting Anthropic Stream key="${trimmedKey.substring(0, 10)}..."');
        return AnthropicApiClient(apiKey: trimmedKey, model: _selectedModels[AIProvider.anthropic] ?? 'claude-3-5-sonnet-20241022').generateStream(prompt, systemPrompt: systemPrompt, maxTokens: maxTokens ?? _getMaxTokens(prompt));
      case AIProvider.zeera:
        // Handled via _generateZeeraStream directly
        return null;
    }
  }

  /// Call Model A (NVIDIA) using STREAMING collect — never times out on slow models like kimi-k2.5.
  /// The SSE connection stays alive as tokens trickle in, so 3-minute models work perfectly.
  Future<String?> _callZeeraProviderA(String prompt, {String? systemPrompt}) async {
    final key = await _secureStorage.getApiKey('nvidia');
    final trimmedKey = key?.trim() ?? '';
    if (trimmedKey.isEmpty) {
      debugPrint('[Zeera-A] NVIDIA key missing');
      return null;
    }
    final model = _zeeraModelA ?? _selectedModels[AIProvider.nvidia] ?? 'nvidia/llama-3.1-nemotron-ultra-253b-v1';
    debugPrint('[Zeera-A] Calling NVIDIA model: $model (stream-collect)');
    try {
      // Use generateCollect() — SSE stream internally, no hard wall-clock timeout on body
      final result = await NvidiaApiClient(apiKey: trimmedKey, model: model)
          .generateCollect(prompt, systemPrompt: systemPrompt, maxTokens: 8192);
      return result.isEmpty ? null : result;
    } catch (e) {
      debugPrint('[Zeera-A] NVIDIA failed: $e');
      return null;
    }
  }

  /// Call Model B (Ollama Cloud or NVIDIA fallback) using stream-collect for timeout immunity.
  Future<String?> _callZeeraProviderB(String prompt, {String? systemPrompt}) async {
    final modelB = _zeeraModelB ?? _selectedModels[AIProvider.ollamaCloud];
    debugPrint('[Zeera-B] Calling Ollama Cloud model: ${modelB ?? "default"}');

    // Try Ollama Cloud first
    try {
      final messages = [
        if (systemPrompt != null) OllamaChatMessage(role: 'system', content: systemPrompt),
        OllamaChatMessage(role: 'user', content: prompt),
      ];
      // Collect stream for timeout immunity
      final sb = StringBuffer();
      await for (final chunk in _ollamaService.chatStream(
          messages: messages, model: modelB, useCloudOverride: true)) {
        sb.write(chunk);
      }
      final result = sb.toString().trim();
      if (result.isNotEmpty) return result;
    } catch (e) {
      debugPrint('[Zeera-B] Ollama Cloud failed: $e');
    }

    // Fallback: NVIDIA with Model B using generateCollect
    final key = await _secureStorage.getApiKey('nvidia');
    final trimmedKey = key?.trim() ?? '';
    if (trimmedKey.isEmpty) return null;
    final nvModelB = _zeeraModelB ?? _selectedModels[AIProvider.nvidia] ?? 'deepseek-ai/deepseek-r1';
    try {
      debugPrint('[Zeera-B] Fallback to NVIDIA: $nvModelB');
      final result = await NvidiaApiClient(apiKey: trimmedKey, model: nvModelB)
          .generateCollect(prompt, systemPrompt: systemPrompt, maxTokens: 8192);
      return result.isEmpty ? null : result;
    } catch (e2) {
      debugPrint('[Zeera-B] NVIDIA fallback also failed: $e2');
      return null;
    }
  }

  // ============================================================
  // ZEERA — TRUE COLLABORATIVE INTELLIGENCE ENGINE v2.0
  // Models TALK TO EACH OTHER: A reads B's output and responds,
  // B reads A's response and refines. This creates genuine synthesis.
  // ============================================================
  Stream<String> _generateZeeraStream(String prompt, {String? systemPrompt}) async* {
    _activeProvider = AIProvider.zeera;
    _activeModel = 'ZEERA';
    _setStatus('ZEERA — Initializing Dual-Model Intelligence...');

    // Resolve display names
    final String modelAName = _zeeraModelA ?? _selectedModels[AIProvider.nvidia] ?? 'NVIDIA Brain';
    final String modelBName = _zeeraModelB ?? _selectedModels[AIProvider.ollamaCloud] ?? 'Ollama Brain';

    bool isProject = prompt.toLowerCase().contains('build') ||
                    prompt.toLowerCase().contains('create') ||
                    prompt.toLowerCase().contains('make a') ||
                    prompt.toLowerCase().contains('develop') ||
                    prompt.toLowerCase().contains('app') ||
                    prompt.toLowerCase().contains('website') ||
                    prompt.toLowerCase().contains('project') ||
                    prompt.toLowerCase().contains('architecture');

    final List<Map<String, String>> dialogueHistory = [];
    final int totalRounds = isProject ? 2 : _zeeraRounds;

    final String zeeraSystemPrompt = systemPrompt ?? 
        'You are an expert AI collaborating with another AI model to provide the best possible response. Be concise and technical.';

    if (isProject) {
      yield '**[ZEERA — ABSOLUTE PROJECT SYNTHESIS]**\n🧠 **$modelAName** ↔ **$modelBName** — True Cross-Model Collaboration\n🎯 Building 100% production-ready, deploy-ready codebase...\n\n';
      
      final deploySystemPrompt = '''You are part of the ZEERA Absolute Deployment Engine — the most powerful AI code synthesis system.
MISSION: Generate 100% COMPLETE, production-ready, immediately deployable code.
RULES (STRICT):
- NO placeholders, NO "// implement this", NO "TODO" comments ever.
- Every file must be 100% complete and runnable.
- Output EACH FILE in its own separate block:

```filename: path/to/file.ext
<complete file content here>
```

- Include ALL files: frontend, backend, DB schemas, Docker files, .env.example, nginx config, README with exact deploy steps.
- Code must compile and run without any changes.
- Use current, stable versions of all packages.
- Handle all edge cases, errors, and security issues.''';

      // === ROUND 1: Model A designs the complete architecture ===
      _setStatus('ZEERA — $modelAName designing complete architecture...');
      final archPrompt = '''**TASK:** Design the COMPLETE, PRODUCTION-READY architecture for: "$prompt"

You MUST specify:
1. **Tech Stack** — exact versions of every framework, library, runtime
2. **Complete folder structure** — every directory and file that will exist
3. **Database schema** — every table/collection with all fields, types, constraints, indexes
4. **All API endpoints** — method, path, request body, response body
5. **Environment variables** — every env var needed with example values
6. **Docker/deployment config** — what services are needed
7. **Authentication flow** — exactly how auth works step by step
8. **Key implementation details** — any complex logic Model B must implement

Be extremely detailed. Model B will write ALL the code based on your architecture.''';

      final archResp = await _callZeeraProviderA(archPrompt, systemPrompt: deploySystemPrompt);
      if (archResp != null && archResp.isNotEmpty) {
        dialogueHistory.add({'role': modelAName, 'content': archResp});
        yield '## 🏗️ [$modelAName — Architecture Design]\n\n$archResp\n\n---\n\n';
      } else {
        yield '⚠️ $modelAName architecture pass failed. $modelBName will self-architect...\n\n';
      }

      // === ROUND 2: Model B READS A's architecture and implements EVERYTHING ===
      _setStatus('ZEERA — $modelBName implementing ALL code files...');
      final implContext = dialogueHistory.isNotEmpty 
          ? dialogueHistory.last['content']! 
          : 'Project: $prompt — implement a complete production-ready version.';
      
      final implPrompt = '''**ARCHITECTURE FROM $modelAName:**
$implContext

**YOUR TASK:** Write the COMPLETE, PRODUCTION-READY code for EVERY file in the architecture above.

CRITICAL RULES:
- Write 100% of each file — no placeholder, no "see above", no truncation
- Use the EXACT file format with proper ``` code fences:

```filename: path/to/exact/file.ext
<COMPLETE file content>
```

- Start with the most important files: main config, DB schema, server entry points
- Then all routes, controllers, services, middleware
- Then ALL frontend components (every page, component, hook, store)
- Then all Docker/config files, .env.example, README

Remember: A developer should be able to copy each block and run `docker-compose up` to get a working app.''';

      final implResp = await _callZeeraProviderB(implPrompt, systemPrompt: deploySystemPrompt);
      if (implResp != null && implResp.isNotEmpty) {
        dialogueHistory.add({'role': modelBName, 'content': implResp});
        yield '## 💻 [$modelBName — Full Code Implementation]\n\n$implResp\n\n---\n\n';
      } else {
        yield '⚠️ $modelBName implementation pass failed.\n\n';
      }

      // === ROUND 3: Model A REVIEWS B's code and adds/fixes anything missing ===
      if (dialogueHistory.length >= 2) {
        _setStatus('ZEERA — $modelAName reviewing and completing gaps...');
        final reviewPrompt = '''You designed this architecture:
${dialogueHistory[0]['content']}

$modelBName implemented this code:
${dialogueHistory[1]['content']}

**YOUR TASK:** Review $modelBName's implementation and:
1. Identify ANY missing files, incomplete implementations, or bugs
2. Write the COMPLETE code for ANY missing pieces
3. Fix any bugs you see
4. Add any configuration or deployment files that are missing
5. Ensure the app will work 100% out of the box

Output ONLY the additional/fixed files using:
```filename: path/to/file.ext
<complete fixed content>
```

If everything is complete, write a deployment checklist instead.''';

        final reviewResp = await _callZeeraProviderA(reviewPrompt, systemPrompt: deploySystemPrompt);
        if (reviewResp != null && reviewResp.isNotEmpty) {
          dialogueHistory.add({'role': '$modelAName-Review', 'content': reviewResp});
          yield '## 🔍 [$modelAName — Code Review & Gap Fill]\n\n$reviewResp\n\n---\n\n';
        }
      }

    } else {
      // === COLLABORATIVE REASONING MODE (non-project) ===
      yield '**[ZEERA — COLLABORATIVE INTELLIGENCE]**\n🧠 **$modelAName** ↔ **$modelBName** — Each model reads the other\'s output\n\n';

      for (int i = 1; i <= totalRounds; i++) {
        // === Model A turn — reads ALL previous dialogue ===
        _setStatus('ZEERA — $modelAName thinking (Round $i of $totalRounds)...');

        final promptA = i == 1
            ? '''You are collaborating with another AI ($modelBName) to answer: "$prompt"

Provide your BEST, most thorough analysis. Be specific, give examples, go deep.
Your response will be shared with $modelBName who will build upon or critique it.'''
            : '''You are collaborating with $modelBName to answer: "$prompt"

$modelBName's previous response:
---
${dialogueHistory.last['content']}
---

Now: (1) Build upon the strong points, (2) Correct any errors you see, (3) Add what is missing, (4) Synthesize into a stronger answer.
Be direct about disagreements and explain why.''';

        final respA = await _callZeeraProviderA(promptA, systemPrompt: zeeraSystemPrompt);
        if (respA != null && respA.isNotEmpty) {
          dialogueHistory.add({'role': modelAName, 'content': respA});
          yield '\n**[$modelAName — Round $i]**\n$respA\n\n';
        } else {
          yield '⚠️ $modelAName unavailable in Round $i.\n';
        }

        // === Model B turn — explicitly reads Model A's latest response ===
        _setStatus('ZEERA — $modelBName responding (Round $i of $totalRounds)...');

        final lastAResp = dialogueHistory.isNotEmpty ? dialogueHistory.last['content'] : '';
        final promptB = '''You are collaborating with $modelAName to answer: "$prompt"

$modelAName just said:
---
$lastAResp
---

Your job: (1) Agree with what is correct, (2) Challenge what is wrong with evidence, (3) Add dimensions $modelAName missed, (4) Push toward the most complete, accurate answer possible.
This is a collaborative reasoning session — be rigorous and specific.''';

        final respB = await _callZeeraProviderB(promptB, systemPrompt: zeeraSystemPrompt);
        if (respB != null && respB.isNotEmpty) {
          dialogueHistory.add({'role': modelBName, 'content': respB});
          yield '\n**[$modelBName — Round $i Response]**\n$respB\n\n';
        } else {
          yield '⚠️ $modelBName unavailable in Round $i.\n';
        }
      }
    }

    // === FINAL META-SYNTHESIS ===
    _setStatus('ZEERA — Meta-synthesis in progress...');

    if (dialogueHistory.isEmpty) {
      yield '\n❌ Both models failed. Check NVIDIA API key and Ollama Cloud settings.';
      _setStatus('ZEERA — Failed');
      return;
    }

    final nvidiaKey = (await _secureStorage.getApiKey('nvidia'))?.trim() ?? '';
    if (nvidiaKey.isEmpty) {
      yield '\n\n**[ZEERA — COMBINED OUTPUT]**\n\n';
      for (final entry in dialogueHistory) {
        yield '### ${entry['role']}\n${entry['content']}\n\n';
      }
      _setStatus('ZEERA — Complete');
      return;
    }

    final synthModel = _zeeraSynthesisModel ?? _selectedModels[AIProvider.nvidia] ?? 'nvidia/llama-3.1-nemotron-ultra-253b-v1';
    debugPrint('[Zeera-Synthesis] Final synthesis via: $synthModel');
    
    final synthesisSystemPrompt = isProject
        ? '''You are ZEERA — the world's most advanced AI code synthesis engine.
You receive outputs from two AI models collaborating on a software project.
Your job: produce the SINGLE MOST COMPLETE, PRODUCTION-READY final version.
RULES:
- Merge the best parts of both models' outputs
- Fill ALL gaps — every file must be 100% complete
- Format: each file in its OWN separate code block:
```filename: path/to/file
<complete content>
```
- Include a deployment checklist at the end
- ZERO placeholders, ZERO truncation, ZERO TODO comments'''
        : '''You are ZEERA — a meta-intelligence that synthesizes collaborative AI dialogue into the definitive answer.
RULES:
- Read the full dialogue between $modelAName and $modelBName
- Extract the highest-quality insights from each
- Resolve contradictions with clear reasoning
- Produce a response that is BETTER than either model alone
- Be comprehensive yet clear\n- Use markdown formatting for readability''';

    final synthesisPrompt = isProject
        ? '''User wants to build: "$prompt"

Here is the collaborative output from $modelAName and $modelBName:

${_formatDialogue(dialogueHistory)}

SYNTHESIZE: Produce the FINAL, COMPLETE, DEPLOYABLE codebase.
Every file must be in its own ```filename: path/to/file``` block.
Start with README and deployment instructions, then all code files.
Absolutely NO truncation or placeholders.'''
        : '''User Question: "$prompt"

Collaborative dialogue between $modelAName and $modelBName:
${_formatDialogue(dialogueHistory)}

Synthesize this into the single best, most complete answer possible.
Do NOT just repeat the dialogue — produce a unified, enhanced response.''';

    try {
      yield '\n\n---\n## 🧬 [ZEERA FINAL SYNTHESIS — $synthModel]\n\n';
      if (isProject) {
        yield '> 📋 **Each file is in its own code block. Copy the content of each block to create the file.**\n\n';
      }
      final stream = NvidiaApiClient(apiKey: nvidiaKey, model: synthModel)
          .generateStream(synthesisPrompt, systemPrompt: synthesisSystemPrompt, maxTokens: 16000);

      await for (final chunk in stream) {
        yield chunk;
      }
      yield '\n\n---\n✅ **ZEERA synthesis complete.**';
    } catch (e) {
      debugPrint('[Zeera-Synthesis] Error: $e');
      yield '\n\n**[ZEERA — Recovery Mode]** Outputting best model response:\n\n';
      // Output all collected dialogue as the final answer
      for (final entry in dialogueHistory) {
        yield '### ${entry['role']}\n${entry['content']}\n\n---\n\n';
      }
    }

    _setStatus('ZEERA — Response Complete');
  }

  String _formatDialogue(List<Map<String, String>> history) {
    if (history.isEmpty) return "None.";
    return history.map((m) => "[${m['role']}]: ${m['content']}").join('\n\n---\n\n');
  }

  /// Helper to pick the "best" model from a list, prioritizing hints or common defaults.
  String _pickBestModel(List<String> models, {String? hint}) {
    if (models.isEmpty) return '';

    // Prioritize models that contain the hint
    if (hint != null) {
      final matchingModels = models.where((m) => m.toLowerCase().contains(hint.toLowerCase())).toList();
      if (matchingModels.isNotEmpty) {
        // Try to find a "chat" or "instruct" version if hint is generic
        final chatInstruct = matchingModels.firstWhere(
          (m) => m.toLowerCase().contains('chat') || m.toLowerCase().contains('instruct'),
          orElse: () => matchingModels.first,
        );
        return chatInstruct;
      }
    }

    // Fallback to common defaults if no hint or no match
    final commonDefaults = [
      'deepseek', 
      'llama-3.3', // Added newer llama
      'llama-3.1', 
      'llama3', 
      'nemotron', // NVIDIA specific
      'gemini-pro', 
      'gpt-4', 
      'mixtral', 
      'gemma'
    ];
    for (final defaultModel in commonDefaults) {
      final found = models.firstWhere(
        (m) => m.toLowerCase().contains(defaultModel.toLowerCase()),
        orElse: () => '',
      );
      if (found.isNotEmpty) return found;
    }

    // If all else fails, just return the first available model
    return models.first;
  }

  /// Fetch available models for a provider
  Future<List<String>> fetchModels(AIProvider provider) async {
    try {
      switch (provider) {
        case AIProvider.gemini:
          final key = await _secureStorage.getApiKey('gemini');
          if (key == null || key.isEmpty) return [];
          return await GeminiApiClient(apiKey: key).fetchModels();
        case AIProvider.ollama:
          final localUrl = await _secureStorage.getBaseUrl('ollamaLocal') ?? 'http://127.0.0.1:11434';
          _ollamaService.setLocalUrl(localUrl);
          final all = await _ollamaService.fetchAvailableModels();
          return all.where((m) => !m.isCloud).map((m) => m.name).toList();
        case AIProvider.ollamaCloud:
          final cloudUrl = await _secureStorage.getBaseUrl('ollamaCloud') ?? 'https://api.ollama.com';
          if (kIsWeb && (cloudUrl == 'https://api.ollama.com' || cloudUrl.isEmpty || cloudUrl == '/api/ollama')) {
             _ollamaService.setBaseUrl(Uri.base.resolve('/api/ollama').toString().replaceAll(RegExp(r'/$'), ''));
          } else {
             _ollamaService.setBaseUrl(cloudUrl);
          }
          final all = await _ollamaService.fetchAvailableModels();
          return all.where((m) => m.isCloud).map((m) => m.name).toList();
        case AIProvider.nvidia:
          final key = await _secureStorage.getApiKey('nvidia');
          if (key == null || key.isEmpty) return [];
          return await NvidiaApiClient(apiKey: key, model: '').fetchModels();
        case AIProvider.openRouter:
          final key = await _secureStorage.getApiKey('openRouter');
          if (key == null || key.isEmpty) return [];
          return await OpenRouterClient(apiKey: key, model: '').fetchModels();
        case AIProvider.anthropic:
          final key = await _secureStorage.getApiKey('anthropic');
          if (key == null || key.isEmpty) return [];
          return await AnthropicApiClient(apiKey: key).fetchModels();
        case AIProvider.llamaCpp:
          return ['LLaMA-3', 'Mistral']; 
        case AIProvider.zeera:
          final key = await _secureStorage.getApiKey('zeeraSynthesis');
          if (key == null || key.isEmpty) return [];
          return await NvidiaApiClient(apiKey: key, model: '').fetchModels();
      }
    } catch (e) {
      debugPrint('[AIRouter] Failed to fetch models for ${provider.name}: $e');
      return [];
    }
  }

  /// Perform a real-time web search via Ollama Cloud API
  Future<String> webSearch(String query) async {
    try {
      _setStatus('Searching the web...');
      final results = await _ollamaService.webSearch(query);
      if (results.isEmpty) return "No results found.";
      
      final StringBuffer sb = StringBuffer();
      sb.writeln("WEB SEARCH RESULTS for: '$query'");
      for (var r in results.take(3)) {
         sb.writeln("• TITLE: ${r['title']}");
         sb.writeln("  URL: ${r['url']}");
         sb.writeln("  CONTENT: ${r['content']}");
      }
      return sb.toString();
    } catch (e) {
      debugPrint('[AIRouter] webSearch failed: $e');
      return "⚠️ Web search failed: $e";
    }
  }

  String _providerName(AIProvider p) {
    switch (p) {
      case AIProvider.llamaCpp: return 'llama.cpp';
      case AIProvider.gemini: return 'Gemini';
      case AIProvider.ollama: return 'Ollama (Local)';
      case AIProvider.ollamaCloud: return 'Ollama Cloud';
      case AIProvider.nvidia: return 'NVIDIA';
      case AIProvider.openRouter: return 'OpenRouter';
      case AIProvider.zeera: return 'Zeera';
      case AIProvider.anthropic: return 'Anthropic';
    }
  }
}

