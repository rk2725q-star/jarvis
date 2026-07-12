import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import '../services/video_gen_service.dart';

class VideoGenScreen extends StatefulWidget {
  const VideoGenScreen({super.key});
  @override
  State<VideoGenScreen> createState() => _VideoGenScreenState();
}

class _VideoGenScreenState extends State<VideoGenScreen>
    with TickerProviderStateMixin {
  // ── Form ─────────────────────────────────────────────────────────────────
  final _titleCtrl = TextEditingController(text: 'ARIA Cinematic');
  final _promptCtrl = TextEditingController();

  String _model = 'flux';
  int _duration = 30;
  int _spi = 5;
  String _resolution = '854x480';
  bool _useCustom = false;

  // ── Generation ───────────────────────────────────────────────────────────
  bool _isGenerating = false;
  VideoGenProgress? _progress;
  StreamSubscription? _sub;
  VideoConfig? _lastConfig;

  // ── Slideshow player ─────────────────────────────────────────────────────
  List<String> _frames = [];
  int _frameIndex = 0;
  bool _isPlaying = false;
  Timer? _slideTimer;

  // Cross-fade animation
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  static const _modelOptions = ['flux', 'turbo', 'flux-realism', 'flux-anime'];
  static const _resOptions = ['854x480', '1280x720', '1920x1080'];
  static const _durationOpts = [15, 30, 60, 90, 120];
  static const _spiOpts = [3, 5, 8, 10];

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _slideTimer?.cancel();
    _fadeCtrl.dispose();
    _titleCtrl.dispose();
    _promptCtrl.dispose();
    super.dispose();
  }

  // ── Slideshow controls ────────────────────────────────────────────────────

  void _playSlideshow() {
    if (_frames.isEmpty) return;
    setState(() => _isPlaying = true);
    _scheduleNext();
  }

  void _scheduleNext() {
    _slideTimer?.cancel();
    final holdMs = (_lastConfig?.secondsPerImage ?? 5) * 1000;
    _slideTimer = Timer(Duration(milliseconds: holdMs), _advanceFrame);
  }

  void _advanceFrame() async {
    if (!_isPlaying || _frames.isEmpty) return;
    // Fade out → change frame → fade in
    await _fadeCtrl.reverse();
    if (!mounted) return;
    setState(() {
      _frameIndex = (_frameIndex + 1) % _frames.length;
    });
    await _fadeCtrl.forward();
    if (_isPlaying) _scheduleNext();
  }

  void _pauseSlideshow() {
    _slideTimer?.cancel();
    setState(() => _isPlaying = false);
  }

  void _seekFrame(int idx) {
    _slideTimer?.cancel();
    _fadeCtrl.value = 1.0;
    setState(() => _frameIndex = idx.clamp(0, _frames.length - 1));
    if (_isPlaying) _scheduleNext();
  }

  void _startPlayback(List<String> frames, VideoConfig config) {
    _slideTimer?.cancel();
    _fadeCtrl.value = 1.0;
    setState(() {
      _frames = frames;
      _frameIndex = 0;
      _isPlaying = false;
    });
  }

  // ── Generation ────────────────────────────────────────────────────────────

  void _startGeneration() {
    final res = _resolution.split('x');
    final config = VideoConfig(
      title: _titleCtrl.text.trim().isEmpty
          ? 'ARIA Video'
          : _titleCtrl.text.trim(),
      durationSeconds: _duration,
      secondsPerImage: _spi,
      fps: 24,
      width: int.parse(res[0]),
      height: int.parse(res[1]),
      artStyle: _model,
      baseSeed: DateTime.now().millisecondsSinceEpoch % 9999,
    );
    _lastConfig = config;

    List<VideoScene> scenes = kDefaultVideoScenes;
    if (_useCustom && _promptCtrl.text.trim().isNotEmpty) {
      final lines = _promptCtrl.text
          .trim()
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      scenes = [
        for (int i = 0; i < lines.length; i++)
          VideoScene(
            position: lines.length == 1 ? 0.0 : i / (lines.length - 1),
            prompt: lines[i],
          ),
      ];
    }

    _slideTimer?.cancel();
    setState(() {
      _isGenerating = true;
      _progress = null;
      _frames = [];
      _frameIndex = 0;
      _isPlaying = false;
    });

    _sub?.cancel();
    _sub = VideoGenService()
        .generate(config, scenes)
        .listen(
          (prog) {
            if (!mounted) return;
            setState(() {
              _progress = prog;
              if (prog.isDone) {
                _isGenerating = false;
                _startPlayback(prog.framePaths, config);
              }
              if (prog.isError) _isGenerating = false;
            });
          },
          onError: (e) {
            if (!mounted) return;
            setState(() {
              _isGenerating = false;
              _progress = VideoGenProgress(
                stage: 'error',
                current: 0,
                total: 1,
                message: '❌ $e',
                isError: true,
              );
            });
          },
        );
  }

  void _cancel() {
    _sub?.cancel();
    setState(() => _isGenerating = false);
  }

  // ── Save / Share ──────────────────────────────────────────────────────────

  Future<void> _saveCurrentFrame() async {
    if (_frames.isEmpty) return;
    try {
      await Gal.putImage(_frames[_frameIndex]);
      _snack('✅ Frame saved to Gallery!');
    } catch (e) {
      _snack('❌ Save failed: $e');
    }
  }

  Future<void> _saveAllFrames() async {
    if (_frames.isEmpty) return;
    int saved = 0;
    for (final f in _frames) {
      try {
        await Gal.putImage(f);
        saved++;
      } catch (_) {}
    }
    _snack('✅ $saved frames saved to Gallery!');
  }

  Future<void> _shareFrame() async {
    if (_frames.isEmpty) return;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(_frames[_frameIndex])],
        text: 'JARVIS AI Frame',
      ),
    );
  }

  Future<void> _openFrame() async {
    if (_frames.isEmpty) return;
    await OpenFilex.open(_frames[_frameIndex]);
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: const Color(0xFF1A1A2E)),
    );
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080812),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F1A),
        title: const Row(
          children: [
            Icon(Icons.videocam_rounded, color: Color(0xFF64FFDA), size: 22),
            SizedBox(width: 8),
            Text(
              'Video Generator',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 14),
            _buildConfigCard(),
            const SizedBox(height: 10),
            _buildCustomPromptCard(),
            const SizedBox(height: 14),
            if (_progress != null) ...[
              _buildProgressCard(),
              const SizedBox(height: 10),
            ],
            // ── Slideshow player (shown once frames are ready) ────────────
            if (_frames.isNotEmpty) ...[
              _buildSlideshowPlayer(),
              const SizedBox(height: 10),
              _buildSlideshowActions(),
              const SizedBox(height: 10),
            ],
            _buildGenerateButton(),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  // ── Slideshow player widget ───────────────────────────────────────────────

  Widget _buildSlideshowPlayer() {
    final frame = _frames[_frameIndex];
    final total = _frames.length;
    final spi = _lastConfig?.secondsPerImage ?? 5;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF64FFDA).withValues(alpha: 0.4),
        ),
        color: Colors.black,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // ── Image with cross-fade ──────────────────────────────────────
          AspectRatio(
            aspectRatio: 16 / 9,
            child: FadeTransition(
              opacity: _fadeAnim,
              child: Image.file(
                File(frame),
                fit: BoxFit.cover,
                key: ValueKey(frame),
              ),
            ),
          ),

          // ── Scrub bar ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Column(
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: const Color(0xFF64FFDA),
                    inactiveTrackColor: Colors.white12,
                    thumbColor: const Color(0xFF64FFDA),
                    overlayColor: const Color(
                      0xFF64FFDA,
                    ).withValues(alpha: 0.2),
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                    ),
                    trackHeight: 4,
                  ),
                  child: Slider(
                    value: _frameIndex.toDouble(),
                    min: 0,
                    max: (total - 1).toDouble(),
                    onChanged: (v) => _seekFrame(v.round()),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Frame ${_frameIndex + 1} / $total',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                      ),
                    ),
                    Text(
                      '${_frameIndex * spi}s / ${(total - 1) * spi}s',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Controls ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(left: 8, right: 8, bottom: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(
                    Icons.skip_previous_rounded,
                    color: Colors.white70,
                  ),
                  onPressed: () => _seekFrame(0),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.arrow_back_ios_rounded,
                    color: Colors.white70,
                    size: 20,
                  ),
                  onPressed: () => _seekFrame(_frameIndex - 1),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _isPlaying ? _pauseSlideshow : _playSlideshow,
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF64FFDA),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF64FFDA).withValues(alpha: 0.4),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                    child: Icon(
                      _isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: Colors.black,
                      size: 30,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: Colors.white70,
                    size: 20,
                  ),
                  onPressed: () => _seekFrame(_frameIndex + 1),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.skip_next_rounded,
                    color: Colors.white70,
                  ),
                  onPressed: () => _seekFrame(total - 1),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlideshowActions() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _actionBtn(
                icon: Icons.download_rounded,
                label: 'Save Frame',
                color: const Color(0xFF64FFDA),
                onTap: _saveCurrentFrame,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _actionBtn(
                icon: Icons.photo_library_rounded,
                label: 'Save All',
                color: Colors.deepPurpleAccent,
                onTap: _saveAllFrames,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _actionBtn(
                icon: Icons.share_rounded,
                label: 'Share Frame',
                color: Colors.blueAccent,
                onTap: _shareFrame,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _actionBtn(
                icon: Icons.open_in_new_rounded,
                label: 'Open Image',
                color: Colors.orange,
                onTap: _openFrame,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _actionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(12),
          color: color.withValues(alpha: 0.08),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    final imageCount = (_duration / _spi).ceil();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D1F2D), Color(0xFF001933)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF64FFDA).withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.movie_creation_rounded,
            color: Color(0xFF64FFDA),
            size: 30,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '🎬 AI Video Generator',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$imageCount AI frames via Pollinations → ${_duration}s slideshow',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Config ────────────────────────────────────────────────────────────────

  Widget _buildConfigCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('⚙️ Configuration'),
          const SizedBox(height: 10),
          _inputField(_titleCtrl, 'Video Title', 'e.g. "Cinematic Journey"'),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _dropdown(
                  'Duration (s)',
                  _duration.toString(),
                  _durationOpts.map((d) => '$d').toList(),
                  (v) => setState(() => _duration = int.parse(v!)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _dropdown(
                  'Sec/Frame',
                  _spi.toString(),
                  _spiOpts.map((s) => '$s').toList(),
                  (v) => setState(() => _spi = int.parse(v!)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _dropdown(
                  'AI Model',
                  _model,
                  _modelOptions,
                  (v) => setState(() => _model = v!),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _dropdown(
                  'Resolution',
                  _resolution,
                  _resOptions,
                  (v) => setState(() => _resolution = v!),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: const Color(0xFF64FFDA).withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  color: Color(0xFF64FFDA),
                  size: 14,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${(_duration / _spi).ceil()} frames × ${_spi}s each = ${_duration}s slideshow',
                    style: const TextStyle(
                      color: Color(0xFF64FFDA),
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Custom Prompts ────────────────────────────────────────────────────────

  Widget _buildCustomPromptCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _label('📝 Custom Prompts'),
              Switch(
                value: _useCustom,
                activeThumbColor: const Color(0xFF64FFDA),
                onChanged: (v) => setState(() => _useCustom = v),
              ),
            ],
          ),
          if (_useCustom) ...[
            Text(
              'One prompt per line = one scene.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _promptCtrl,
              maxLines: 5,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText:
                    'Tamil Nadu coastline at dawn, cinematic, 8k\nMeenakshi temple golden hour...',
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.2),
                  fontSize: 11,
                ),
                filled: true,
                fillColor: const Color(0xFF1A1A2E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(
                    color: Color(0xFF64FFDA),
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ] else
            Text(
              'Using built-in 16-scene cinematic progression (sunrise → space)',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.35),
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
            ),
        ],
      ),
    );
  }

  // ── Progress card ─────────────────────────────────────────────────────────

  Widget _buildProgressCard() {
    final prog = _progress!;
    final barColor = prog.isError ? Colors.redAccent : const Color(0xFF64FFDA);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: prog.isError
              ? Colors.redAccent.withValues(alpha: 0.4)
              : const Color(0xFF64FFDA).withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            prog.message.split('\n').first,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          if (prog.message.contains('\n'))
            Text(
              prog.message.split('\n').last,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 11,
              ),
            ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: prog.isDone || prog.isError ? 1.0 : prog.progress,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '${prog.current} / ${prog.total}  •  ${prog.stage}',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }

  // ── Generate button ───────────────────────────────────────────────────────

  Widget _buildGenerateButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: _isGenerating
          ? ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2A0A0A),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.stop_circle, color: Colors.redAccent),
              label: const Text(
                'Cancel',
                style: TextStyle(color: Colors.redAccent, fontSize: 16),
              ),
              onPressed: _cancel,
            )
          : ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF64FFDA),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.videocam, color: Colors.black),
              label: const Text(
                'Generate Video',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              onPressed: _startGeneration,
            ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _label(String t) => Text(
    t,
    style: const TextStyle(
      color: Colors.white,
      fontWeight: FontWeight.w700,
      fontSize: 14,
    ),
  );

  Widget _inputField(TextEditingController ctrl, String label, String hint) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: Color(0xFF64FFDA), fontSize: 13),
        hintStyle: TextStyle(
          color: Colors.white.withValues(alpha: 0.2),
          fontSize: 11,
        ),
        filled: true,
        fillColor: const Color(0xFF1A1A2E),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF64FFDA), width: 1.5),
        ),
      ),
    );
  }

  Widget _dropdown(
    String label,
    String value,
    List<String> opts,
    ValueChanged<String?> onChanged,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: const Color(0xFF1A1A2E),
          style: const TextStyle(color: Colors.white, fontSize: 13),
          items: opts
              .map((o) => DropdownMenuItem(value: o, child: Text(o)))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
