// ignore_for_file: use_build_context_synchronously, unnecessary_underscores
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:jarvis_ai/core/router/ai_router.dart';
import 'package:jarvis_ai/services/tts_service.dart';
import 'package:jarvis_ai/services/skill_service.dart';
import 'agentica_engine.dart';

// ═══════════════════════════════════════════════════════════════════════
//  AGENTICA SCREEN v3 — FIXED UI
//  Zero full rebuilds. 60fps guaranteed. Event batched.
// ═══════════════════════════════════════════════════════════════════════

class AgenticaScreen extends StatefulWidget {
  const AgenticaScreen({super.key});

  @override
  State<AgenticaScreen> createState() => _AgenticaScreenState();
}

class _AgenticaScreenState extends State<AgenticaScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // ── Engine ──────────────────────────────────────────────────────────
  late final AgenticaQueueManager _queueManager;
  late final AgenticaEngine _engine;
  late final TtsService _ttsService;

  // ── Controllers ─────────────────────────────────────────────────────
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _msgListKey = GlobalKey<AnimatedListState>();

  // ── ISOLATED STATE (OpenClaw pattern) ─────────────────────────────
  // Each section has its own ValueNotifier — rebuilds ONLY that section
  final _messagesNotifier = ValueNotifier<List<_Msg>>([]);
  final _statusNotifier = ValueNotifier<_AgentStatus>(_AgentStatus.idle);
  final _confirmNotifier = ValueNotifier<String?>(null);
  final _accessibilityNotifier = ValueNotifier<bool>(false);
  final _statsNotifier = ValueNotifier<_TaskStats>(const _TaskStats());

  // ── Speech ──────────────────────────────────────────────────────────
  final _speech = stt.SpeechToText();
  final _speechStateNotifier = ValueNotifier<_SpeechState>(_SpeechState());

  // ── Animation (isolated) ───────────────────────────────────────────
  late final AnimationController _pulseAnim;
  late final Animation<double> _pulseValue;

  // ── Event Batching (CRITICAL FIX) ───────────────────────────────────
  final _eventBuffer = <AgenticaEvent>[];
  Timer? _eventBatchTimer;
  static const _eventBatchMs = 16; // 1 frame at 60fps

  // ── Constants ───────────────────────────────────────────────────────
  static const _accCh = MethodChannel('jarvis.ai.os/accessibility');

  static const _exampleTasks = [
    'Send a message on WhatsApp',
    'Call someone from contacts',
    'Open YouTube and search something',
    'Take a screenshot and describe it',
    'Open Settings → Wi-Fi',
    'Check my latest Gmail',
    'Search the web for today\'s news',
    'Open Maps and search a location',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Pre-load fonts to avoid first-frame jank
    _preloadFonts();

    // Animation with RepaintBoundary isolation
    _pulseAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseValue = Tween<double>(begin: 0.0, end: 1.0).animate(_pulseAnim);

    // Engine setup
    final router = context.read<AIRouter>();
    final skillService = context.read<SkillService>();
    _ttsService = context.read<TtsService>();
    _engine = AgenticaEngine(router: router, skillService: skillService);
    _queueManager = AgenticaQueueManager(engine: _engine);

    // CRITICAL FIX: Stream with batching — no setState per event
    _engine.events.listen(_onEvent, onError: (_) {});
    _engine.startScheduler();

    // Initial message
    _addMessage(
      const _Msg(
        text:
            '⚡ JARVIS Agentica — Universal Device Agent\n\n'
            'I can autonomously control ANY installed app on your device.\n'
            'I observe your screen, plan actions, and execute them step by step.\n\n'
            'Just describe what you want done — I\'ll figure out the how.',
        isUser: false,
        type: 'info',
      ),
    );

    _initSpeech();
    _checkAccessibilityAsync(); // Non-blocking
  }

  Future<void> _preloadFonts() async {
    await GoogleFonts.pendingFonts([
      GoogleFonts.syne(),
      GoogleFonts.inter(),
      GoogleFonts.jetBrainsMono(),
    ]);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAccessibilityAsync();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseAnim.dispose();
    _eventBatchTimer?.cancel();
    _queueManager.dispose();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _messagesNotifier.dispose();
    _statusNotifier.dispose();
    _confirmNotifier.dispose();
    _accessibilityNotifier.dispose();
    _statsNotifier.dispose();
    _speechStateNotifier.dispose();
    super.dispose();
  }

  // ═════════════════════════════════════════════════════════════════════
  //  EVENT HANDLER — BATCHED (The #1 Fix)
  //  Coalesces rapid events into single frame update
  // ═════════════════════════════════════════════════════════════════════
  void _onEvent(AgenticaEvent e) {
    _eventBuffer.add(e);
    _eventBatchTimer ??= Timer(
      const Duration(milliseconds: _eventBatchMs),
      _flushEvents,
    );
  }

  void _flushEvents() {
    _eventBatchTimer = null;
    if (_eventBuffer.isEmpty) return;

    final messages = List<_Msg>.from(_messagesNotifier.value);
    var status = _statusNotifier.value;
    var confirm = _confirmNotifier.value;
    var stats = _statsNotifier.value;

    for (final e in _eventBuffer) {
      switch (e.type) {
        case 'log':
          messages.add(_Msg(text: e.message, isUser: false, type: 'log'));
          break;
        case 'status':
          final s = e.data['status'] as String? ?? '';
          status = switch (s) {
            'running' => _AgentStatus.running,
            'done' => _AgentStatus.success,
            'failed' => _AgentStatus.error,
            'timeout' => _AgentStatus.error,
            _ => _AgentStatus.idle,
          };
          messages.add(
            _Msg(
              text: e.message,
              isUser: false,
              type: s == 'done'
                  ? 'success'
                  : s == 'failed'
                  ? 'error'
                  : 'status',
            ),
          );
          break;
        case 'tool':
          final tool = e.data['tool'] as String? ?? '';
          final params =
              (e.data['params'] as Map?)?.entries
                  .map((e) => '${e.key}=${e.value}')
                  .join(', ') ??
              '';
          messages.add(
            _Msg(
              text: '🔧 $tool${params.isNotEmpty ? '($params)' : ''}',
              isUser: false,
              type: 'tool',
            ),
          );
          break;
        case 'completed':
          messages.add(
            _Msg(text: '✅ Done: ${e.message}', isUser: false, type: 'success'),
          );
          _ttsService.speak(e.message);
          stats = stats.copyWith(done: stats.done + 1);
          status = _AgentStatus.success;
          break;
        case 'confirmation':
          confirm = e.message;
          messages.add(
            _Msg(text: '❓ ${e.message}', isUser: false, type: 'confirm'),
          );
          _ttsService.speak(e.message);
          break;
      }
    }

    _eventBuffer.clear();

    // ATOMIC UPDATE: Single frame, no rebuild churn
    _messagesNotifier.value = messages;
    _statusNotifier.value = status;
    _confirmNotifier.value = confirm;
    _statsNotifier.value = stats;

    // Animated insertion
    if (messages.length > 1) {
      _msgListKey.currentState?.insertItem(messages.length - 1);
    }
    _scrollBottom();
  }

  void _addMessage(_Msg msg) {
    final current = List<_Msg>.from(_messagesNotifier.value)..add(msg);
    _messagesNotifier.value = current;
    _msgListKey.currentState?.insertItem(current.length - 1);
    _scrollBottom();
  }

  // ═════════════════════════════════════════════════════════════════════
  //  SPEECH — Event-driven, zero polling
  // ═════════════════════════════════════════════════════════════════════
  Future<void> _initSpeech() async {
    try {
      final available = await _speech.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            if (_speechStateNotifier.value.isListening) {
              // Auto-restart if still in listening mode
              Future.delayed(
                const Duration(milliseconds: 100),
                _startListening,
              );
            }
          }
        },
        onError: (err) {
          if (err.errorMsg != 'error_no_match') {
            Future.delayed(const Duration(milliseconds: 200), _startListening);
          }
        },
      );
      _speechStateNotifier.value = _SpeechState(
        available: available,
        isListening: false,
      );
    } catch (_) {}
  }

  void _toggleListening() async {
    final current = _speechStateNotifier.value;
    if (!current.available) return;

    if (current.isListening) {
      await _speech.stop();
      _speechStateNotifier.value = _SpeechState(
        available: true,
        isListening: false,
      );
    } else {
      _speechStateNotifier.value = _SpeechState(
        available: true,
        isListening: true,
      );
      _startListening();
    }
  }

  void _startListening() async {
    if (!_speechStateNotifier.value.isListening) return;
    try {
      await _speech.listen(
        onResult: (result) {
          if (!mounted) return;
          _inputCtrl.text = result.recognizedWords;
          _inputCtrl.selection = TextSelection.fromPosition(
            TextPosition(offset: _inputCtrl.text.length),
          );
          if (result.finalResult && result.recognizedWords.isNotEmpty) {
            _send(result.recognizedWords.trim());
          }
        },
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.dictation,
          cancelOnError: false,
          partialResults: true,
        ),
        localeId: 'en_IN',
      );
    } catch (_) {}
  }

  // ═════════════════════════════════════════════════════════════════════
  //  ACCESSIBILITY — Async, non-blocking
  // ═════════════════════════════════════════════════════════════════════
  Future<void> _checkAccessibilityAsync() async {
    try {
      final result = await _accCh.invokeMethod<String>('takeRefSnapshot');
      _accessibilityNotifier.value = result != null;
    } catch (_) {
      _accessibilityNotifier.value = false;
    }
  }

  void _openAccessibilitySettings() async {
    try {
      await _accCh.invokeMethod('requestAccessibility');
    } catch (_) {
      _showAccessibilityDialog();
    }
    Future.delayed(const Duration(seconds: 3), _checkAccessibilityAsync);
  }

  void _showAccessibilityDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Enable JARVIS Access',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Go to:\nSettings → Accessibility → Installed apps → JARVIS\n\nTurn ON the JARVIS Accessibility Service.',
          style: TextStyle(color: Color(0xFFB0B0C8), height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it', style: TextStyle(color: Colors.amber)),
          ),
        ],
      ),
    );
  }

  void _send(String text) {
    if (text.trim().isEmpty) return;
    _addMessage(_Msg(text: text, isUser: true, type: 'user'));
    _inputCtrl.clear();

    if (_confirmNotifier.value != null) {
      _queueManager.steer(text);
      _confirmNotifier.value = null;
    } else {
      _queueManager.enqueue(text);
      _statusNotifier.value = _AgentStatus.running;
      _statsNotifier.value = _statsNotifier.value.copyWith(
        running: _statsNotifier.value.running + 1,
      );
    }
  }

  void _scrollBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients && _scrollCtrl.position.hasContentDimensions) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutQuad,
        );
      }
    });
  }

  // ═════════════════════════════════════════════════════════════════════
  //  BUILD — Zero full rebuilds. Selective sections only.
  // ═════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07070F),
      body: SafeArea(
        child: Column(
          children: [
            // Header: ONLY rebuilds on status/stats change
            _Header(
              pulseAnimation: _pulseValue,
              statusNotifier: _statusNotifier,
              statsNotifier: _statsNotifier,
              onCancel: _queueManager.cancel,
            ),

            // Accessibility: ONLY rebuilds on permission change
            ValueListenableBuilder<bool>(
              valueListenable: _accessibilityNotifier,
              builder: (_, granted, __) {
                if (granted) return const SizedBox.shrink();
                return _AccessibilityBanner(onTap: _openAccessibilitySettings);
              },
            ),

            // Messages: AnimatedList, isolated rebuilds
            Expanded(
              child: _MessageList(
                listKey: _msgListKey,
                messagesNotifier: _messagesNotifier,
                scrollController: _scrollCtrl,
              ),
            ),

            // Example chips: ONLY shown when idle
            ValueListenableBuilder<_AgentStatus>(
              valueListenable: _statusNotifier,
              builder: (_, status, __) {
                if (status != _AgentStatus.idle) return const SizedBox.shrink();
                return _ExampleChips(tasks: _exampleTasks, onTap: _send);
              },
            ),

            // Input: Isolated with own notifiers
            _InputBar(
              controller: _inputCtrl,
              speechNotifier: _speechStateNotifier,
              confirmNotifier: _confirmNotifier,
              onSend: _send,
              onToggleSpeech: _toggleListening,
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  ISOLATED WIDGETS — Each rebuilds ONLY when its notifier changes
// ═══════════════════════════════════════════════════════════════════════

class _Header extends StatelessWidget {
  final Animation<double> pulseAnimation;
  final ValueNotifier<_AgentStatus> statusNotifier;
  final ValueNotifier<_TaskStats> statsNotifier;
  final VoidCallback onCancel;

  const _Header({
    required this.pulseAnimation,
    required this.statusNotifier,
    required this.statsNotifier,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: const BoxDecoration(
        color: Color(0xFF0A0A18),
        border: Border(bottom: BorderSide(color: Color(0xFF1A1A2E))),
      ),
      child: Row(
        children: [
          // CRITICAL FIX: RepaintBoundary isolates animation
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: pulseAnimation,
              builder: (_, __) {
                return ValueListenableBuilder<_AgentStatus>(
                  valueListenable: statusNotifier,
                  builder: (_, status, __) {
                    final active = status == _AgentStatus.running;
                    return Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: active
                            ? Color.lerp(
                                const Color(0xFF9B88FF),
                                const Color(0xFF6040FF),
                                pulseAnimation.value,
                              )
                            : const Color(0xFF2A2A40),
                        boxShadow: active
                            ? [
                                BoxShadow(
                                  color: const Color(0xFF9B88FF).withAlpha(100),
                                  blurRadius: 8,
                                  spreadRadius: 2,
                                ),
                              ]
                            : null,
                      ),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(width: 10),
          ShaderMask(
            shaderCallback: (b) => const LinearGradient(
              colors: [Color(0xFF9B88FF), Color(0xFF6040FF)],
            ).createShader(b),
            child: Text(
              'AGENTICA',
              style: GoogleFonts.syne(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 2.5,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'Universal Agent',
            style: GoogleFonts.inter(
              fontSize: 10,
              color: Colors.white30,
              fontStyle: FontStyle.italic,
            ),
          ),
          const Spacer(),
          // Stats: ONLY this section rebuilds on stats change
          ValueListenableBuilder<_TaskStats>(
            valueListenable: statsNotifier,
            builder: (_, stats, __) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (stats.running > 0)
                    _Chip(
                      label: '${stats.running} running',
                      color: const Color(0xFF9B88FF),
                    ),
                  if (stats.done > 0)
                    _Chip(
                      label: '${stats.done} done',
                      color: Colors.greenAccent,
                    ),
                  if (stats.failed > 0)
                    _Chip(
                      label: '${stats.failed} failed',
                      color: Colors.redAccent,
                    ),
                ],
              );
            },
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(
              Icons.stop_circle_outlined,
              color: Colors.redAccent,
              size: 20,
            ),
            tooltip: 'Cancel',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;

  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _AccessibilityBanner extends StatelessWidget {
  final VoidCallback onTap;

  const _AccessibilityBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.amber.withAlpha(22),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.amber.withAlpha(100)),
        ),
        child: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                '⚠️ Accessibility permission needed\nTap here → Enable JARVIS in Settings → Accessibility',
                style: TextStyle(
                  color: Colors.amber,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: Colors.amber, size: 18),
          ],
        ),
      ),
    );
  }
}

class _MessageList extends StatelessWidget {
  final GlobalKey<AnimatedListState> listKey;
  final ValueNotifier<List<_Msg>> messagesNotifier;
  final ScrollController scrollController;

  const _MessageList({
    required this.listKey,
    required this.messagesNotifier,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<_Msg>>(
      valueListenable: messagesNotifier,
      builder: (_, messages, __) {
        return AnimatedList(
          key: listKey,
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
          initialItemCount: messages.length,
          itemBuilder: (context, index, animation) {
            return _MessageItem(msg: messages[index], animation: animation);
          },
        );
      },
    );
  }
}

class _MessageItem extends StatelessWidget {
  final _Msg msg;
  final Animation<double> animation;

  const _MessageItem({required this.msg, required this.animation});

  @override
  Widget build(BuildContext context) {
    final widget = msg.isUser ? _buildUserMsg() : _buildAgentMsg();

    return SlideTransition(
      position: animation.drive(
        Tween<Offset>(
          begin: const Offset(0, 0.3),
          end: Offset.zero,
        ).chain(CurveTween(curve: Curves.easeOutQuad)),
      ),
      child: FadeTransition(opacity: animation, child: widget),
    );
  }

  Widget _buildUserMsg() {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8, left: 48),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF9B88FF), Color(0xFF6040FF)],
          ),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(4),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
        ),
        child: Text(
          msg.text,
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildAgentMsg() {
    final (Color accent, IconData icon) = switch (msg.type) {
      'success' => (Colors.greenAccent, Icons.check_circle_outline),
      'error' => (Colors.redAccent, Icons.error_outline),
      'tool' => (const Color(0xFFFFB347), Icons.build_outlined),
      'confirm' => (const Color(0xFF4DD0E1), Icons.help_outline),
      'info' => (const Color(0xFF9B88FF), Icons.auto_awesome),
      'status' => (const Color(0xFF9B88FF), Icons.loop),
      _ => (Colors.white24, Icons.terminal),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 5, right: 40),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 3, right: 7),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: accent.withAlpha(22),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 11, color: accent),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF0E0E1C),
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(14),
                  bottomLeft: Radius.circular(14),
                  bottomRight: Radius.circular(14),
                ),
                border: Border.all(color: accent.withAlpha(35)),
              ),
              child: Text(
                msg.text,
                style: (msg.type == 'log' || msg.type == 'tool')
                    ? GoogleFonts.jetBrainsMono(
                        color: msg.type == 'tool'
                            ? const Color(0xFFFFB347)
                            : Colors.white38,
                        fontSize: 11,
                      )
                    : GoogleFonts.inter(
                        color: Colors.white.withAlpha(220),
                        fontSize: 13,
                        height: 1.45,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExampleChips extends StatelessWidget {
  final List<String> tasks;
  final ValueChanged<String> onTap;

  const _ExampleChips({required this.tasks, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        children: tasks.map((t) {
          return GestureDetector(
            onTap: () => onTap(t),
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF0E0E1C),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF2A2A40)),
              ),
              child: Text(
                t,
                style: GoogleFonts.inter(color: Colors.white54, fontSize: 12),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueNotifier<_SpeechState> speechNotifier;
  final ValueNotifier<String?> confirmNotifier;
  final ValueChanged<String> onSend;
  final VoidCallback onToggleSpeech;

  const _InputBar({
    required this.controller,
    required this.speechNotifier,
    required this.confirmNotifier,
    required this.onSend,
    required this.onToggleSpeech,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
      decoration: const BoxDecoration(
        color: Color(0xFF0A0A18),
        border: Border(top: BorderSide(color: Color(0xFF1A1A2E))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Confirmation banner
          ValueListenableBuilder<String?>(
            valueListenable: confirmNotifier,
            builder: (_, question, __) {
              if (question == null) return const SizedBox.shrink();
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF4DD0E1).withAlpha(18),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFF4DD0E1).withAlpha(70),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.help_outline,
                      size: 13,
                      color: Color(0xFF4DD0E1),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        question,
                        style: GoogleFonts.inter(
                          color: const Color(0xFF4DD0E1),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF0E0E1C),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF2A2A40)),
                  ),
                  child: TextField(
                    controller: controller,
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                    maxLines: 3,
                    minLines: 1,
                    textInputAction: TextInputAction.send,
                    onSubmitted: onSend,
                    decoration: InputDecoration(
                      hintText: 'Tell Agentica what to do...',
                      hintStyle: GoogleFonts.inter(
                        color: Colors.white24,
                        fontSize: 13,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
              ),
              // Speech button
              ValueListenableBuilder<_SpeechState>(
                valueListenable: speechNotifier,
                builder: (_, state, __) {
                  if (!state.available) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: GestureDetector(
                      onTap: onToggleSpeech,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: state.isListening
                              ? const Color(0xFF6040FF).withAlpha(50)
                              : const Color(0xFF0E0E1C),
                          border: Border.all(
                            color: state.isListening
                                ? const Color(0xFF9B88FF)
                                : const Color(0xFF2A2A40),
                            width: 1.5,
                          ),
                        ),
                        child: Center(
                          child: Icon(
                            state.isListening
                                ? Icons.mic_rounded
                                : Icons.mic_none_rounded,
                            color: state.isListening
                                ? const Color(0xFF9B88FF)
                                : Colors.white54,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () => onSend(controller.text),
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF9B88FF), Color(0xFF6040FF)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.send_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  DATA MODELS
// ═══════════════════════════════════════════════════════════════════════

enum _AgentStatus { idle, running, success, error }

class _TaskStats {
  final int running;
  final int done;
  final int failed;

  const _TaskStats({this.running = 0, this.done = 0, this.failed = 0});

  _TaskStats copyWith({int? running, int? done, int? failed}) {
    return _TaskStats(
      running: running ?? this.running,
      done: done ?? this.done,
      failed: failed ?? this.failed,
    );
  }
}

class _SpeechState {
  final bool available;
  final bool isListening;

  const _SpeechState({this.available = false, this.isListening = false});

  _SpeechState copyWith({bool? available, bool? isListening}) {
    return _SpeechState(
      available: available ?? this.available,
      isListening: isListening ?? this.isListening,
    );
  }
}

class _Msg {
  final String text;
  final bool isUser;
  final String type;
  const _Msg({required this.text, required this.isUser, required this.type});
}
