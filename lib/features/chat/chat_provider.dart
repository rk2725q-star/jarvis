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
import 'package:jarvis_ai/features/diagram/diagram_service.dart';
import 'package:jarvis_ai/features/integrations/integrations_model.dart';
import 'package:jarvis_ai/features/integrations/integrations_provider.dart';

class ChatProvider extends ChangeNotifier {
  final AIRouter router;
  final SessionService sessionService;
  final TtsService ttsService;
  final IntegrationsProvider integrationsProvider;
  final FileProcessor _fileProcessor = FileProcessor();
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
    final recentHistory = _messages.where((m) => !m.isStreaming).toList();
    // Get last 6 messages to provide immediate conversational context
    final recentMemories = recentHistory.length > 6 ? recentHistory.sublist(recentHistory.length - 6) : recentHistory;
    
    if (recentMemories.isNotEmpty) {
      final historyStr = recentMemories.map((m) {
        final str = m.content;
        // Truncate ultra-long individual messages to 30000 chars, but this still allows large pastes to remain in short-term memory
        final displayStr = str.length > 30000 ? '${str.substring(0, 30000)}\n\n...(TRUNCATED FOR MEMORY)...' : str;
        return '${m.isUser ? "USER" : "JARVIS"}:\n$displayStr';
      }).join('\n\n---\n\n');
      
      String finalHistory = historyStr;
      // Cap entire injected short-term context to ~60000 chars to avoid model overflow for standard APIs
      if (finalHistory.length > 60000) {
        finalHistory = "...\n${finalHistory.substring(finalHistory.length - 60000)}";
      }
      combinedText = "[RECENT CHAT HISTORY]\n$finalHistory\n\n[CURRENT USER QUERY]\n$combinedText";
    }

    // ── 1. Set Status ────────────────────────
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

    // Add user message — store ORIGINAL text only (not the history-injected combinedText)
    // combinedText (with [RECENT CHAT HISTORY]) is only sent to the AI, never displayed
    final displayText = text.isEmpty ? "Analyzed attached files" : text.trim();
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

    if (userMsg.provider != null && userMsg.provider!.isNotEmpty) {
      // The user mentioned an integration. Render the UI card only! No jarvis text.
      _setAnalysisStatus("thinking...", active: false);
      notifyListeners();
      return;
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
      await for (final chunk in router.generateStream(
        combinedText,
        // CRITICAL FIX: Only pass integration capabilities when user explicitly
        // @mentioned an integration. Passing capabilitySystemPrompt to ALL messages
        // was causing JARVIS to autonomously open integrations without user request.
        integrationCapabilities: atIntegrationCapability ?? '',
      )) {
        buffer.write(chunk);
        final idx = _messages.indexWhere((m) => m.id == aiMsg.id);
        if (idx != -1) {
          final displayContent = _stripTags(buffer.toString());
          _messages[idx] = aiMsg.copyWith(
            content: displayContent,
            provider: router.activeProvider?.name,
            model: router.activeModel,
            isStreaming: true,
          );
          notifyListeners();
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
      notifyListeners();
    }

    // Mark as done (Rule 3: SILENT TAG BEHAVIOR - strip tags before display/storage)
    final idx = _messages.indexWhere((m) => m.id == aiMsg.id);
    if (idx != -1) {
      final cleanText = _stripTags(buffer.toString());
      final finalMsg = _messages[idx].copyWith(
        content: cleanText,
        isStreaming: false,
        tokenCount: _estimateTokenCount(cleanText),
      );
      _messages[idx] = finalMsg;
      await sessionService.addMessage(finalMsg);
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
