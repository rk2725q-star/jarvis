import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jarvis_ai/core/router/ai_router.dart';
import 'package:jarvis_ai/core/file_processor/file_processor.dart';
import 'package:jarvis_ai/models/message.dart';
import 'package:jarvis_ai/models/session.dart';
import 'package:jarvis_ai/services/session_service.dart';
import 'package:jarvis_ai/services/tts_service.dart';
import 'package:jarvis_ai/services/notification_service.dart';
import 'package:jarvis_ai/services/netless_context_manager.dart';
import 'package:jarvis_ai/services/netless_service.dart';
import 'package:jarvis_ai/features/diagram/diagram_service.dart';
import 'package:jarvis_ai/features/integrations/integrations_model.dart';
import 'package:jarvis_ai/features/integrations/integrations_provider.dart';
import 'package:jarvis_ai/services/aggregator_service.dart';
import 'package:jarvis_ai/data/models/search_result_model.dart';
import 'package:jarvis_ai/services/skill_service.dart';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:jarvis_ai/features/codesign/services/codesign_service.dart';
import 'package:jarvis_ai/features/codesign/models/codesign_models.dart';
import 'package:jarvis_ai/features/mcp/mcp_client.dart';
class ChatProvider extends ChangeNotifier {
  final AIRouter router;
  final SessionService sessionService;
  final TtsService ttsService;
  final IntegrationsProvider integrationsProvider;
  final FileProcessor _fileProcessor = FileProcessor();
  final AggregatorService _aggregator = AggregatorService();
  ChatProvider({
    required this.router,
    required this.sessionService,
    required this.ttsService,
    required this.integrationsProvider,
  });

  final _uuid = const Uuid();
  String? _currentSessionId;
  List<Message> _messages = [];
  List<Session> _sessions = [];
  bool _isTTSEnabled = false;
  bool _isVoiceMode = false;
  List<String> _currentSuggestions = [];

  // File & Analysis state
  final List<String> _attachedFilePaths = [];
  bool _isAnalyzing = false;
  String _analysisStatus = 'Thinking...';
  bool _webSearchEnabled = true;

  String? _pendingNotificationReply;

  // MCP Integration
  List<McpServer> connectedMcpServers = [];

  Future<void> connectMcpServer(String url, {String? token}) async {
    final server = await McpServer.connect(url, token: token);
    connectedMcpServers.add(server);
    notifyListeners();
  }

  // ── Live Intelligence Tracking (shown in UI during generation) ──
  List<String> _activeDnaModels = [];
  List<String> _activeContextualSkills = [];

  List<String> get activeDnaModels => List.unmodifiable(_activeDnaModels);
  List<String> get activeContextualSkills => List.unmodifiable(_activeContextualSkills);
  int get totalActiveSkillCount => _activeDnaModels.length + _activeContextualSkills.length;

  /// Compute which skills are active for a given query — mirrors ai_router logic
  void _computeActiveSkills(String query) {
    final allSkills = router.skillService.skills.where((s) => s.isActive).toList();
    _activeDnaModels = allSkills
        .where((s) => s.id.startsWith('jarvis-dna-'))
        .map((s) => s.description.split('—').first.trim())
        .toList();

    // Score contextual skills
    final scored = allSkills
        .where((s) => !s.id.startsWith('jarvis-dna-'))
        .map((s) {
          final queryWords = query.toLowerCase()
              .split(RegExp(r'[^a-zA-Z0-9]'))
              .where((w) => w.length > 2)
              .toSet();
          if (queryWords.isEmpty) return MapEntry(s, 0.0);
          final kw = s.triggerKeywords.map((k) => k.toLowerCase()).toSet();
          final hits = queryWords.intersection(kw).length;
          final score = hits / queryWords.length;
          return MapEntry(s, score);
        })
        .where((e) => e.value > 0)
        .toList();
    scored.sort((a, b) => b.value.compareTo(a.value));
    _activeContextualSkills = scored.take(12)
        .map((e) => e.key.name)
        .toList();
    notifyListeners();
  }

  void _clearActiveSkills() {
    _activeDnaModels = [];
    _activeContextualSkills = [];
    notifyListeners();
  }

  // Netless Smart Context Manager
  final NetlessContextManager netlessContext = NetlessContextManager();

  // Getters
  String? get currentSessionId => _currentSessionId;
  List<Message> get messages => List.unmodifiable(_messages);
  List<Session> get sessions => List.unmodifiable(_sessions);
  bool get isTTSEnabled => _isTTSEnabled;
  bool get isVoiceMode => _isVoiceMode;
  List<String> get currentSuggestions => List.unmodifiable(_currentSuggestions);
  bool get isGenerating => router.isGenerating || _isAnalyzing;
  List<String> get attachedFilePaths => List.unmodifiable(_attachedFilePaths);
  bool get isAnalyzing => _isAnalyzing;
  String get analysisStatus => _analysisStatus;
  bool get webSearchEnabled => _webSearchEnabled;
  String? get pendingNotificationReply => _pendingNotificationReply;

  void toggleWebSearch(bool value) {
    _webSearchEnabled = value;
    notifyListeners();
  }

  void _setAnalysisStatus(String status, {bool active = true}) {
    _analysisStatus = status;
    _isAnalyzing = active;
    notifyListeners();
  }

  Future<void> init() async {
    await _aggregator.initialize();
    await loadSessions();
    if (_sessions.isEmpty) {
      await createNewSession();
    } else {
      await switchSession(_sessions.first.id);
    }
    await checkPendingNotification();
  }

  Future<void> checkPendingNotification() async {
    final prefs = await SharedPreferences.getInstance();
    final notif = prefs.getString('pending_notification_reply');
    if (notif != null) {
      _pendingNotificationReply = notif;
      await prefs.remove('pending_notification_reply');
      notifyListeners();
    }
  }

  void cancelPendingNotification() {
    _pendingNotificationReply = null;
    notifyListeners();
  }

  Future<void> loadSessions() async {
    _sessions = sessionService.getAllSessions();
    notifyListeners();
  }

  Future<void> createNewSession() async {
    final session = await sessionService.createSession();
    _sessions.insert(0, session);
    await switchSession(session.id);
  }

  Future<void> switchSession(String sessionId) async {
    _currentSessionId = sessionId;
    _messages = sessionService.getMessages(sessionId);
    notifyListeners();
  }

  Future<void> deleteSession(String sessionId) async {
    await sessionService.deleteSession(sessionId);
    _sessions.removeWhere((s) => s.id == sessionId);
    if (_currentSessionId == sessionId) {
      if (_sessions.isNotEmpty) {
        await switchSession(_sessions.first.id);
      } else {
        await createNewSession();
      }
    }
    notifyListeners();
  }

  Future<void> renameSession(String sessionId, String newTitle) async {
    final idx = _sessions.indexWhere((s) => s.id == sessionId);
    if (idx != -1) {
      final updated = _sessions[idx].copyWith(title: newTitle);
      await sessionService.updateSession(updated);
      _sessions[idx] = updated;
      notifyListeners();
    }
  }

  Future<void> pickAndAttachFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
      );

      if (result != null && result.paths.isNotEmpty) {
        for (final path in result.paths) {
          if (path != null && !_attachedFilePaths.contains(path)) {
            _attachedFilePaths.add(path);
          }
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint("File picking failed: $e");
    }
  }

  void unattachFile(String path) {
    _attachedFilePaths.remove(path);
    notifyListeners();
  }

  void attachFile(String path) {
    if (!_attachedFilePaths.contains(path)) {
      _attachedFilePaths.add(path);
      notifyListeners();
    }
  }

  Future<void> sendMessage(String text) async {
    if (_currentSessionId == null) return;
    if (text.trim().isEmpty && _attachedFilePaths.isEmpty) return;

    _currentSuggestions = [];
    notifyListeners();

    // ── Intercept Skill Creation Command ────────────────────────────────────
    if (text.trim().startsWith('/skill')) {
      final userMsg = Message(
        id: _uuid.v4(),
        content: text.trim(),
        isUser: true,
        timestamp: DateTime.now(),
        sessionId: _currentSessionId!,
      );
      _messages.add(userMsg);
      await sessionService.addMessage(userMsg);
      _setAnalysisStatus("building skill...");
      notifyListeners();

      final skillDescription = text.trim().substring(6).trim();
      if (skillDescription.isEmpty) {
        final errorMsg = Message(
          id: _uuid.v4(),
          content: "❌ **Error: Skill description cannot be empty.**\n\nUsage: `/skill [description of what the skill should do]`\nE.g.: `/skill Translate any programming queries to python scripts`",
          isUser: false,
          timestamp: DateTime.now(),
          sessionId: _currentSessionId!,
        );
        _messages.add(errorMsg);
        await sessionService.addMessage(errorMsg);
        _setAnalysisStatus("thinking...", active: false);
        notifyListeners();
        return;
      }

      final SkillService service = router.skillService;
      try {
        final creatorPrompt = "The user wants to build a custom skill for their AI assistant. "
            "Skill description: '$skillDescription'.\n\n"
            "Analyze the description and generate a structured JSON object for this skill. "
            "Ensure the system instructions are highly specific, professional, and explain how to handle the inputs and format responses. "
            "Extract 5-10 trigger keywords that identify when the skill should be used.\n\n"
            "Return ONLY a valid JSON object matching this schema, no markdown blocks, no other text:\n"
            "{\n"
            "  \"name\": \"Short descriptive name\",\n"
            "  \"description\": \"One sentence description of functionality\",\n"
            "  \"systemInstruction\": \"Instructions telling the AI how to behave when this skill is invoked\",\n"
            "  \"triggerKeywords\": [\"keyword1\", \"keyword2\", ...]\n"
            "}";

        final response = await router.generate(
          creatorPrompt,
          systemPrompt: "You are the JARVIS Autonomous Skill Builder. Output valid JSON matching the schema only.",
        );

        final cleanJson = response.replaceFirst('```json', '').replaceFirst('```', '').trim();
        final Map<String, dynamic> parsed = jsonDecode(cleanJson);

        final skillName = parsed['name']?.toString() ?? 'Custom Skill';
        final skillDesc = parsed['description']?.toString() ?? skillDescription;
        final skillInstruction = parsed['systemInstruction']?.toString() ?? 'Adopt the user\'s requested behavior.';
        final List<String> keywords = List<String>.from(parsed['triggerKeywords'] ?? []);

        final createdSkill = await service.createSkill(
          name: skillName,
          description: skillDesc,
          systemInstruction: skillInstruction,
          triggerKeywords: keywords,
        );

        final successContent = "🎨 **Dynamic Skill Built Successfully!**\n\n"
            "JARVIS has autonomously generated and compiled this capability:\n\n"
            "• **Skill Name:** ${createdSkill.name}\n"
            "• **Description:** ${createdSkill.description}\n"
            "• **Trigger Keywords:** `${createdSkill.triggerKeywords.join(', ')}`\n\n"
            "⚙️ **System Prompt Directive:**\n"
            "> ${createdSkill.systemInstruction}\n\n"
            "--- \n"
            "🔄 *This skill is now **active** across all conversation sessions. JARVIS will automatically invoke it whenever your message matches the trigger context!*";

        final successMsg = Message(
          id: _uuid.v4(),
          content: successContent,
          isUser: false,
          timestamp: DateTime.now(),
          sessionId: _currentSessionId!,
        );
        _messages.add(successMsg);
        await sessionService.addMessage(successMsg);
      } catch (e) {
        final fallbackName = skillDescription.length > 20 ? "${skillDescription.substring(0, 20)}..." : skillDescription;
        final createdSkill = await service.createSkill(
          name: fallbackName,
          description: "User-defined skill: $skillDescription",
          systemInstruction: "You are playing a custom role. Behavior required: $skillDescription.",
          triggerKeywords: skillDescription.toLowerCase().split(' ').where((w) => w.length > 4).toList(),
        );

        final successContent = "🎨 **Dynamic Skill Created (Local Fallback)**\n\n"
            "• **Skill Name:** ${createdSkill.name}\n"
            "• **Description:** ${createdSkill.description}\n\n"
            "🔄 *This skill has been added and is active. JARVIS will run it when triggered!*";

        final successMsg = Message(
          id: _uuid.v4(),
          content: successContent,
          isUser: false,
          timestamp: DateTime.now(),
          sessionId: _currentSessionId!,
        );
        _messages.add(successMsg);
        await sessionService.addMessage(successMsg);
      } finally {
        _setAnalysisStatus("thinking...", active: false);
        notifyListeners();
      }
      return;
    }

    // ── Intercept Roadmap Commands ──────────────────────────────────────────
    final cleanInput = text.trim().toLowerCase();
    final isRoadmapRequest = cleanInput == '/roadmap' ||
        cleanInput == 'roadmap' ||
        cleanInput.contains('roadmap') ||
        cleanInput.contains('road map') ||
        RegExp(r'\broad\s*map\b', caseSensitive: false).hasMatch(cleanInput);
    if (isRoadmapRequest) {
      final userMsg = Message(
        id: _uuid.v4(),
        content: text.trim(),
        isUser: true,
        timestamp: DateTime.now(),
        sessionId: _currentSessionId!,
      );
      _messages.add(userMsg);
      await sessionService.addMessage(userMsg);
      notifyListeners();

      // 1. Add Textual Milestones Message
      final textContent = '# Strategic Roadmap Toward Robust, Human-Like AI Capabilities\n\n'
          'Here are the key milestones of the 10-year phased research plan:\n\n'
          '| Milestone | Phase & Focus | Target / Evaluation Metric |\n'
          '|-----------|---------------|----------------------------|\n'
          '| **M1.1: Adversarial Common-Sense** | Phase 1 (Years 1-3) | Physical/social reasoning score <30% |\n'
          '| **M1.2: Causal World Models** | Phase 1 (Years 1-3) | Intervention prediction accuracy |\n'
          '| **M2.1: Neuro-Symbolic Planning** | Phase 2 (Years 3-6) | Plan success rate over 50+ steps |\n'
          '| **M2.3: Theory-of-Mind Modules** | Phase 2 (Years 3-6) | False-belief task performance |\n'
          '| **M3.4: Provable Safety Boundaries** | Phase 3 (Years 6-9) | Formal verification coverage |\n'
          '| **M4.2: Collaborative Deferral** | Phase 4 (Years 9-12) | Joint human-AI task performance |\n\n'
          '---\n\n'
          '**Want to see the full interactive dashboard?**\n\n'
          'You can:\n'
          '- Open the **AI Roadmap Dashboard** from the navigation drawer\n'
          '- Or type `/roadmap` to view the interactive card in chat\n\n'
          'This lets you explore live simulators for causal counterfactuals, Theory of Mind false-beliefs, neuro-symbolic QA, provable safety scripting, and human-AI cooperative deferral.\n\n'
          'Would you like me to show the dashboard? 🚀';

      final aiTextMsg = Message(
        id: _uuid.v4(),
        content: textContent,
        isUser: false,
        timestamp: DateTime.now(),
        sessionId: _currentSessionId!,
      );
      _messages.add(aiTextMsg);
      await sessionService.addMessage(aiTextMsg);
      notifyListeners();

      // 2. Add Interactive Card Message
      final aiCardMsg = Message(
        id: _uuid.v4(),
        content: '<!--JARVIS_ROADMAP_CARD-->',
        isUser: false,
        timestamp: DateTime.now(),
        sessionId: _currentSessionId!,
      );
      _messages.add(aiCardMsg);
      await sessionService.addMessage(aiCardMsg);
      notifyListeners();
      return;
    }

    String combinedText = text.trim();

    // ── @ Integration routing ─────────────────────────────────────────────────
    String? atIntegrationCapability;
    String? resolvedProvider;
    AIIntegration? targetIntg;

    final atMatch = RegExp(r'^@(\w+)\s*').firstMatch(combinedText);
    if (atMatch != null) {
      final intId = atMatch.group(1)!.toLowerCase();
      targetIntg = findIntegration(intId);
      if (targetIntg != null) {
        resolvedProvider = intId;
        combinedText = combinedText.substring(atMatch.end).trim();
      }
    }
    
    // ── Creative Modes Interception ──────────────────────────────────────────
    bool isImagiya = false;
    bool isCodesign = false;
    String imagiyaPrompt = '';
    String finalImagePrompt = '';
    String codesignAgentType = 'landing';
    
    if (combinedText.startsWith('[IMAGIYA]')) {
      isImagiya = true;
      final parts = combinedText.substring(9).split('|');
      final qualityStyle = parts.isNotEmpty ? parts[0].trim() : 'hd realistic';
      final qualityParts = qualityStyle.split(' ');
      final style = qualityParts.length > 1 ? qualityParts.skip(1).join(' ') : 'realistic';
      imagiyaPrompt = parts.length > 1 ? parts.skip(1).join('|').trim() : '';
      finalImagePrompt = '$imagiyaPrompt, $style style, highly detailed, sharp text, legible typography';
    } else if (combinedText.startsWith('[CODESIGN]')) {
      isCodesign = true;
      final parts = combinedText.substring(10).split('|');
      codesignAgentType = parts.isNotEmpty ? parts[0].trim() : 'landing';
      final designQuery = parts.length > 1 ? parts.skip(1).join('|').trim() : '';
      imagiyaPrompt = designQuery.isNotEmpty ? designQuery : codesignAgentType;
      finalImagePrompt = 'Modern $codesignAgentType UI UX design, $imagiyaPrompt, clean minimal interface, sharp readable text labels, dribbble behance quality, high fidelity wireframe, professional web design, no blur';
    } else {
      // Auto-detect design queries
      final queryLower = combinedText.toLowerCase();
      final designKeywords = [
        'design website', 'design a website', 'design website for',
        'design landing page', 'design landing-page',
        'design web page', 'design web-page',
        'design mobile ui', 'design mobile app', 'design mobile layout',
        'design dashboard', 'design admin dashboard',
        'design pricing page', 'design pricing-page',
        'create landing page', 'create dashboard', 'create pricing page',
        'design a mobile ui', 'design a dashboard', 'design a landing page'
      ];
      bool matchesKeyword = false;
      for (final kw in designKeywords) {
        if (queryLower.contains(kw)) {
          matchesKeyword = true;
          break;
        }
      }
      
      // Also check for general "design an app" or "create a website" context
      if (!matchesKeyword) {
        if ((queryLower.contains('design') || queryLower.contains('create')) && 
            (queryLower.contains('website') || queryLower.contains('landing page') || queryLower.contains('dashboard') || queryLower.contains('mobile ui') || queryLower.contains('pricing page') || queryLower.contains('app ui'))) {
          matchesKeyword = true;
        }
      }

      if (matchesKeyword) {
        isCodesign = true;
        if (queryLower.contains('dashboard') || queryLower.contains('admin')) {
          codesignAgentType = 'dashboard';
        } else if (queryLower.contains('mobile') || queryLower.contains('app ui') || queryLower.contains('phone')) {
          codesignAgentType = 'mobile';
        } else if (queryLower.contains('pricing')) {
          codesignAgentType = 'pricing';
        } else if (queryLower.contains('slides') || queryLower.contains('presentation')) {
          codesignAgentType = 'slides';
        } else {
          codesignAgentType = 'landing';
        }
        imagiyaPrompt = text.trim();
        finalImagePrompt = 'Modern $codesignAgentType UI UX design, $imagiyaPrompt, clean minimal interface, sharp readable text labels, dribbble behance quality, high fidelity wireframe, professional web design, no blur';
      }
    }


    // NOTE: Autonomous keyword-based integration routing is intentionally disabled.
    // Integrations are ONLY triggered when the user explicitly uses @mention.

    if (targetIntg != null && resolvedProvider != null) {
      final cap = kIntegrationCapabilityPrompts[resolvedProvider];
      if (cap != null) {
        atIntegrationCapability =
            '\n\n[@ INTEGRATION OVERRIDE — EXCLUSIVE MODE]\n'
            'The user has specifically invoked the @${targetIntg.name} integration.\n'
            'You MUST respond as if you ARE ${targetIntg.name}. Use ALL its capabilities.\n'
            '$cap\n'
            '[END OVERRIDE]';
      }
    }


    // Check if the user is replying after opening the app from a notification
    if (_pendingNotificationReply != null) {
      final payload = _pendingNotificationReply!;
      combinedText =
          "[SYSTEM NOTE: The user just opened the app from a notification titled: '$payload'. Respond contextually as if they are reacting to it.]\n\nUSER QUERY: ${text.isEmpty ? '(User just opened the report)' : combinedText}";

      // PERSISTENT MEMORY UPDATE: Only mark as routine completion if it's not a report
      final isReport =
          payload.contains('Report') ||
          payload.contains('Summary') ||
          payload.contains('Recap');
      if (!isReport) {
        router.memory.addMemory(
          content:
              "ROUTINE COMPLETED: User replied to '$payload' with '$text'. They are finished with this task. Do NOT ask them if they did this again today.",
          importance: 1.0,
          category: 'notification',
        );

        // INTELLIGENT SKIP: If they just replied to a routine, skip future routine reminders for today
        final notificationService = NotificationService();
        final routineType = _getRoutineTypeFromPurpose(payload);
        if (routineType != null) {
          notificationService.skipRoutineForToday(routineType);
        }
      } else {
        router.memory.addMemory(
          content:
              "REPORT LOG: User opened '$payload'. Report was generated and discussed.",
          importance: 0.7,
          category: 'report',
        );
      }

      _pendingNotificationReply = null;
      notifyListeners();
    }

    // Also check if the message itself indicates they already did something
    final lower = text.toLowerCase();
    if (lower.contains('i ate') ||
        lower.contains('had my breakfast') ||
        lower.contains('breakfast sapten') ||
        lower.contains('eat breakfast')) {
      NotificationService().skipRoutineForToday('breakfast');
    } else if (lower.contains('i wake up') || lower.contains('woke up')) {
      NotificationService().skipRoutineForToday('morning');
    } else if (lower.contains('ate lunch') || lower.contains('lunch sapten')) {
      NotificationService().skipRoutineForToday('lunch');
    } else if (lower.contains('had dinner') ||
        lower.contains('dinner sapten')) {
      NotificationService().skipRoutineForToday('dinner');
    } else if (lower.contains('going to sleep') ||
        lower.contains('sleeping now')) {
      NotificationService().skipRoutineForToday('sleep');
    }

    // --- Inject Short-Term Chat History ---
    final actualProvider = resolvedProvider ?? router.activeProvider?.name;

    if (actualProvider == 'netless') {
      // Use smart context manager for Netless to strictly manage 1024 token limit
      final ref = netlessContext.parseReference(combinedText);
      String enrichedPrompt = combinedText;
      if (ref != null) {
        enrichedPrompt = '${ref.role} said: "${ref.content}"\n\nUser: $combinedText';
      }
      combinedText = await netlessContext.prepareContext(enrichedPrompt, NetlessService());
    } else {
      final bool isInfinity = router.lastSelectedProvider != AIProvider.netless;
      if (isInfinity) {
        final recentHistory = _messages.where((m) => !m.isStreaming).toList();
        
        // If we have history, build a virtual 3M context window!
        if (recentHistory.isNotEmpty) {
          // Keep the last 12 messages fully intact (short-term context)
          final int shortTermCount = 12;
          final int splitIdx = recentHistory.length > shortTermCount
              ? recentHistory.length - shortTermCount
              : 0;

          final olderHistory = recentHistory.sublist(0, splitIdx);
          final recentHistoryPart = recentHistory.sublist(splitIdx);

          // Build a highly compressed session synopsis for older messages
          // so that the AI retains chronological context of the entire past
          // chat session without blowing up the actual model's prompt limit.
          final olderSummaryBuf = StringBuffer();
          if (olderHistory.isNotEmpty) {
            olderSummaryBuf.writeln("[INFINITY VIRTUAL 3M CONTEXT — COMPRESSED SESSION MEMORY]");
            for (final m in olderHistory) {
              final role = m.isUser ? "User" : "Jarvis";
              final clean = m.content.replaceAll(RegExp(r'\s+'), ' ').trim();
              final snippet = clean.length > 150
                  ? '${clean.substring(0, 80)}...${clean.substring(clean.length - 60)}'
                  : clean;
              olderSummaryBuf.writeln('• $role: $snippet');
            }
            olderSummaryBuf.writeln("[END COMPRESSED SESSION MEMORY]\n");
          }

          final recentHistoryStr = recentHistoryPart.map((m) {
            final str = m.content;
            final displayStr = str.length > 20000 ? '${str.substring(0, 20000)}\n\n...(TRUNCATED)...' : str;
            return '${m.isUser ? "USER" : "JARVIS"}:\n$displayStr';
          }).join('\n\n---\n\n');

          combinedText = "${olderSummaryBuf.toString()}[RECENT CHAT HISTORY]\n$recentHistoryStr\n\n[CURRENT USER QUERY]\n$combinedText";
        }
      } else {
        final recentHistory = _messages.where((m) => !m.isStreaming).toList();
        final recentMemories = recentHistory.length > 6 ? recentHistory.sublist(recentHistory.length - 6) : recentHistory;
        
        if (recentMemories.isNotEmpty) {
          final historyStr = recentMemories.map((m) {
            final str = m.content;
            final displayStr = str.length > 30000 ? '${str.substring(0, 30000)}\n\n...(TRUNCATED FOR MEMORY)...' : str;
            return '${m.isUser ? "USER" : "JARVIS"}:\n$displayStr';
          }).join('\n\n---\n\n');
          
          String finalHistory = historyStr;
          int maxLength = 60000;
          if (finalHistory.length > maxLength) {
            finalHistory = "...\n${finalHistory.substring(finalHistory.length - maxLength)}";
          }
          combinedText = "[RECENT CHAT HISTORY]\n$finalHistory\n\n[CURRENT USER QUERY]\n$combinedText";
        }
      }
    }

    // ── 1. Set Status ────────────────────────
    // Skip thinking status for creative image modes (Imagiya / CoDesign)
    if (isImagiya || isCodesign) {
      // No thinking indicator for image generation
    } else {
      bool hasImages = _attachedFilePaths.any(
        (p) =>
            p.toLowerCase().endsWith('.jpg') ||
            p.toLowerCase().endsWith('.png') ||
            p.toLowerCase().endsWith('.jpeg'),
      );
      if (_attachedFilePaths.isNotEmpty) {
        _setAnalysisStatus(hasImages ? "analyze image..." : "analyze file...");
      } else {
        _setAnalysisStatus("thinking...");
      }
    }

    // ── 2. Process files ──────────────────────
    if (_attachedFilePaths.isNotEmpty) {
      final List<String> fileContents = [];
      for (final path in _attachedFilePaths) {
        try {
          _analysisStatus =
              'Reading ${path.split(Platform.pathSeparator).last}...';
          notifyListeners();

          final extracted = await _fileProcessor.extractText(path);
          fileContents.add(
            "FILE [${path.split(Platform.pathSeparator).last}]:\n$extracted",
          );
        } catch (e) {
          debugPrint("Extraction failed for $path: $e");
        }
      }

      if (fileContents.isNotEmpty) {
        combinedText =
            "${fileContents.join("\n\n")}\n\nUSER QUERY: $combinedText";
      }

      _attachedFilePaths.clear();
      _isAnalyzing = false;
      _analysisStatus = '';
      notifyListeners();
    }

    // Compute which skills/models are active for this query (for visual display)
    _computeActiveSkills(text.trim());

    // Add user message — store ORIGINAL text only (not the history-injected combinedText)
    // combinedText (with [RECENT CHAT HISTORY]) is only sent to the AI, never displayed
    String displayText = text.isEmpty ? "Analyzed attached files" : text.trim();
    if (text.startsWith('[IMAGIYA]')) {
      displayText = '🎨 Generate Image: $imagiyaPrompt';
    } else if (text.startsWith('[CODESIGN]')) {
      final parts = text.substring(10).split('|');
      final agentType = parts.isNotEmpty ? parts[0].trim() : 'landing';
      final designQuery = parts.length > 1 ? parts.skip(1).join('|').trim() : '';
      displayText = '🎨 CoDesign · ${agentType[0].toUpperCase()}${agentType.substring(1)}: $designQuery';
    } else if (isCodesign) {
      displayText = '🎨 CoDesign · ${codesignAgentType[0].toUpperCase()}${codesignAgentType.substring(1)}: ${text.trim()}';
    }

    final userMsg = Message(
      id: _uuid.v4(),
      content: displayText,
      isUser: true,
      timestamp: DateTime.now(),
      sessionId: _currentSessionId!,
      provider: resolvedProvider,
    );
    _messages.add(userMsg);
    await sessionService.addMessage(userMsg);
    notifyListeners();
    
    // Imagiya: generate image using official providers — image only, no LLM follow-up
    if (isImagiya) {
      _setAnalysisStatus("generating image...", active: true);
      notifyListeners();
      try {
        final activeProvider = router.lastSelectedProvider ?? AIProvider.gemini;
        final selectedModel = router.getSelectedModel(activeProvider);
        
        final imageUrl = await router.generateImage(
          finalImagePrompt,
          modelOverride: selectedModel,
        );

        final aiMsg = Message(
          id: _uuid.v4(),
          content: '![Generated Image]($imageUrl)',
          isUser: false,
          timestamp: DateTime.now(),
          sessionId: _currentSessionId!,
          provider: 'imagiya',
          model: selectedModel,
        );
        _messages.add(aiMsg);
        await sessionService.addMessage(aiMsg);
      } catch (e) {
        final errorMsg = Message(
          id: _uuid.v4(),
          content: '❌ Image generation failed: $e',
          isUser: false,
          timestamp: DateTime.now(),
          sessionId: _currentSessionId!,
          provider: 'imagiya',
        );
        _messages.add(errorMsg);
        await sessionService.addMessage(errorMsg);
      } finally {
        _setAnalysisStatus("thinking...", active: false);
        notifyListeners();
      }
      return; // ← Image only, done.
    }

    // CoDesign: generate interactive HTML layout using LLM directly (open-codesign architecture)
    if (isCodesign) {
      _setAnalysisStatus("generating interactive design...", active: true);
      notifyListeners();
      try {
        final CodesignArtifactType targetType = switch (codesignAgentType.toLowerCase()) {
          'landing' || 'landingpage' => CodesignArtifactType.landingPage,
          'dashboard' => CodesignArtifactType.dashboard,
          'slides' || 'presentation' || 'slidesdeck' => CodesignArtifactType.slidesDeck,
          'mobile' || 'mobileui' || 'app' => CodesignArtifactType.mobileUI,
          'pricing' || 'pricingpage' => CodesignArtifactType.pricingPage,
          _ => CodesignArtifactType.landingPage,
        };

        final request = CodesignRequest(
          prompt: imagiyaPrompt.isEmpty ? text : imagiyaPrompt,
          type: targetType,
        );

        final codesignService = CodesignService(router: router);
        final artifact = await codesignService.generate(request);

        // Save layout as a physical .html file in the workspace designs directory
        Directory designsDir = Directory('c:/Users/manit/Downloads/wfy/designs');
        try {
          if (!await designsDir.exists()) {
            await designsDir.create(recursive: true);
          }
        } catch (_) {
          final appDir = await getApplicationDocumentsDirectory();
          designsDir = Directory('${appDir.path}/designs');
          if (!await designsDir.exists()) {
            await designsDir.create(recursive: true);
          }
        }

        final fileName = 'design_${DateTime.now().millisecondsSinceEpoch}.html';
        final file = File('${designsDir.path}/$fileName');
        await file.writeAsString(artifact.htmlContent);

        final aiMsg = Message(
          id: _uuid.v4(),
          content: '[CODESIGN_HTML]${artifact.htmlContent}',
          isUser: false,
          timestamp: DateTime.now(),
          sessionId: _currentSessionId!,
          provider: 'codesign',
          model: router.activeModel ?? 'CoDesign',
        );
        _messages.add(aiMsg);
        await sessionService.addMessage(aiMsg);
      } catch (e) {
        final errorMsg = Message(
          id: _uuid.v4(),
          content: '❌ CoDesign interactive layout generation failed: $e',
          isUser: false,
          timestamp: DateTime.now(),
          sessionId: _currentSessionId!,
          provider: 'codesign',
        );
        _messages.add(errorMsg);
        await sessionService.addMessage(errorMsg);
      } finally {
        _setAnalysisStatus("thinking...", active: false);
        notifyListeners();
      }
      return; // ← Done.
    }

    if (userMsg.provider != null && userMsg.provider!.isNotEmpty) {
      // The user mentioned an integration. Render the UI card only! No jarvis text.
      _setAnalysisStatus("thinking...", active: false);
      notifyListeners();
      return;
    }

    // ── ARIA Real-Time Search (for ALL providers) ────────────────────────────
    // Runs BEFORE the AI with a hard 3s timeout so it's always fast.
    // Results are injected INTO the prompt so every provider (Gemini, Ollama,
    // OpenRouter, etc.) has live DuckDuckGo context when generating a response.
    Future<List<AriaSearchResult>> ariaFuture = Future.value([]);
    if (_webSearchEnabled && !isImagiya && !isCodesign) {
      final query = text.trim();
      if (query.isNotEmpty) {
        _setAnalysisStatus('🔍 Searching web...');
        try {
          // 3 second fast fetch — keeps the app responsive
          final results = await _aggregator
              .searchUserQuery(query, limit: 6)
              .timeout(const Duration(seconds: 3), onTimeout: () => []);

          if (results.isNotEmpty) {
            // Build context block injected into the LLM prompt
            final contextBuf = StringBuffer(
              '\n\n[REAL-TIME WEB CONTEXT — DuckDuckGo — Query: "$query"]\n',
            );
            for (final r in results) {
              contextBuf.writeln('• ${r.title}');
              if (r.summary != null && r.summary!.isNotEmpty) {
                contextBuf.writeln('  ${r.summary}');
              }
              final date = r.publishedAt != null
                  ? r.publishedAt!.toLocal().toString().substring(0, 10)
                  : 'Recent';
              contextBuf.writeln(
                '  Source: ${r.provenance.sourceName} | Date: $date | URL: ${r.url}',
              );
            }
            contextBuf.writeln('[END REAL-TIME CONTEXT]\n');
            // Inject before the user's message so AI sees it first
            combinedText = '${contextBuf.toString()}$combinedText';
            // Keep ariaFuture with results for the footer
            ariaFuture = Future.value(results);
          }
        } catch (_) {}
        _setAnalysisStatus('thinking...');
      }
    }

    // Router and models are now ready to stream for chat.
    // Add streaming AI message placeholder
    final aiMsg = Message(
      id: _uuid.v4(),
      content: '',
      isUser: false,
      timestamp: DateTime.now(),
      sessionId: _currentSessionId!,
      isStreaming: true,
    );
    _messages.add(aiMsg);
    notifyListeners();

    final buffer = StringBuffer();

    try {
      final mcpTools = connectedMcpServers.expand((s) => s.tools).toList();
      bool useToolLoop = mcpTools.isNotEmpty && !isImagiya && !isCodesign && resolvedProvider == null;
      
      if (useToolLoop) {
        final toolsMap = mcpTools.map((t) => t.toGeminiSchema()).toList();
        bool isToolCalling = true;
        int toolLoopCount = 0;
        
        while (isToolCalling && toolLoopCount < 5) {
          final resp = await router.generateWithTools(
            combinedText,
            tools: toolsMap,
          );
          
          if (resp.toolCall != null) {
            final toolCall = resp.toolCall!;
            _setAnalysisStatus('Running ${toolCall.name}...');
            
            try {
              final server = connectedMcpServers.firstWhere(
                (s) => s.tools.any((t) => t.name == toolCall.name)
              );
              final result = await server.callTool(toolCall.name, toolCall.arguments);
              combinedText += '\n\n[Tool Result for ${toolCall.name}]:\n${jsonEncode(result)}\n\nPlease continue responding based on this result.';
            } catch (e) {
              combinedText += '\n\n[Tool Error for ${toolCall.name}]:\n$e\n\nPlease continue responding based on this result.';
            }
            toolLoopCount++;
          } else {
            isToolCalling = false;
            // Simulate streaming the final text so the UI animates properly
            final text = resp.text ?? "⚠️ No response generated.";
            final chunkSize = text.length > 500 ? 20 : 5;
            for (int i = 0; i < text.length; i += chunkSize) {
              final end = (i + chunkSize < text.length) ? i + chunkSize : text.length;
              buffer.write(text.substring(i, end));
              final idx = _messages.indexWhere((m) => m.id == aiMsg.id);
              if (idx != -1) {
                _messages[idx] = aiMsg.copyWith(
                  content: _stripTags(buffer.toString()),
                  provider: 'MCP Agent',
                  model: router.activeModel ?? 'Tool Caller',
                  isStreaming: true,
                );
                notifyListeners();
              }
              await Future.delayed(const Duration(milliseconds: 20));
            }
          }
        }
      } else {
        await for (final chunk in router.generateStream(
          combinedText,
          integrationCapabilities: atIntegrationCapability ?? '',
        )) {
          buffer.write(chunk);
          final idx = _messages.indexWhere((m) => m.id == aiMsg.id);
          if (idx != -1) {
            final displayContent = _stripTags(buffer.toString());
            final bool isInfinity = router.lastSelectedProvider != AIProvider.netless;
            _messages[idx] = aiMsg.copyWith(
              content: displayContent,
              provider: isInfinity ? 'INFINITY' : router.activeProvider?.name,
              model: isInfinity
                  ? '3M Context (${router.activeModel ?? "Brain"})'
                  : router.activeModel,
              isStreaming: true,
            );
            notifyListeners();
          }
        }
      }
    } catch (e) {
      debugPrint("Stream error: $e");
      final idx = _messages.indexWhere((m) => m.id == aiMsg.id);
      if (idx != -1) {
        _messages[idx] = aiMsg.copyWith(
          content: "⚠️ Error generating response: $e",
          isStreaming: false,
        );
        notifyListeners();
      }
    } finally {
      _setAnalysisStatus("thinking...", active: false);
      _clearActiveSkills();
      notifyListeners();
    }

    // Mark as done — strip tags, finalize message
    final idx = _messages.indexWhere((m) => m.id == aiMsg.id);
    if (idx != -1) {
      String cleanText = _stripTags(buffer.toString());

      // ── Append ARIA search sources as footer (results arrive in background) ──
      try {
        final ariaResults = await ariaFuture;
        if (ariaResults.isNotEmpty) {
          final srcBuf = StringBuffer('\n\n---\n🔍 **Real-Time Sources (DuckDuckGo)**\n');
          for (final r in ariaResults.take(5)) {
            final date = r.publishedAt != null
                ? r.publishedAt!.toLocal().toString().substring(0, 10)
                : 'Recent';
            srcBuf.writeln('- **${r.title}** — ${r.provenance.sourceName} · $date');
            if (r.url.isNotEmpty) srcBuf.writeln('  🔗 ${r.url}');
          }
          cleanText = '$cleanText${srcBuf.toString()}';
        }
      } catch (_) {}

      final finalMsg = _messages[idx].copyWith(
        content: cleanText,
        isStreaming: false,
        tokenCount: _estimateTokenCount(cleanText),
      );
      _messages[idx] = finalMsg;
      await sessionService.addMessage(finalMsg);

      if (actualProvider == 'netless') {
        netlessContext.addAssistantResponse(cleanText);
      }
      notifyListeners();

      if (_isTTSEnabled) {
        await ttsService.speak(cleanText);
      }

      await _parseAndScheduleReminders(buffer.toString());

      // REAL-TIME INFORMATION: Handle <WEB_SEARCH> tag (Rule 9)
      if (_webSearchEnabled) {
        final searchRegex = RegExp(r'<WEB_SEARCH\s+query="([^"]+)">');
        final searchMatch = searchRegex.firstMatch(buffer.toString());
        if (searchMatch != null) {
          final query = searchMatch.group(1);
          if (query != null) {
            _setAnalysisStatus('searching web...');

            // 1. Fetch real-time results (returns synthesis-ready context block)
            final searchContext = await router.webSearch(query);
            _setAnalysisStatus('synthesizing...', active: true);

            // 2. Re-inject results into AI for a proper synthesized answer
            //    We send ONLY the search context + the original user query.
            //    This ensures the AI uses REAL data, not hallucinations.
            final synthesisPrompt = 'The user asked: "$query"\n\n'
                'Here are the real-time web search results you must use:\n\n'
                '$searchContext\n\n'
                'Now give a complete, accurate answer to the user query based strictly on these sources. '
                'Include the date of each fact. If the query is about today\'s news/scores/prices, mention the exact date.';

            final synthesisBuffer = StringBuffer();
            await for (final chunk in router.generateStream(
              synthesisPrompt,
              systemPrompt: 'You are JARVIS real-time information synthesizer. '
                  'Summarize the provided web search results into a clear, accurate, '
                  'well-formatted answer. Cite sources. Do NOT invent data.',
              maxTokens: 2048,
            )) {
              synthesisBuffer.write(chunk);
            }

            _setAnalysisStatus('done', active: false);

            final idxFinish = _messages.indexWhere((m) => m.id == aiMsg.id);
            if (idxFinish != -1) {
              final baseResponse = _stripTags(buffer.toString());
              final synthesized = synthesisBuffer.toString().trim();
              final updatedContent = synthesized.isNotEmpty
                  ? '$baseResponse\n\n**Real-Time Search: $query**\n$synthesized'
                  : '$baseResponse\n\n$searchContext';
              _messages[idxFinish] = _messages[idxFinish].copyWith(content: updatedContent);
              notifyListeners();
              await sessionService.addMessage(_messages[idxFinish]);
            }
          }
        }
      }

      // GOOGLE DOCS (docx) INTEGRATION
      final fullResponse = buffer.toString();

      // 1. Search Docs
      final searchDocsRegex = RegExp(r'<SEARCH_DOCS\s+query="([^"]+)">');
      final searchDocMatch = searchDocsRegex.firstMatch(fullResponse);
      if (searchDocMatch != null) {
        final query = searchDocMatch.group(1);
        if (query != null) {
          _setAnalysisStatus("searching docs...");
          final result = await router.searchGoogleDocs(query);
          _setAnalysisStatus("thinking...", active: false);

          final idxDocs = _messages.indexWhere((m) => m.id == aiMsg.id);
          if (idxDocs != -1) {
            final baseResponse = _stripTags(fullResponse);
            final updated = "$baseResponse\n\n📁 **Google Docs Search: $query**\n$result";
            _messages[idxDocs] = _messages[idxDocs].copyWith(content: updated);
            notifyListeners();
            await sessionService.addMessage(_messages[idxDocs]);
          }
        }
      }

      // 2. Read Doc
      final readDocRegex = RegExp(r'<READ_DOC\s+id="([^"]+)">');
      final readDocMatch = readDocRegex.firstMatch(fullResponse);
      if (readDocMatch != null) {
        final id = readDocMatch.group(1);
        if (id != null) {
          _setAnalysisStatus("reading doc...");
          final content = await router.readGoogleDoc(id);
          _setAnalysisStatus("thinking...", active: false);

          final idxRead = _messages.indexWhere((m) => m.id == aiMsg.id);
          if (idxRead != -1) {
            final baseResponse = _stripTags(fullResponse);
            final updated = "$baseResponse\n\n📖 **Doc Content (ID: $id):**\n$content";
            _messages[idxRead] = _messages[idxRead].copyWith(content: updated);
            notifyListeners();
            await sessionService.addMessage(_messages[idxRead]);
          }
        }
      }

      // 3. Create Doc (NEW Robust format)
      final createDocRegex = RegExp(r'<CREATE_DOC\s+title="([^"]+)">([\s\S]+?)</CREATE_DOC>', dotAll: true);
      final createDocMatch = createDocRegex.firstMatch(fullResponse);
      if (createDocMatch != null) {
        final title = createDocMatch.group(1);
        final content = createDocMatch.group(2);
        if (title != null && content != null) {
          _setAnalysisStatus("creating doc...");
          final result = await router.createGoogleDoc(title, content);
          _setAnalysisStatus("thinking...", active: false);

          final idxCreate = _messages.indexWhere((m) => m.id == aiMsg.id);
          if (idxCreate != -1) {
            final baseResponse = _stripTags(fullResponse);
            final updated = "$baseResponse\n\n$result";
            _messages[idxCreate] = _messages[idxCreate].copyWith(content: updated);
            notifyListeners();
            await sessionService.addMessage(_messages[idxCreate]);
          }
        }
      }

      // 4. Create Academic Report (Massive 16-22 pages)
      final academicReportRegex = RegExp(r'<CREATE_ACADEMIC_REPORT\s+topic=["' "'" r']([^"' "'" r']+)' r'["' "'" r']\s+title=["' "'" r']([^"' "'" r']+)' r'["' "'" r']>');
      final academicReportMatch = academicReportRegex.firstMatch(fullResponse);
      if (academicReportMatch != null) {
        final topic = academicReportMatch.group(1);
        final title = academicReportMatch.group(2);
        if (topic != null && title != null) {
          _setAnalysisStatus("generating report...");
          final result = await router.createAcademicReport(topic, title);
          _setAnalysisStatus("thinking...", active: false);

          final idxReport = _messages.indexWhere((m) => m.id == aiMsg.id);
          if (idxReport != -1) {
            final baseResponse = _stripTags(fullResponse);
            final updated = "$baseResponse\n\n$result";
            _messages[idxReport] = _messages[idxReport].copyWith(content: updated);
            notifyListeners();
            await sessionService.addMessage(_messages[idxReport]);
          }
        }
      }

      // 5. Draw Diagram
      final diagramRegex = RegExp(r'<DRAW_DIAGRAM\s+prompt="([^"]+)">');
      final diagramMatch = diagramRegex.firstMatch(fullResponse);
      if (diagramMatch != null) {
        final p = diagramMatch.group(1);
        if (p != null) {
          _setAnalysisStatus("drawing...");
          try {
            final html = await DiagramService().generateDiagram(router, p);
            final idxDiag = _messages.indexWhere((m) => m.id == aiMsg.id);
            if (idxDiag != -1) {
              final base = _stripTags(fullResponse);
              final updated = "$base\n\n<!--JARVIS_DIAGRAM-->\n$html";
              _messages[idxDiag] = _messages[idxDiag].copyWith(content: updated);
              notifyListeners();
              await sessionService.addMessage(_messages[idxDiag]);
            }
          } catch (_) {}
          _setAnalysisStatus("thinking...", active: false);
        }
      }

      _generateSuggestions(cleanText);

      // ── 6. Agentic Integration Suggestion ────────────────────────────────
      // Check both: if the AI explicitly emitted <OPEN_INTEGRATION> tag,
      // OR if user query keywords match an integration
      final openIntegRegex = RegExp(r'<OPEN_INTEGRATION\s+id="([^"]+)"(?:\s+query="([^"]+)")?>');
      final tagMatch = openIntegRegex.firstMatch(buffer.toString());

      IntegrationMatch? agentMatch;
      if (tagMatch != null) {
        final integId = tagMatch.group(1);
        final tagQuery = tagMatch.group(2) ?? text;
        final foundInteg = kAIIntegrations.firstWhere(
          (i) => i.id == integId,
          orElse: () => kAIIntegrations.first,
        );
        agentMatch = IntegrationMatch(
          integration: foundInteg,
          taskUrl: foundInteg.buildTaskUrl(tagQuery),
          reason: 'JARVIS routed your request',
        );
      }
      // NOTE: Keyword-based automatic integration detection is DISABLED.
      // Integration cards only appear when AI explicitly requests via <OPEN_INTEGRATION> tag.

      if (agentMatch != null) {
        final match = agentMatch;
        final integ = match.integration;
        // Append a special integration card message
        final cardContent =
            '<!--JARVIS_INTEGRATION_CARD-->\n'
            '${integ.id}\n'
            '${integ.name}\n'
            '${integ.emoji}\n'
            '${integ.description}\n'
            '${match.taskUrl}\n'
            '${integ.gradientColors[0]},${integ.gradientColors[1]}';
        final cardMsg = Message(
          id: _uuid.v4(),
          content: cardContent,
          isUser: false,
          timestamp: DateTime.now(),
          sessionId: _currentSessionId!,
          provider: 'JARVIS Agent',
        );
        _messages.add(cardMsg);
        await sessionService.addMessage(cardMsg);
        notifyListeners();
      }
    }
    await loadSessions();
  }




  Future<void> sendDiagramMessage(String text) async {
    if (_currentSessionId == null || text.trim().isEmpty) return;
    _currentSuggestions = [];
    notifyListeners();

    final userMsg = Message(
      id: _uuid.v4(),
      content: text.trim(),
      isUser: true,
      timestamp: DateTime.now(),
      sessionId: _currentSessionId!,
    );
    _messages.add(userMsg);
    await sessionService.addMessage(userMsg);
    notifyListeners();

    final aiMsg = Message(
      id: _uuid.v4(),
      content: '🎨 JARVIS is drawing your diagram...',
      isUser: false,
      timestamp: DateTime.now(),
      sessionId: _currentSessionId!,
      isStreaming: true,
    );
    _messages.add(aiMsg);
    notifyListeners();

    try {
      final html = await DiagramService().generateDiagram(router, text);
      final idx = _messages.indexWhere((m) => m.id == aiMsg.id);
      if (idx != -1) {
        final finalMsg = aiMsg.copyWith(
          content: "<!--JARVIS_DIAGRAM-->\n$html",
          isStreaming: false,
          provider: router.activeProvider?.name,
        );
        _messages[idx] = finalMsg;
        await sessionService.addMessage(finalMsg);
        notifyListeners();
      }
    } catch (e) {
      final idx = _messages.indexWhere((m) => m.id == aiMsg.id);
      if (idx != -1) {
        _messages[idx] = aiMsg.copyWith(content: "⚠️ Failed to generate diagram: $e", isStreaming: false);
        notifyListeners();
      }
    }
  }

  Stream<String> sendMessageStream(String input, {bool isVoiceMode = false}) {
    return router.generateStream(input, isVoiceMode: isVoiceMode);
  }

  void setTTS(bool value) {
    _isTTSEnabled = value;
    if (!value) ttsService.stop();
    notifyListeners();
  }

  void setVoiceMode(bool value) {
    _isVoiceMode = value;
    notifyListeners();
  }

  Future<void> clearCurrentChat() async {
    if (_currentSessionId != null) {
      await sessionService.clearMessages(_currentSessionId!);
      _messages.clear();
      notifyListeners();
    }
  }

  int _estimateTokenCount(String text) => (text.length / 4).ceil();





  void _generateSuggestions(String lastAiResponse) {
    final r = lastAiResponse.toLowerCase();
    final List<String> suggestions = [];

    // ── Code/Tech ──────────────────────────────────────────────
    if (r.contains('code') || r.contains('function') || r.contains('class ') ||
        r.contains('algorithm') || r.contains('programming') || r.contains('bug')) {
      suggestions.addAll(['Optimize this code', 'Explain step by step', 'Add error handling', 'Write unit tests', 'Show me an example']);
    }
    // ── Story / Creative ───────────────────────────────────────
    else if (r.contains('story') || r.contains('chapter') || r.contains('character') ||
        r.contains('plot') || r.contains('write') || r.contains('poem')) {
      suggestions.addAll(['Continue the story', 'Add a plot twist', 'Describe the setting', 'Write dialogue', 'Make it shorter']);
    }
    // ── Math / Science ─────────────────────────────────────────
    else if (r.contains('equation') || r.contains('formula') || r.contains('calculate') ||
        r.contains('math') || r.contains('physics') || r.contains('chemistry')) {
      suggestions.addAll(['Show the solution steps', 'Give a real-world example', 'Simplify this', 'Related concepts', 'Practice problems']);
    }
    // ── Research / Topic ───────────────────────────────────────
    else if (r.contains('research') || r.contains('study') || r.contains('according') ||
        r.contains('history') || r.contains('discovered') || r.contains('theory')) {
      suggestions.addAll(['Tell me more', 'Key takeaways', 'Compare perspectives', 'Cite sources', 'Summarize this']);
    }
    // ── Planning / Task ────────────────────────────────────────
    else if (r.contains('plan') || r.contains('schedule') || r.contains('task') ||
        r.contains('step') || r.contains('goal') || r.contains('project')) {
      suggestions.addAll(['Break it into steps', 'Set reminders', 'Prioritize tasks', 'Add a timeline', 'Start with the first step']);
    }
    // ── Health / Fitness ───────────────────────────────────────
    else if (r.contains('health') || r.contains('exercise') || r.contains('diet') ||
        r.contains('calories') || r.contains('workout') || r.contains('nutrition')) {
      suggestions.addAll(['Weekly plan', 'Beginner tips', 'Track progress', 'Common mistakes', 'Expert advice']);
    }
    // ── Generic fallback – still context-driven ────────────────
    else {
      suggestions.addAll(['Tell me more', 'Explain in detail', 'Give an example', 'Summarize this', 'Any alternatives?']);
    }

    // Cap at 5
    _currentSuggestions = suggestions.take(5).toList();
    notifyListeners();
  }


  Future<void> _parseAndScheduleReminders(String text) async {
    try {
      final ns = NotificationService();
      final cancelRegex = RegExp(r'<CANCEL_REMINDER\s+time="([^"]+)">');
      for (final match in cancelRegex.allMatches(text)) {
        final t = match.group(1);
        if (t != null) {
          final id = ns.getRoutineIdFromPurpose(t);
          if (id != null) {
            ns.cancelNotification(id);
          } else {
            try {
              final dt = DateTime.parse(t);
              ns.cancelNotification(dt.millisecondsSinceEpoch ~/ 1000);
            } catch (_) {}
          }
        }
      }

      final updateRegex = RegExp(r'<UPDATE_ROUTINE\s+type="([^"]+)"\s+(?:weekday="([^"]+)"\s+)?time="([^"]+)">');
      for (final match in updateRegex.allMatches(text)) {
        final type = match.group(1);
        final wd = match.group(2);
        final time = match.group(3);
        if (type != null && time != null) {
          final parts = time.split(':');
          final h = int.parse(parts[0]);
          final m = int.parse(parts[1]);
          if (wd != null && (wd.contains('-') || wd.contains(','))) {
            List<int> days = [];
            if (wd.contains('-')) {
              final r = wd.split('-');
              for (int i = int.parse(r[0]); i <= int.parse(r[1]); i++) {
                days.add(i);
              }
            } else {
              days = wd.split(',').map((s) => int.parse(s.trim())).toList();
            }
            for (var d in days) {
              await ns.updateRoutine(type, weekday: d, hour: h, minute: m);
            }
          } else {
            final d = wd != null ? int.parse(wd) : null;
            await ns.updateRoutine(type, weekday: d, hour: h, minute: m);
          }
        }
      }

      final skipRegex = RegExp(r'<SKIP_ROUTINE\s+type="([^"]+)">');
      for (final match in skipRegex.allMatches(text)) {
        final ty = match.group(1);
        if (ty != null) await ns.skipRoutineForToday(ty);
      }

      final regex = RegExp(r'<SCHEDULE_REMINDER\s+time="([^"]+)"\s+message="([^"]+)">');
      for (final match in regex.allMatches(text)) {
        final t = match.group(1);
        final m = match.group(2);
        if (t != null && m != null) {
          final st = DateTime.parse(t);
          final rt = _getRoutineTypeFromPurpose(m);
          if (rt != null) {
            final rTime = _getRoutineTimeFromType(rt, st);
            if (st.difference(rTime).inHours.abs() <= 2) await ns.skipRoutineForToday(rt);
          }
          ns.scheduleReminder(st.millisecondsSinceEpoch ~/ 1000, "JARVIS Reminder", m, st);
          router.memory.addMemory(content: "JARVIS SCHEDULED NOTIFICATION: '$m' at $t.", importance: 0.9, category: 'notification');
        }
      }
    } catch (_) {}
  }

  String? _getRoutineTypeFromPurpose(String purpose) {
    final lower = purpose.toLowerCase();
    if (lower.contains('morning') || lower.contains('06:00') || lower.contains('wake up')) return 'morning';
    if (lower.contains('breakfast') || lower.contains('9:30')) return 'breakfast';
    if (lower.contains('lunch') || lower.contains('13:30')) return 'lunch';
    if (lower.contains('evening') || lower.contains('tea') || lower.contains('18:00')) return 'evening';
    if (lower.contains('dinner') || lower.contains('20:00')) return 'dinner';
    if (lower.contains('sleep') || lower.contains('22:00')) return 'sleep';
    return null;
  }

  DateTime _getRoutineTimeFromType(String type, DateTime relativeTo) {
    int h = 0, m = 0;
    switch (type) {
      case 'morning': h = 6; break;
      case 'breakfast': h = 9; m = 30; break;
      case 'lunch': h = 13; m = 30; break;
      case 'evening': h = 18; break;
      case 'dinner': h = 20; break;
      case 'sleep': h = 22; break;
    }
    return DateTime(relativeTo.year, relativeTo.month, relativeTo.day, h, m);
  }

  String _stripTags(String text) {
    return text
        // Strip any bare <WEB_SEARCH ...> or <tool_code> remnants, preserving the contents within <tool_code>...</tool_code>
        .replaceAll(RegExp(r'<tool_code\b[^>]*>', caseSensitive: false), '')
        .replaceAll(RegExp(r'</tool_code>', caseSensitive: false), '')
        // Strip injected REAL-TIME WEB CONTEXT block (should not appear in output)
        .replaceAll(RegExp(r'\[REAL-TIME WEB CONTEXT[^\]]*\][\s\S]*?\[END REAL-TIME CONTEXT\]', caseSensitive: false), '')
        // Existing tag strips
        .replaceAll(RegExp(r'<think>[\s\S]*?(?:</think>|$)', caseSensitive: false), '')
        .replaceAll(RegExp(r'<SCHEDULE_REMINDER[^>]*>'), '')
        .replaceAll(RegExp(r'<CANCEL_REMINDER[^>]*>'), '')
        .replaceAll(RegExp(r'<SKIP_ROUTINE[^>]*>'), '')
        .replaceAll(RegExp(r'<WEB_SEARCH[^>]*>'), '')
        .replaceAll(RegExp(r'<UPDATE_ROUTINE[^>]*>'), '')
        .replaceAll(RegExp(r'<GENERATE_IMAGE[^>]*>', dotAll: true), '')
        .replaceAll(RegExp(r'<SEARCH_DOCS[^>]*>'), '')
        .replaceAll(RegExp(r'<READ_DOC[^>]*>'), '')
        .replaceAll(RegExp(r'<CREATE_DOC[^>]*>([\s\S]*?)</CREATE_DOC>', dotAll: true), '')
        .replaceAll(RegExp(r'<CREATE_ACADEMIC_REPORT[^>]*>'), '')
        .replaceAll(RegExp(r'<DRAW_DIAGRAM[^>]*>', dotAll: true), '')
        .replaceAll(RegExp(r'<OPEN_INTEGRATION[^>]*>'), '')
        .trim();
  }



  @override
  void dispose() {
    _fileProcessor.dispose();
    super.dispose();
  }
}

