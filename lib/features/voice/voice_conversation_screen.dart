import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:google_fonts/google_fonts.dart';
import '../chat/chat_provider.dart';
import '../../services/notification_service.dart';

class VoiceConversationScreen extends StatefulWidget {
  const VoiceConversationScreen({super.key});

  @override
  State<VoiceConversationScreen> createState() => _VoiceConversationScreenState();
}

class _VoiceConversationScreenState extends State<VoiceConversationScreen> with TickerProviderStateMixin {
  // Speech to Text
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _sttReady = false;
  bool _isListening = false;

  // AI State
  String _liveWords = '';   
  String _lastWords = '';   
  String _aiResponse = '';  
  bool _isThinking = false; 
  bool _isSpeaking = false; 
  bool _processingLock = false;

  // Streaming TTS Pipeline
  final List<String> _ttsQueue = [];
  bool _isTtsActive = false;
  bool _isStreamActive = false;
  final StringBuffer _sentenceBuffer = StringBuffer();

  // Timers
  Timer? _silenceTimer;
  Timer? _heartbeatTimer;
  static const int _silenceMs = 2000; 

  // Animation Controllers
  late AnimationController _pulseCtrl;
  late AnimationController _waveCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _initStt();
    
    // SURGICAL HEARTBEAT: Checks every 1s and wakes the mic ONLY if we are truly in 'User Turn'.
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_speech.isListening && !_isSpeaking && !_isThinking && !_processingLock && !_isTtsActive) {
         _startStt(force: false); 
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final chat = context.read<ChatProvider>();
      chat.ttsService.setHandlers(
        onStart: () {
          // HARDEST STOP: Kill mic immediately to stop 'Output goes to Input' (Echo).
          _stopSttSurgical();
          if (mounted) setState(() => _isSpeaking = true);
        },
        onComplete: () {
          _isTtsActive = false;
          _isSpeaking = false;
          _processTtsQueue();
        },
        onError: (err) {
          _isTtsActive = false;
          _isSpeaking = false;
          _processTtsQueue();
        },
      );
    });
  }

  void _setupAnimations() {
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
    _waveCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.15).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
  }

  Future<void> _initStt() async {
    _sttReady = await _speech.initialize(
      onStatus: (status) {
        if (status == 'notListening' || status == 'done') {
           _isListening = false;
           // Auto-restart if in User Turn and died
           if (!_isSpeaking && !_processingLock && !_isThinking) _startStt();
        }
      },
      onError: (err) {
        _isListening = false;
      },
      debugLogging: false,
    );
    if (_sttReady) _startStt();
  }

  Future<void> _startStt({bool force = false}) async {
    if (!_sttReady || _isSpeaking || _isThinking || _processingLock || _isTtsActive || !mounted) return;
    if (_speech.isListening && !force) return;

    try {
      if (force) await _speech.cancel(); 

      // THE SILENCE STACK: Configuration optimized for 45s+ continuous listening with minimal boops.
      await _speech.listen(
        onResult: (result) {
          // Additional safety check to discard while JARVIS is speaking
          if (_isSpeaking || _processingLock || _isThinking) return;

          final words = result.recognizedWords.trim();
          if (words.isEmpty) return;
          if (mounted) setState(() => _liveWords = words);

          if (words != _lastWords) {
            _lastWords = words;
            _silenceTimer?.cancel();
            _silenceTimer = Timer(const Duration(milliseconds: _silenceMs), () => _onUserFinishedSpeaking(words));
          }
        },
        listenFor: const Duration(hours: 1), 
        pauseFor: const Duration(seconds: 120), // Long window to prevent in-between boops while user speaks
        listenOptions: stt.SpeechListenOptions(
          cancelOnError: false, 
          partialResults: true,
          onDevice: true, // Quieter and faster reactivation
          listenMode: stt.ListenMode.dictation, 
        ),
      );
      if (mounted) setState(() => _isListening = true);
    } catch (_) {
      _isListening = false;
    }
  }

  // Surgical cancel is often quieter than full stop
  Future<void> _stopSttSurgical() async {
    _silenceTimer?.cancel();
    if (_speech.isListening) {
      await _speech.cancel();
    }
    if (mounted) setState(() => _isListening = false);
  }

  Future<void> _onUserFinishedSpeaking(String words) async {
    if (words.isEmpty || _processingLock || !mounted) return;
    
    final chat = context.read<ChatProvider>();
    _processingLock = true;
    _isStreamActive = true;
    _silenceTimer?.cancel();

    // STOP BEFORE THINKING to completely isolate the user input from AI generation.
    await _stopSttSurgical();

    if (mounted) {
      setState(() {
        _liveWords = '';
        _isThinking = true;
        _aiResponse = '';
        _ttsQueue.clear();
        _sentenceBuffer.clear();
      });
    }

    try {
      final fullBuffer = StringBuffer();
      await for (final chunk in chat.sendMessageStream(words, isVoiceMode: true)) {
        if (mounted && _isThinking) setState(() => _isThinking = false);
        fullBuffer.write(chunk);
        _sentenceBuffer.write(chunk);
        if (mounted) setState(() => _aiResponse = fullBuffer.toString());

        String currentText = _sentenceBuffer.toString();
        final wordsInBuf = currentText.trim().split(RegExp(r'\s+'));
        final hasPunctuation = currentText.contains(RegExp(r'[.!?\n]'));
        
        if (hasPunctuation || wordsInBuf.length >= 6) {
           String sentence;
           if (hasPunctuation) {
              final match = RegExp(r'^.*?[.!?\n]').stringMatch(currentText);
              if (match != null) {
                sentence = match.trim();
                _sentenceBuffer.clear();
                _sentenceBuffer.write(currentText.substring(match.length));
              } else {
                sentence = currentText.trim();
                _sentenceBuffer.clear();
              }
           } else {
              sentence = wordsInBuf.take(5).join(' ');
              _sentenceBuffer.clear();
              _sentenceBuffer.write(wordsInBuf.skip(5).join(' '));
           }

           if (sentence.isNotEmpty) {
             _ttsQueue.add(sentence);
             _processTtsQueue();
           }
        }
      }

      _isStreamActive = false;
      String finalChunk = _sentenceBuffer.toString().trim();
      if (finalChunk.isNotEmpty) {
        _ttsQueue.add(finalChunk);
        _sentenceBuffer.clear();
        _processTtsQueue();
      }

      if (fullBuffer.isEmpty) {
        if (mounted) setState(() => _isThinking = false);
        _finishInteraction();
      } else {
        _parseAndScheduleReminders(fullBuffer.toString());
      }
      
    } catch (e) {
      if (mounted) setState(() => _isThinking = false);
      _finishInteraction();
    }
  }

  void _processTtsQueue() {
    if (_isTtsActive || _ttsQueue.isEmpty) {
      if (!_isTtsActive && _ttsQueue.isEmpty && !_isStreamActive) {
        _finishInteraction();
      }
      return;
    }

    _isTtsActive = true;
    String nextSentence = _ttsQueue.removeAt(0);
    final chat = context.read<ChatProvider>();
    chat.ttsService.speak(nextSentence).catchError((_) {
      _isTtsActive = false;
      _processTtsQueue();
    });
  }

  void _parseAndScheduleReminders(String text) {
    try {
      final regex = RegExp(r'<SCHEDULE_REMINDER\s+time="([^"]+)"\s+message="([^"]+)">');
      final matches = regex.allMatches(text);
      for (final match in matches) {
        if (match.groupCount >= 2) {
          final timeStr = match.group(1);
          final msg = match.group(2);
          if (timeStr != null && msg != null) {
            try {
              final scheduleTime = DateTime.parse(timeStr);
              NotificationService().scheduleReminder(
                scheduleTime.millisecondsSinceEpoch ~/ 1000,
                "JARVIS Voice Reminder",
                msg,
                scheduleTime,
              );
              // Store memory of this voice event!
              final chat = context.read<ChatProvider>();
              chat.router.memory.addMemory(
                content: "JARVIS SCHEDULED NOTIFICATION: '\$msg' at \$timeStr. NOTE: Act like a caring human. Check in on them regarding this event, ask how it went, or convey wishes if it's a special occasion like a birthday.",
                importance: 0.9,
                category: 'notification',
              );
            } catch (e) {
              debugPrint("Failed to parse reminder time: \$timeStr");
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Reminder parsing error: \$e");
    }
  }

  void _finishInteraction() {
    _processingLock = false;
    _isTtsActive = false;
    _isStreamActive = false;
    _isSpeaking = false;
    _lastWords = ''; 
    if (mounted) {
      setState(() => _liveWords = '');
      _startStt(force: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF010206), 
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(child: _buildCenter()),
             _buildBottom(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          IconButton(
            onPressed: () => _endCall(),
            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white54, size: 28),
          ),
          const Spacer(),
          Text('JARVIS LIVE', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 8, color: Colors.cyanAccent.withValues(alpha: 0.8))),
          const Spacer(),
          const Icon(Icons.waves_rounded, color: Colors.cyanAccent, size: 22),
        ],
      ),
    );
  }

  Widget _buildCenter() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Spacer(),
        _buildOrb(),
        const SizedBox(height: 48),
        _buildStatusLabel(),
        const SizedBox(height: 32),
        _buildTranscript(),
        const Spacer(),
      ],
    );
  }

  Widget _buildOrb() {
    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (context, child) {
        final Color orbColor = _isSpeaking ? const Color(0xFF00D4FF) : (_isThinking ? const Color(0xFFFFAA00) : (_isListening ? const Color(0xFF00FF88) : Colors.white24));
        return Stack(
          alignment: Alignment.center,
          children: [
            Transform.scale(scale: _pulseAnim.value * 1.3, child: Container(width: 170, height: 170, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: orbColor.withValues(alpha: 0.1), width: 1)))),
            Transform.scale(scale: _pulseAnim.value * 1.1, child: Container(width: 150, height: 150, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: orbColor.withValues(alpha: 0.2), width: 1.5)))),
            Transform.scale(
              scale: (_isListening || _isSpeaking) ? _pulseAnim.value : 1.0,
              child: Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [orbColor.withValues(alpha: 1.0), orbColor.withValues(alpha: 0.4), Colors.transparent], stops: const [0.0, 0.7, 1.0]),
                  boxShadow: [BoxShadow(color: orbColor.withValues(alpha: 0.4), blurRadius: 40, spreadRadius: 10)],
                ),
                child: Center(child: _buildOrbIcon(orbColor)),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildOrbIcon(Color color) {
    if (_isThinking) return SizedBox(width: 32, height: 32, child: CircularProgressIndicator(color: color, strokeWidth: 2.5));
    if (_isSpeaking) return _buildWaveBars(color);
    return Icon(_isListening ? Icons.graphic_eq_rounded : Icons.mic_none_rounded, color: Colors.white, size: 40);
  }

  Widget _buildWaveBars(Color color) {
    return AnimatedBuilder(
      animation: _waveCtrl,
      builder: (context, child) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (i) {
            final heights = [18.0, 32.0, 24.0, 36.0, 20.0];
            final t = (_waveCtrl.value + (i * 0.15)) % 1.0;
            final h = heights[i] * (0.6 + 0.4 * (t < 0.5 ? t * 2 : (1 - t) * 2));
            return Container(margin: const EdgeInsets.symmetric(horizontal: 2.5), width: 5, height: h, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)));
          }),
        );
      },
    );
  }

  Widget _buildStatusLabel() {
    String label = _isThinking ? 'AGENT THINKING' : (_isSpeaking ? 'JARVIS SPEAKING' : (_isListening ? 'LISTENING LIVE' : 'CONNECTING...'));
    Color color = _isThinking ? Colors.orange : (_isSpeaking ? Colors.cyanAccent : (_isListening ? Colors.greenAccent : Colors.grey));
    return Text(label, style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 4, color: color));
  }

  Widget _buildTranscript() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        children: [
          if (_liveWords.isNotEmpty) Text('"$_liveWords"', textAlign: TextAlign.center, style: GoogleFonts.notoSans(fontSize: 17, fontStyle: FontStyle.italic, color: Colors.greenAccent, fontWeight: FontWeight.w500)),
          if (_aiResponse.isNotEmpty) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.02), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withValues(alpha: 0.05))),
              child: Text(
                _aiResponse, 
                textAlign: TextAlign.center, 
                maxLines: 4, 
                style: GoogleFonts.notoSans(
                  fontSize: 15, 
                  color: Colors.white.withValues(alpha: 0.9), 
                  height: 1.6,
                  fontWeight: FontWeight.w500,
                )
              ),
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildBottom() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 60),
      child: InkWell(
        onTap: _endCall,
        child: Column(
          children: [
            Container(width: 72, height: 72, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.redAccent, boxShadow: [BoxShadow(color: Colors.redAccent.withValues(alpha: 0.3), blurRadius: 20, spreadRadius: 5)]), child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 34)),
            const SizedBox(height: 12),
            Text('END CALL', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white54, letterSpacing: 3)),
          ],
        ),
      ),
    );
  }

  void _endCall() async {
    final chat = context.read<ChatProvider>();
    _silenceTimer?.cancel();
    _heartbeatTimer?.cancel();
    await _stopSttSurgical();
    await chat.ttsService.stop();
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _silenceTimer?.cancel();
    _heartbeatTimer?.cancel();
    _pulseCtrl.dispose();
    _waveCtrl.dispose();
    super.dispose();
  }
}
