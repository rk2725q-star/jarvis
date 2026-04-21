// ignore_for_file: use_build_context_synchronously, unnecessary_underscores
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────────────
const _kApiKey = 'AIzaSyDvbzjTZWJLZLK4QJ2t14t7PlcB72wqO1w';
const _kBase   = 'https://www.googleapis.com/youtube/v3';

// ─────────────────────────────────────────────────────────────────────────────
// Data Models
// ─────────────────────────────────────────────────────────────────────────────
class YtVideo {
  final String id, title, channelTitle, thumbnail, duration, viewCount, publishedAt;
  const YtVideo({
    required this.id, required this.title, required this.channelTitle,
    required this.thumbnail, required this.duration, required this.viewCount,
    required this.publishedAt,
  });

  factory YtVideo.fromSearch(Map<String, dynamic> item, Map<String, dynamic>? details) {
    final snippet = item['snippet'] as Map? ?? {};
    final stats   = details?['statistics'] as Map? ?? {};
    final cd      = details?['contentDetails'] as Map? ?? {};
    return YtVideo(
      id: (item['id'] is Map ? item['id']['videoId'] : item['id']) as String? ?? '',
      title: snippet['title'] as String? ?? '',
      channelTitle: snippet['channelTitle'] as String? ?? '',
      thumbnail: (snippet['thumbnails'] as Map? ?? {})
          .cast<String, dynamic>()
          .entries
          .lastOrNull
          ?.value['url'] as String? ?? '',
      duration: _fmtDuration(cd['duration'] as String? ?? ''),
      viewCount: _fmtViews(stats['viewCount'] as String? ?? ''),
      publishedAt: _fmtAge(snippet['publishedAt'] as String? ?? ''),
    );
  }
}

String _fmtDuration(String iso) {
  if (iso.isEmpty) return '';
  final r = RegExp(r'PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?');
  final m = r.firstMatch(iso);
  if (m == null) return '';
  final h = int.tryParse(m.group(1) ?? '0') ?? 0;
  final min = int.tryParse(m.group(2) ?? '0') ?? 0;
  final s = int.tryParse(m.group(3) ?? '0') ?? 0;
  if (h > 0) return '$h:${min.toString().padLeft(2,'0')}:${s.toString().padLeft(2,'0')}';
  return '$min:${s.toString().padLeft(2,'0')}';
}

String _fmtViews(String v) {
  final n = int.tryParse(v) ?? 0;
  if (n >= 1000000000) return '${(n/1000000000).toStringAsFixed(1)}B views';
  if (n >= 1000000)    return '${(n/1000000).toStringAsFixed(1)}M views';
  if (n >= 1000)       return '${(n/1000).toStringAsFixed(0)}K views';
  return '$n views';
}

String _fmtAge(String iso) {
  if (iso.isEmpty) return '';
  try {
    final d = DateTime.parse(iso);
    final diff = DateTime.now().difference(d);
    if (diff.inDays > 365) return '${(diff.inDays/365).toInt()} years ago';
    if (diff.inDays > 30)  return '${(diff.inDays/30).toInt()} months ago';
    if (diff.inDays > 0)   return '${diff.inDays} days ago';
    if (diff.inHours > 0)  return '${diff.inHours} hours ago';
    return '${diff.inMinutes} minutes ago';
  } catch (_) { return ''; }
}

// ─────────────────────────────────────────────────────────────────────────────
// YouTube API Client
// ─────────────────────────────────────────────────────────────────────────────
class _YtApi {
  static Future<List<YtVideo>> search(String query) async {
    final searchUrl = '$_kBase/search?part=snippet&type=video&maxResults=25'
        '&q=${Uri.encodeComponent(query)}&key=$_kApiKey';
    final r = await http.get(Uri.parse(searchUrl));
    if (r.statusCode != 200) return [];
    final items = (json.decode(r.body)['items'] as List? ?? []).cast<Map<String, dynamic>>();
    final ids = items.map((e) => (e['id'] as Map)['videoId'] as String).join(',');
    return _fetchWithDetails(items, ids);
  }

  static Future<List<YtVideo>> popular({String? pageToken}) async {
    final url = '$_kBase/videos?part=snippet,statistics,contentDetails'
        '&chart=mostPopular&regionCode=IN&maxResults=30'
        '${pageToken != null ? "&pageToken=$pageToken" : ""}&key=$_kApiKey';
    final r = await http.get(Uri.parse(url));
    if (r.statusCode != 200) return [];
    final items = (json.decode(r.body)['items'] as List? ?? []).cast<Map<String, dynamic>>();
    return items.map((item) => YtVideo.fromSearch(
        {'id': item['id'], 'snippet': item['snippet']}, item)).toList();
  }

  static Future<List<YtVideo>> _fetchWithDetails(
      List<Map<String, dynamic>> items, String ids) async {
    final detUrl = '$_kBase/videos?part=statistics,contentDetails&id=$ids&key=$_kApiKey';
    final dr = await http.get(Uri.parse(detUrl));
    final Map<String, Map<String, dynamic>> detMap = {};
    if (dr.statusCode == 200) {
      for (var d in (json.decode(dr.body)['items'] as List? ?? [])) {
        detMap[d['id'] as String] = d as Map<String, dynamic>;
      }
    }
    return items.map((item) {
      final vid = (item['id'] as Map)['videoId'] as String;
      return YtVideo.fromSearch(item, detMap[vid]);
    }).where((v) => v.id.isNotEmpty).toList();
  }

  static Future<List<YtVideo>> suggestions(String videoId) async {
    final url = '$_kBase/search?part=snippet&type=video&maxResults=15'
        '&relatedToVideoId=$videoId&key=$_kApiKey';
    final r = await http.get(Uri.parse(url));
    if (r.statusCode != 200) return [];
    final items = (json.decode(r.body)['items'] as List? ?? [])
        .cast<Map<String, dynamic>>()
        .where((e) => (e['id'] as Map? ?? {})['videoId'] != null)
        .toList();
    if (items.isEmpty) return [];
    final ids = items.map((e) => (e['id'] as Map)['videoId'] as String).join(',');
    return _fetchWithDetails(items, ids);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Background Audio Player (youtube_explode_dart + just_audio)
// ─────────────────────────────────────────────────────────────────────────────
class _BgAudio {
  static final _yt = YoutubeExplode();
  static final player = AudioPlayer();

  static Future<void> play(String videoId, String title) async {
    try {
      final manifest = await _yt.videos.streamsClient.getManifest(videoId);
      final audio = manifest.audioOnly.withHighestBitrate();
      await player.setAudioSource(AudioSource.uri(Uri.parse(audio.url.toString())));
      await player.play();
    } catch (e) {
      debugPrint('BgAudio error: $e');
    }
  }

  static Future<void> stop() async {
    await player.stop();
  }

  static bool get isPlaying => player.playing;
}

// ─────────────────────────────────────────────────────────────────────────────
// Main YouTube Screen
// ─────────────────────────────────────────────────────────────────────────────
class YouTubeScreen extends StatefulWidget {
  const YouTubeScreen({super.key});

  @override
  State<YouTubeScreen> createState() => _YouTubeScreenState();
}

class _YouTubeScreenState extends State<YouTubeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _searchCtrl = TextEditingController();
  bool _searching = false;

  List<YtVideo> _home = [];
  List<YtVideo> _searchResults = [];
  bool _homeLoading = true;
  bool _searchLoading = false;

  // Mini-player
  YtVideo? _nowPlaying;
  bool _miniVisible = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _loadHome();
  }

  Future<void> _loadHome() async {
    setState(() => _homeLoading = true);
    final vids = await _YtApi.popular();
    if (mounted) setState(() { _home = vids; _homeLoading = false; });
  }

  Future<void> _doSearch(String q) async {
    if (q.trim().isEmpty) return;
    setState(() { _searchLoading = true; _searchResults = []; });
    final vids = await _YtApi.search(q);
    if (mounted) setState(() { _searchResults = vids; _searchLoading = false; });
  }

  void _openVideo(YtVideo v) {
    setState(() { _nowPlaying = v; _miniVisible = false; });
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (_, __, a3) => _VideoPage(
          video: v,
          onMinimize: (vid) {
            setState(() { _nowPlaying = vid; _miniVisible = true; });
          },
        ),
        transitionsBuilder: (_, anim, a3, child) =>
            SlideTransition(position: Tween(begin: const Offset(0, 1), end: Offset.zero)
                .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)), child: child),
      ),
    );
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: Column(children: [
        _buildTopBar(),
        Expanded(child: Stack(children: [
          TabBarView(controller: _tabs, children: [
            _HomeTab(videos: _home, loading: _homeLoading, onTap: _openVideo),
            _SearchTab(
              ctrl: _searchCtrl,
              results: _searchResults,
              loading: _searchLoading,
              onSearch: _doSearch,
              onTap: _openVideo,
            ),
          ]),
          if (_miniVisible && _nowPlaying != null)
            _MiniPlayer(
              video: _nowPlaying!,
              onExpand: () {
                setState(() => _miniVisible = false);
                _openVideo(_nowPlaying!);
              },
              onClose: () => setState(() { _miniVisible = false; _BgAudio.stop(); }),
            ),
        ])),
        _buildTabBar(),
      ]),
    );
  }

  Widget _buildTopBar() {
    return SafeArea(
      bottom: false,
      child: Container(
        color: const Color(0xFF0F0F0F),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          // YouTube logo
          const _YTLogo(),
          const Spacer(),
          if (!_searching) ...[
            IconButton(
              icon: const Icon(Icons.search, color: Colors.white, size: 26),
              onPressed: () {
                setState(() { _searching = true; _tabs.animateTo(1); });
              },
            ),
            IconButton(
              icon: const Icon(Icons.notifications_none, color: Colors.white, size: 26),
              onPressed: () {},
            ),
            const CircleAvatar(
              radius: 14,
              backgroundColor: Color(0xFF6C63FF),
              child: Icon(Icons.person, size: 16, color: Colors.white),
            ),
          ] else ...[
            Expanded(child: Container(
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFF222222),
                borderRadius: BorderRadius.circular(4),
              ),
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                decoration: const InputDecoration(
                  hintText: 'Search YouTube',
                  hintStyle: TextStyle(color: Colors.white38),
                  border: InputBorder.none,
                  prefixIcon: Icon(Icons.search, color: Colors.white38, size: 20),
                  contentPadding: EdgeInsets.symmetric(vertical: 9),
                ),
                onSubmitted: (q) { _doSearch(q); },
                textInputAction: TextInputAction.search,
              ),
            )),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => setState(() { _searching = false; _searchCtrl.clear(); }),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF3EA6FF), fontSize: 14)),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: const Color(0xFF111111),
      child: TabBar(
        controller: _tabs,
        indicatorColor: Colors.transparent,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white38,
        tabs: const [
          Tab(icon: Icon(Icons.home_outlined), text: 'Home'),
          Tab(icon: Icon(Icons.search), text: 'Search'),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Home Tab
// ─────────────────────────────────────────────────────────────────────────────
class _HomeTab extends StatelessWidget {
  final List<YtVideo> videos;
  final bool loading;
  final void Function(YtVideo) onTap;

  const _HomeTab({required this.videos, required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFFF0000)));
    }
    if (videos.isEmpty) {
      return const Center(child: Text('Could not load feed', style: TextStyle(color: Colors.white38)));
    }
    // Category chips
    final cats = ['All', 'Music', 'Gaming', 'News', 'Sports', 'Live', 'Tech', 'Movies'];
    return CustomScrollView(slivers: [
      SliverToBoxAdapter(child: SizedBox(
        height: 44,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          itemCount: cats.length,
          itemBuilder: (_, i) => Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _Chip(label: cats[i], selected: i == 0),
          ),
        ),
      )),
      SliverList(delegate: SliverChildBuilderDelegate(
        (_, i) => _VideoCard(video: videos[i], onTap: () => onTap(videos[i])),
        childCount: videos.length,
      )),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Search Tab
// ─────────────────────────────────────────────────────────────────────────────
class _SearchTab extends StatelessWidget {
  final TextEditingController ctrl;
  final List<YtVideo> results;
  final bool loading;
  final void Function(String) onSearch;
  final void Function(YtVideo) onTap;

  const _SearchTab({
    required this.ctrl, required this.results, required this.loading,
    required this.onSearch, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFFF0000)));
    }
    if (results.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.search, size: 64, color: Colors.white12),
        const SizedBox(height: 12),
        const Text('Search for videos, channels, playlists',
            style: TextStyle(color: Colors.white38, fontSize: 14)),
      ]));
    }
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (_, i) => _VideoCard(video: results[i], onTap: () => onTap(results[i]), horizontal: true),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Video Card
// ─────────────────────────────────────────────────────────────────────────────
class _VideoCard extends StatelessWidget {
  final YtVideo video;
  final VoidCallback onTap;
  final bool horizontal;

  const _VideoCard({required this.video, required this.onTap, this.horizontal = false});

  @override
  Widget build(BuildContext context) {
    if (horizontal) {
      return InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            // Thumbnail
            Stack(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: _Thumb(url: video.thumbnail, w: 160, h: 90),
              ),
              if (video.duration.isNotEmpty)
                Positioned(bottom: 4, right: 4,
                    child: _DurationBadge(video.duration)),
            ]),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(video.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              Text('${video.channelTitle} • ${video.viewCount}',
                  style: const TextStyle(color: Colors.white60, fontSize: 12)),
            ])),
          ]),
        ),
      );
    }
    // Vertical card (home feed)
    return InkWell(
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Thumbnail
        Stack(children: [
          _Thumb(url: video.thumbnail, w: double.infinity, h: 210),
          if (video.duration.isNotEmpty)
            Positioned(bottom: 8, right: 8,
                child: _DurationBadge(video.duration)),
        ]),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const CircleAvatar(
              radius: 18,
              backgroundColor: Color(0xFF333333),
              child: Icon(Icons.person, size: 18, color: Colors.white60),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(video.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
              const SizedBox(height: 3),
              Text('${video.channelTitle} • ${video.viewCount} • ${video.publishedAt}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ])),
            IconButton(
              icon: const Icon(Icons.more_vert, color: Colors.white54, size: 20),
              onPressed: () {},
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Video Player Page
// ─────────────────────────────────────────────────────────────────────────────
class _VideoPage extends StatefulWidget {
  final YtVideo video;
  final void Function(YtVideo) onMinimize;

  const _VideoPage({required this.video, required this.onMinimize});

  @override
  State<_VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<_VideoPage> {
  final _yt = YoutubeExplode();
  VideoPlayerController? _vpc;
  bool _loading = true;
  bool _error = false;
  bool _audioOnly = false;   // fallback if no video stream
  bool _controlsVisible = true;
  Timer? _hideTimer;
  List<YtVideo> _suggestions = [];

  String _description = '';
  bool _descExpanded = false;

  @override
  void initState() {
    super.initState();
    _initPlayer();
    _loadMeta();
    _loadSuggestions();
  }

  Future<void> _initPlayer() async {
    setState(() { _loading = true; _error = false; });
    try {
      final manifest = await _yt.videos.streamsClient.getManifest(widget.video.id);

      // Try to get muxed (video+audio) stream first
      final muxed = manifest.muxed;
      if (muxed.isNotEmpty) {
        final stream = muxed.withHighestBitrate();
        _vpc = VideoPlayerController.networkUrl(Uri.parse(stream.url.toString()));
        await _vpc!.initialize();
        await _vpc!.play();
        setState(() => _loading = false);
        _scheduleHide();
        return;
      }

      // Fallback: audio-only via just_audio
      setState(() { _audioOnly = true; });
      await _BgAudio.play(widget.video.id, widget.video.title);
      setState(() => _loading = false);
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = true; });
    }
  }

  Future<void> _loadMeta() async {
    try {
      final v = await _yt.videos.get(widget.video.id);
      if (mounted) setState(() => _description = v.description);
    } catch (_) {}
  }

  Future<void> _loadSuggestions() async {
    final s = await _YtApi.suggestions(widget.video.id);
    if (mounted) setState(() => _suggestions = s);
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide();
  }

  void _minimize() {
    // Keep audio playing in background
    _vpc?.pause();
    _BgAudio.play(widget.video.id, widget.video.title);
    widget.onMinimize(widget.video);
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _vpc?.dispose();
    _yt.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: SafeArea(
        child: Column(children: [
          // ── Video Player ────────────────────────────────────────────────
          _buildPlayer(),

          // ── Scrollable content ─────────────────────────────────────────
          Expanded(child: CustomScrollView(slivers: [
            // Title + meta
            SliverToBoxAdapter(child: _buildMeta()),
            // Action bar
            SliverToBoxAdapter(child: _buildActions()),
            // Description
            SliverToBoxAdapter(child: _buildDescription()),
            const SliverToBoxAdapter(child: Divider(color: Colors.white12, height: 1)),
            // Up Next / suggestions
            SliverToBoxAdapter(child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Text('Up next', style: TextStyle(color: Colors.white.withAlpha(200),
                  fontSize: 15, fontWeight: FontWeight.w600)),
            )),
            if (_suggestions.isEmpty)
              const SliverToBoxAdapter(child: Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator(color: Color(0xFFFF0000), strokeWidth: 2)),
              ))
            else
              SliverList(delegate: SliverChildBuilderDelegate(
                (_, i) => _VideoCard(
                  video: _suggestions[i],
                  onTap: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => _VideoPage(video: _suggestions[i], onMinimize: widget.onMinimize)),
                  ),
                  horizontal: true,
                ),
                childCount: _suggestions.length,
              )),
          ])),
        ]),
      ),
    );
  }

  Widget _buildPlayer() {
    final w = MediaQuery.of(context).size.width;
    final h = w * 9 / 16;
    return GestureDetector(
      onTap: _toggleControls,
      child: Container(
        width: w, height: h,
        color: Colors.black,
        child: Stack(alignment: Alignment.center, children: [
          // Video frame or audio art
          if (_loading)
            const CircularProgressIndicator(color: Color(0xFFFF0000))
          else if (_error)
            Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 40),
              const SizedBox(height: 8),
              const Text('Could not load video', style: TextStyle(color: Colors.white70)),
              TextButton(onPressed: _initPlayer, child: const Text('Retry', style: TextStyle(color: Color(0xFF3EA6FF)))),
            ])
          else if (_audioOnly)
            Column(mainAxisSize: MainAxisSize.min, children: [
              _Thumb(url: widget.video.thumbnail, w: w, h: h),
              Positioned.fill(child: Container(color: Colors.black54)),
            ])
          else if (_vpc != null && _vpc!.value.isInitialized)
            AspectRatio(aspectRatio: _vpc!.value.aspectRatio,
                child: VideoPlayer(_vpc!)),

          // Controls overlay
          if (_controlsVisible && !_loading && !_error)
            _buildControls(w, h),

          // Minimize button
          Positioned(
            top: 8, left: 8,
            child: GestureDetector(
              onTap: _minimize,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 22),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildControls(double w, double h) {
    final playing = _audioOnly ? _BgAudio.isPlaying : (_vpc?.value.isPlaying ?? false);
    return AnimatedOpacity(
      opacity: _controlsVisible ? 1 : 0,
      duration: const Duration(milliseconds: 200),
      child: Container(
        width: w, height: h,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.black54, Colors.transparent, Colors.black54],
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
          ),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const SizedBox(),
          // Center play/pause
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(onPressed: () {
              if (_audioOnly) {
                if (_BgAudio.isPlaying) { _BgAudio.player.pause(); }
                else { _BgAudio.player.play(); }
              } else {
                if (_vpc!.value.isPlaying) { _vpc!.pause(); } else { _vpc!.play(); }
              }
              setState(() {});
              _scheduleHide();
            },
              icon: Icon(playing ? Icons.pause_circle_filled : Icons.play_circle_filled,
                  color: Colors.white, size: 60),
            ),
          ]),
          // Progress bar
          if (!_audioOnly && _vpc != null)
            VideoProgressIndicator(_vpc!,
              allowScrubbing: true,
              colors: const VideoProgressColors(
                playedColor: Color(0xFFFF0000),
                backgroundColor: Colors.white24,
                bufferedColor: Colors.white38,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            )
          else
            const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Widget _buildMeta() => Padding(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(widget.video.title,
          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Text('${widget.video.viewCount} • ${widget.video.publishedAt}',
          style: const TextStyle(color: Colors.white54, fontSize: 13)),
    ]),
  );

  Widget _buildActions() {
    final items = [
      (Icons.thumb_up_outlined, 'Like'),
      (Icons.thumb_down_outlined, 'Dislike'),
      (Icons.share_outlined, 'Share'),
      (Icons.download_outlined, 'Save'),
      (Icons.playlist_add, 'Save'),
    ];
    return SizedBox(
      height: 72,
      child: ListView(scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: items.map((e) => _ActionBtn(e.$1, e.$2)).toList()),
    );
  }

  Widget _buildDescription() {
    if (_description.isEmpty) return const SizedBox(height: 8);
    final short = _description.length > 120 ? _description.substring(0, 120) : _description;
    return GestureDetector(
      onTap: () => setState(() => _descExpanded = !_descExpanded),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_descExpanded ? _description : short,
                style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5)),
            const SizedBox(height: 6),
            Text(_descExpanded ? 'Show less' : 'Show more',
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Mini Player (background audio)
// ─────────────────────────────────────────────────────────────────────────────
class _MiniPlayer extends StatefulWidget {
  final YtVideo video;
  final VoidCallback onExpand;
  final VoidCallback onClose;

  const _MiniPlayer({required this.video, required this.onExpand, required this.onClose});

  @override
  State<_MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<_MiniPlayer> {
  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: GestureDetector(
        onTap: widget.onExpand,
        child: Container(
          height: 68,
          decoration: const BoxDecoration(
            color: Color(0xFF222222),
            border: Border(top: BorderSide(color: Color(0xFF333333))),
          ),
          child: Row(children: [
            // Thumbnail
            ClipRRect(
              child: _Thumb(url: widget.video.thumbnail, w: 100, h: 68),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(widget.video.title,
                maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 12))),
            // Play/Pause
            StreamBuilder<PlayerState>(
              stream: _BgAudio.player.playerStateStream,
              builder: (_, snap) {
                final playing = snap.data?.playing ?? false;
                return IconButton(
                  icon: Icon(playing ? Icons.pause : Icons.play_arrow, color: Colors.white),
                  onPressed: () {
            if (playing) { _BgAudio.player.pause(); } else { _BgAudio.player.play(); }
                    setState(() {});
                  },
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white54),
              onPressed: widget.onClose,
            ),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable Widgets
// ─────────────────────────────────────────────────────────────────────────────
class _YTLogo extends StatelessWidget {
  const _YTLogo();

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(
      width: 30, height: 21,
      decoration: BoxDecoration(
        color: const Color(0xFFFF0000),
        borderRadius: BorderRadius.circular(5),
      ),
      child: const Center(child: Icon(Icons.play_arrow, color: Colors.white, size: 18)),
    ),
    const SizedBox(width: 5),
    const Text('YouTube', style: TextStyle(color: Colors.white,
        fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
  ]);
}

class _Thumb extends StatelessWidget {
  final String url;
  final double w, h;

  const _Thumb({required this.url, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return Container(width: w, height: h, color: const Color(0xFF1A1A1A),
          child: const Icon(Icons.videocam, color: Colors.white24));
    }
    return Image.network(
      url,
      width: w, height: h, fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
          width: w, height: h, color: const Color(0xFF1A1A1A),
          child: const Icon(Icons.broken_image, color: Colors.white24)),
    );
  }
}

class _DurationBadge extends StatelessWidget {
  final String dur;
  const _DurationBadge(this.dur);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
    decoration: BoxDecoration(
      color: Colors.black87,
      borderRadius: BorderRadius.circular(3),
    ),
    child: Text(dur, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
  );
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  const _Chip({required this.label, this.selected = false});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    decoration: BoxDecoration(
      color: selected ? Colors.white : const Color(0xFF272727),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(label, style: TextStyle(
      color: selected ? Colors.black : Colors.white,
      fontSize: 13, fontWeight: FontWeight.w500,
    )),
  );
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  const _ActionBtn(this.icon, this.label);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF272727),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 13)),
        ]),
      ),
    ]),
  );
}
