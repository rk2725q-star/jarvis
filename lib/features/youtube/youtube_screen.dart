// ignore_for_file: use_build_context_synchronously, unnecessary_underscores, deprecated_member_use, dead_code, dead_null_aware_expression
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Shared YoutubeExplode instance (uses YouTube Innertube API — no key needed)
// ─────────────────────────────────────────────────────────────────────────────
final _yt = YoutubeExplode();
const _kSprefsKey = 'yt_subscriptions';

// ─────────────────────────────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────────────────────────────
class YtVid {
  final String id, title, channel, channelId, thumb, duration, viewCount, age;
  const YtVid({
    required this.id, required this.title, required this.channel,
    required this.channelId, required this.thumb, required this.duration,
    this.viewCount = '', this.age = '',
  });

  factory YtVid.fromVideo(Video v) => YtVid(
    id: v.id.value,
    title: v.title,
    channel: v.author,
    channelId: v.channelId.value,
    thumb: 'https://i.ytimg.com/vi/${v.id.value}/mqdefault.jpg',
    duration: _fmtDur(v.duration),
    viewCount: _fmtViews(v.engagement.viewCount ?? 0),
    age: _fmtAge(v.uploadDate),
  );

  factory YtVid.fromPlaylist(Video v) => YtVid(
    id: v.id.value,
    title: v.title,
    channel: v.author,
    channelId: v.channelId.value,
    thumb: 'https://i.ytimg.com/vi/${v.id.value}/mqdefault.jpg',
    duration: _fmtDur(v.duration),
    viewCount: _fmtViews(v.engagement.viewCount ?? 0),
    age: _fmtAge(v.uploadDate),
  );
}

class YtChannel {
  final String id, name, thumb, subs;
  const YtChannel({required this.id, required this.name, required this.thumb, this.subs = ''});

  Map<String, String> toJson() => {'id': id, 'name': name, 'thumb': thumb, 'subs': subs};
  factory YtChannel.fromJson(Map<String, dynamic> j) => YtChannel(
    id: j['id'] as String, name: j['name'] as String,
    thumb: j['thumb'] as String, subs: j['subs'] as String? ?? '',
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────
String _fmtDur(Duration? d) {
  if (d == null) return '';
  final h = d.inHours; final m = d.inMinutes % 60; final s = d.inSeconds % 60;
  return h > 0
      ? '$h:${m.toString().padLeft(2,'0')}:${s.toString().padLeft(2,'0')}'
      : '$m:${s.toString().padLeft(2,'0')}';
}

String _fmtViews(int n) {
  if (n >= 1000000000) return '${(n/1000000000).toStringAsFixed(1)}B views';
  if (n >= 1000000)    return '${(n/1000000).toStringAsFixed(1)}M views';
  if (n >= 1000)       return '${(n/1000).toStringAsFixed(0)}K views';
  return '$n views';
}

String _fmtAge(DateTime? dt) {
  if (dt == null) return '';
  final d = DateTime.now().difference(dt);
  if (d.inDays > 365) return '${(d.inDays/365).toInt()} years ago';
  if (d.inDays > 30)  return '${(d.inDays/30).toInt()} months ago';
  if (d.inDays > 0)   return '${d.inDays} days ago';
  if (d.inHours > 0)  return '${d.inHours}h ago';
  return '${d.inMinutes}m ago';
}

// ─────────────────────────────────────────────────────────────────────────────
// Data Service (Innertube / youtube_explode_dart)
// ─────────────────────────────────────────────────────────────────────────────
class _YtSvc {
  /// Home feed — YouTube trending playlist for India
  static Future<List<YtVid>> home() async {
    final out = <YtVid>[];
    try {
      const plId = 'PLrEnWoR732-BHrPp_Pm8_VleD68f9s14-';
      await for (final v in _yt.playlists.getVideos(plId)) {
        out.add(YtVid.fromPlaylist(v));
        if (out.length >= 25) break;
      }
    } catch (_) {}
    if (out.isEmpty) {
      try {
        final list = await _yt.search.search('trending India 2025');
        for (final v in list) {
          out.add(YtVid.fromVideo(v));
          if (out.length >= 20) break;
        }
      } catch (_) {}
    }
    return out;
  }

  static Future<List<YtVid>> search(String q) async {
    final out = <YtVid>[];
    try {
      final list = await _yt.search.search(q);
      for (final v in list) {
        out.add(YtVid.fromVideo(v));
        if (out.length >= 30) break;
      }
    } catch (_) {}
    return out;
  }

  static Future<List<YtVid>> shorts() async {
    final out = <YtVid>[];
    try {
      final list = await _yt.search.search('#shorts India 2025');
      for (final v in list) {
        out.add(YtVid.fromVideo(v));
        if (out.length >= 20) break;
      }
    } catch (_) {}
    return out;
  }

  static Future<List<YtVid>> channelVideos(String channelId) async {
    final out = <YtVid>[];
    try {
      await for (final v in _yt.channels.getUploads(channelId)) {
        out.add(YtVid.fromVideo(v));
        if (out.length >= 15) break;
      }
    } catch (_) {}
    return out;
  }

  static Future<YtChannel?> findChannel(String query) async {
    try {
      Channel? ch;
      if (query.startsWith('UC') && !query.contains(' ')) {
        ch = await _yt.channels.get(ChannelId(query));
      } else {
        final handle = query.startsWith('@') ? query.substring(1) : query;
        try {
          ch = await _yt.channels.getByUsername(handle);
        } catch (_) {
          final list = await _yt.search.search(query);
          for (final v in list) {
            ch = await _yt.channels.get(v.channelId);
            break;
          }
        }
      }
      if (ch == null) return null;
      return YtChannel(
        id: ch.id.value,
        name: ch.title,
        thumb: ch.logoUrl,
        subs: ch.subscribersCount != null ? _fmtViews(ch.subscribersCount!) : '',
      );
    } catch (_) { return null; }
  }

  static Future<List<YtVid>> related(String videoId) async {
    final out = <YtVid>[];
    try {
      final v = await _yt.videos.get(videoId);
      final q = v.title.split(' ').take(4).join(' ');
      final list = await _yt.search.search(q);
      for (final r in list) {
        if (r.id.value != videoId) { out.add(YtVid.fromVideo(r)); }
        if (out.length >= 15) break;
      }
    } catch (_) {}
    return out;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Background Audio
// ─────────────────────────────────────────────────────────────────────────────
class _BgAudio {
  static final player = AudioPlayer();
  static Future<void> play(String id) async {
    try {
      final m = await _yt.videos.streamsClient.getManifest(id);
      final a = m.audioOnly.withHighestBitrate();
      await player.setAudioSource(AudioSource.uri(Uri.parse(a.url.toString())));
      await player.play();
    } catch (e) { debugPrint('BgAudio: $e'); }
  }
  static Future<void> stop() => player.stop();
  static bool get isPlaying => player.playing;
}

// ─────────────────────────────────────────────────────────────────────────────
// Subscriptions store
// ─────────────────────────────────────────────────────────────────────────────
class _SubStore {
  static List<YtChannel> _cache = [];

  static Future<List<YtChannel>> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getStringList(_kSprefsKey) ?? [];
    _cache = raw.map((e) => YtChannel.fromJson(json.decode(e) as Map<String, dynamic>)).toList();
    return _cache;
  }

  static Future<void> add(YtChannel ch) async {
    if (_cache.any((c) => c.id == ch.id)) return;
    _cache.add(ch);
    await _save();
  }

  static Future<void> remove(String id) async {
    _cache.removeWhere((c) => c.id == id);
    await _save();
  }

  // kept for potential external callers
  // static bool has(String id) => _cache.any((c) => c.id == id);

  static Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kSprefsKey, _cache.map((c) => json.encode(c.toJson())).toList());
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Root Screen
// ─────────────────────────────────────────────────────────────────────────────
class YouTubeScreen extends StatefulWidget {
  const YouTubeScreen({super.key});
  @override State<YouTubeScreen> createState() => _YouTubeScreenState();
}

class _YouTubeScreenState extends State<YouTubeScreen> {
  int _tab = 0;
  YtVid? _miniVideo;

  void _openVideo(YtVid v) {
    Navigator.of(context).push(PageRouteBuilder(
      pageBuilder: (_, a1, a2) => _VideoPage(video: v, onMinimize: (vid) {
        setState(() => _miniVideo = vid);
      }),
      transitionsBuilder: (_, anim, a2, child) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
            .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: child,
      ),
      transitionDuration: const Duration(milliseconds: 280),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      _HomeTab(onTap: _openVideo),
      _ShortsTab(onTap: _openVideo),
      const _CreateTab(),
      _SubsTab(onTap: _openVideo),
      const _YouTab(),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: Stack(children: [
        IndexedStack(index: _tab, children: tabs),
        if (_miniVideo != null)
          _MiniPlayer(
            video: _miniVideo!,
            onExpand: () { final v = _miniVideo!; setState(() => _miniVideo = null); _openVideo(v); },
            onClose: () { setState(() => _miniVideo = null); _BgAudio.stop(); },
          ),
      ]),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    const items = [
      (Icons.home_outlined, Icons.home, 'Home'),
      (Icons.slideshow_outlined, Icons.slideshow, 'Shorts'),
      (Icons.add_circle_outline, Icons.add_circle, 'Create'),
      (Icons.subscriptions_outlined, Icons.subscriptions, 'Subscriptions'),
      (Icons.person_outline, Icons.person, 'You'),
    ];
    return Container(
      color: const Color(0xFF111111),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(items.length, (i) {
              final selected = _tab == i;
              return Expanded(child: GestureDetector(
                onTap: () => setState(() => _tab = i),
                behavior: HitTestBehavior.opaque,
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(selected ? items[i].$2 : items[i].$1,
                      color: selected ? Colors.white : Colors.white38, size: 22),
                  const SizedBox(height: 2),
                  Text(items[i].$3,
                      style: TextStyle(
                        color: selected ? Colors.white : Colors.white38,
                        fontSize: 10, fontWeight: FontWeight.w500,
                      )),
                ]),
              ));
            }),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Top App Bar (shared)
// ─────────────────────────────────────────────────────────────────────────────
class _YtAppBar extends StatelessWidget implements PreferredSizeWidget {
  final void Function()? onSearch;
  const _YtAppBar({this.onSearch});

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Container(
        height: 56, color: const Color(0xFF0F0F0F),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          // YouTube logo
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 28, height: 20,
              decoration: BoxDecoration(
                color: const Color(0xFFFF0000),
                borderRadius: BorderRadius.circular(5),
              ),
              child: const Center(child: Icon(Icons.play_arrow, color: Colors.white, size: 16)),
            ),
            const SizedBox(width: 5),
            const Text('YouTube', style: TextStyle(
              color: Colors.white, fontSize: 17,
              fontWeight: FontWeight.w700, letterSpacing: -0.5,
            )),
          ]),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.cast, color: Colors.white, size: 22),
            onPressed: () {},
            padding: const EdgeInsets.all(8),
          ),
          IconButton(
            icon: const Icon(Icons.notifications_none, color: Colors.white, size: 22),
            onPressed: () {},
            padding: const EdgeInsets.all(8),
          ),
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white, size: 22),
            onPressed: onSearch,
            padding: const EdgeInsets.all(8),
          ),
          const CircleAvatar(radius: 14, backgroundColor: Color(0xFF6C63FF),
              child: Icon(Icons.person, size: 15, color: Colors.white)),
          const SizedBox(width: 4),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Home Tab
// ─────────────────────────────────────────────────────────────────────────────
class _HomeTab extends StatefulWidget {
  final void Function(YtVid) onTap;
  const _HomeTab({required this.onTap});
  @override State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> with AutomaticKeepAliveClientMixin {
  List<YtVid> _videos = [];
  bool _loading = true;
  final _cats = ['All', 'Music', 'Gaming', 'News', 'Sports', 'Tech', 'Movies', 'Live'];
  String _selCat = 'All';

  @override bool get wantKeepAlive => true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    List<YtVid> vids = await _YtSvc.home();
    if (_selCat != 'All') {
      vids = await _YtSvc.search(_selCat);
    }
    if (mounted) setState(() { _videos = vids; _loading = false; });
  }

  Future<void> _selectCat(String cat) async {
    setState(() { _selCat = cat; _loading = true; });
    final vids = cat == 'All' ? await _YtSvc.home() : await _YtSvc.search(cat);
    if (mounted) setState(() { _videos = vids; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: _YtAppBar(onSearch: () => _pushSearch(context)),
      body: RefreshIndicator(
        color: const Color(0xFFFF0000),
        backgroundColor: const Color(0xFF1A1A1A),
        onRefresh: _load,
        child: CustomScrollView(slivers: [
          // Category chips
          SliverToBoxAdapter(child: SizedBox(
            height: 46,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              itemCount: _cats.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => _selectCat(_cats[i]),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                    decoration: BoxDecoration(
                      color: _selCat == _cats[i] ? Colors.white : const Color(0xFF272727),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(_cats[i], style: TextStyle(
                      color: _selCat == _cats[i] ? Colors.black : Colors.white,
                      fontSize: 13, fontWeight: FontWeight.w500,
                    )),
                  ),
                ),
              ),
            ),
          )),
          if (_loading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator(color: Color(0xFFFF0000))),
            )
          else if (_videos.isEmpty)
            const SliverFillRemaining(
              child: Center(child: Text('Could not load feed.\nPull down to retry.',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.white38))),
            )
          else
            SliverList(delegate: SliverChildBuilderDelegate(
              (_, i) => _VCard(video: _videos[i], onTap: () => widget.onTap(_videos[i])),
              childCount: _videos.length,
            )),
        ]),
      ),
    );
  }

  void _pushSearch(BuildContext ctx) {
    Navigator.of(ctx).push(MaterialPageRoute(
      builder: (_) => _SearchPage(onTap: widget.onTap),
    ));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Search Page (separate screen — logo stays on main page)
// ─────────────────────────────────────────────────────────────────────────────
class _SearchPage extends StatefulWidget {
  final void Function(YtVid) onTap;
  const _SearchPage({required this.onTap});
  @override State<_SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<_SearchPage> {
  final _ctrl = TextEditingController();
  List<YtVid> _results = [];
  bool _loading = false;

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) return;
    setState(() { _loading = true; _results = []; });
    final r = await _YtSvc.search(q);
    if (mounted) setState(() { _results = r; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF212121),
        elevation: 0,
        leading: const BackButton(color: Colors.white),
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          decoration: const InputDecoration(
            hintText: 'Search YouTube',
            hintStyle: TextStyle(color: Colors.white38),
            border: InputBorder.none,
          ),
          onSubmitted: _search,
          textInputAction: TextInputAction.search,
        ),
        actions: [
          if (_ctrl.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () { _ctrl.clear(); setState(() => _results = []); },
            ),
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white),
            onPressed: () => _search(_ctrl.text),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF0000)))
          : _results.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.search, size: 72, color: Colors.white12),
                  const SizedBox(height: 12),
                  const Text('Search for videos, channels\nor playlists',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38, fontSize: 14)),
                ]))
              : ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (_, i) => _VCard(
                    video: _results[i],
                    onTap: () { widget.onTap(_results[i]); },
                    compact: true,
                  ),
                ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shorts Tab
// ─────────────────────────────────────────────────────────────────────────────
class _ShortsTab extends StatefulWidget {
  final void Function(YtVid) onTap;
  const _ShortsTab({required this.onTap});
  @override State<_ShortsTab> createState() => _ShortsTabState();
}

class _ShortsTabState extends State<_ShortsTab> with AutomaticKeepAliveClientMixin {
  List<YtVid> _shorts = [];
  bool _loading = true;

  @override bool get wantKeepAlive => true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final v = await _YtSvc.shorts();
    if (mounted) setState(() { _shorts = v; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _YtAppBar(onSearch: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => _SearchPage(onTap: widget.onTap)))),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF0000)))
          : _shorts.isEmpty
              ? const Center(child: Text('No shorts loaded', style: TextStyle(color: Colors.white38)))
              : PageView.builder(
                  scrollDirection: Axis.vertical,
                  itemCount: _shorts.length,
                  itemBuilder: (_, i) => _ShortCard(video: _shorts[i], onTap: () => widget.onTap(_shorts[i])),
                ),
    );
  }
}

class _ShortCard extends StatelessWidget {
  final YtVid video;
  final VoidCallback onTap;
  const _ShortCard({required this.video, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(fit: StackFit.expand, children: [
        // Thumbnail
        Image.network(video.thumb, fit: BoxFit.cover, errorBuilder: (_, a, b) =>
            Container(color: const Color(0xFF1A1A1A))),
        // Gradient
        Container(decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black87],
          ),
        )),
        // Info
        Positioned(bottom: 80, left: 12, right: 60, child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(video.channel, style: const TextStyle(color: Colors.white,
              fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 4),
          Text(video.title, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 13)),
        ])),
        // Right actions
        Positioned(bottom: 80, right: 8, child: Column(children: [
          _ShortAction(Icons.thumb_up_outlined, 'Like'),
          const SizedBox(height: 20),
          _ShortAction(Icons.comment_outlined, 'Comment'),
          const SizedBox(height: 20),
          _ShortAction(Icons.share_outlined, 'Share'),
        ])),
        // Shorts label
        const Positioned(top: 12, left: 16,
          child: Text('Shorts', style: TextStyle(color: Colors.white,
              fontSize: 16, fontWeight: FontWeight.w700))),
      ]),
    );
  }
}

class _ShortAction extends StatelessWidget {
  final IconData icon;
  final String label;
  const _ShortAction(this.icon, this.label);
  @override Widget build(BuildContext context) => Column(children: [
    Icon(icon, color: Colors.white, size: 28),
    const SizedBox(height: 2),
    Text(label, style: const TextStyle(color: Colors.white, fontSize: 11)),
  ]);
}

// ─────────────────────────────────────────────────────────────────────────────
// Create Tab placeholder
// ─────────────────────────────────────────────────────────────────────────────
class _CreateTab extends StatelessWidget {
  const _CreateTab();
  @override Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF0F0F0F),
    appBar: const _YtAppBar(),
    body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.videocam_outlined, size: 80, color: Colors.white24),
      const SizedBox(height: 16),
      const Text('Create', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      const Text('Upload a video or Go live', style: TextStyle(color: Colors.white54)),
      const SizedBox(height: 24),
      _CreateBtn(Icons.upload, 'Upload a video', () {}),
      const SizedBox(height: 12),
      _CreateBtn(Icons.circle, 'Create a Short', () {}),
      const SizedBox(height: 12),
      _CreateBtn(Icons.live_tv, 'Go live', () {}),
    ])),
  );
}

class _CreateBtn extends StatelessWidget {
  final IconData icon; final String label; final VoidCallback onTap;
  const _CreateBtn(this.icon, this.label, this.onTap);
  @override Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      width: 240,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF272727), borderRadius: BorderRadius.circular(24),
      ),
      child: Row(children: [
        Icon(icon, color: Colors.white, size: 22),
        const SizedBox(width: 14),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
      ]),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Subscriptions Tab
// ─────────────────────────────────────────────────────────────────────────────
class _SubsTab extends StatefulWidget {
  final void Function(YtVid) onTap;
  const _SubsTab({required this.onTap});
  @override State<_SubsTab> createState() => _SubsTabState();
}

class _SubsTabState extends State<_SubsTab> with AutomaticKeepAliveClientMixin {
  List<YtChannel> _channels = [];
  YtChannel? _selChannel;
  List<YtVid> _videos = [];
  bool _loadingVids = false;
  bool _loadingChans = true;
  final _addCtrl = TextEditingController();

  @override bool get wantKeepAlive => true;

  @override
  void initState() { super.initState(); _loadChannels(); }

  Future<void> _loadChannels() async {
    setState(() => _loadingChans = true);
    final ch = await _SubStore.load();
    if (mounted) setState(() { _channels = ch; _loadingChans = false; });
    if (_channels.isNotEmpty) { _selectChannel(_channels.first); }
  }

  Future<void> _selectChannel(YtChannel ch) async {
    setState(() { _selChannel = ch; _loadingVids = true; _videos = []; });
    final v = await _YtSvc.channelVideos(ch.id);
    if (mounted) setState(() { _videos = v; _loadingVids = false; });
  }

  Future<void> _addChannel(String query) async {
    if (query.trim().isEmpty) return;
    final ch = await _YtSvc.findChannel(query.trim());
    if (ch == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Channel not found'), backgroundColor: Colors.red));
      }
      return;
    }
    await _SubStore.add(ch);
    await _loadChannels();
    _addCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: _YtAppBar(onSearch: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => _SearchPage(onTap: widget.onTap)))),
      body: _loadingChans
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF0000)))
          : Column(children: [
              // ── Channel row ──────────────────────────────────────────────
              SizedBox(height: 100, child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                children: [
                  // Add button
                  Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: GestureDetector(
                      onTap: () => _showAddDialog(context),
                      child: Column(children: [
                        Container(
                          width: 56, height: 56,
                          decoration: BoxDecoration(
                            color: const Color(0xFF272727),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white24),
                          ),
                          child: const Icon(Icons.add, color: Colors.white, size: 26),
                        ),
                        const SizedBox(height: 4),
                        const Text('Add', style: TextStyle(color: Colors.white54, fontSize: 11)),
                      ]),
                    ),
                  ),
                  // Channel avatars
                  ..._channels.map((ch) => Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: GestureDetector(
                      onTap: () => _selectChannel(ch),
                      onLongPress: () => _confirmRemove(ch),
                      child: Column(children: [
                        Container(
                          width: 56, height: 56,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _selChannel?.id == ch.id
                                  ? const Color(0xFFFF0000) : Colors.transparent,
                              width: 2.5,
                            ),
                          ),
                          child: ClipOval(child: ch.thumb.isNotEmpty
                              ? Image.network(ch.thumb, fit: BoxFit.cover,
                                  errorBuilder: (_, a, b) => _avatarFallback(ch.name))
                              : _avatarFallback(ch.name)),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(width: 60, child: Text(ch.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _selChannel?.id == ch.id ? Colors.white : Colors.white60,
                              fontSize: 11, fontWeight: _selChannel?.id == ch.id
                                  ? FontWeight.w600 : FontWeight.normal,
                            ))),
                      ]),
                    ),
                  )),
                ],
              )),
              // ── Divider ─────────────────────────────────────────────────
              const Divider(color: Colors.white12, height: 1),
              // ── Channel header ──────────────────────────────────────────
              if (_selChannel != null)
                Container(
                  color: const Color(0xFF1A1A1A),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(children: [
                    ClipOval(child: _selChannel!.thumb.isNotEmpty
                        ? Image.network(_selChannel!.thumb, width: 40, height: 40, fit: BoxFit.cover)
                        : _avatarFallback(_selChannel!.name)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_selChannel!.name, style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                      if (_selChannel!.subs.isNotEmpty)
                        Text(_selChannel!.subs, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    ])),
                    OutlinedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.notifications_outlined, size: 16),
                      label: const Text('Subscribed'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ]),
                ),
              // ── Videos list ─────────────────────────────────────────────
              Expanded(child: _channels.isEmpty
                  ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.subscriptions_outlined, size: 80, color: Colors.white12),
                      const SizedBox(height: 16),
                      const Text('Your subscriptions will appear here',
                          style: TextStyle(color: Colors.white54, fontSize: 15)),
                      const SizedBox(height: 8),
                      const Text('Tap + to add a channel (@handle or channel name)',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white30, fontSize: 13)),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: () => _showAddDialog(context),
                        icon: const Icon(Icons.add),
                        label: const Text('Add Channel'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF0000),
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ]))
                  : _loadingVids
                      ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF0000)))
                      : _videos.isEmpty
                          ? const Center(child: Text('No videos found', style: TextStyle(color: Colors.white38)))
                          : ListView.builder(
                              itemCount: _videos.length,
                              itemBuilder: (_, i) => _VCard(
                                video: _videos[i],
                                onTap: () => widget.onTap(_videos[i]),
                                compact: true,
                              ),
                            )),
            ]),
    );
  }

  Widget _avatarFallback(String name) => Container(
    width: 56, height: 56, color: const Color(0xFF333333),
    child: Center(child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
        style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold))),
  );

  void _showAddDialog(BuildContext context) {
    _addCtrl.clear();
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      title: const Text('Add Channel', style: TextStyle(color: Colors.white)),
      content: TextField(
        controller: _addCtrl,
        autofocus: true,
        style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(
          hintText: '@channelname or channel name',
          hintStyle: TextStyle(color: Colors.white38),
          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
          focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFFF0000))),
        ),
        onSubmitted: (q) { Navigator.pop(context); _addChannel(q); },
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF0000)),
          onPressed: () { Navigator.pop(context); _addChannel(_addCtrl.text); },
          child: const Text('Add', style: TextStyle(color: Colors.white)),
        ),
      ],
    ));
  }

  void _confirmRemove(YtChannel ch) {
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      title: const Text('Remove channel?', style: TextStyle(color: Colors.white)),
      content: Text('Remove ${ch.name} from subscriptions?',
          style: const TextStyle(color: Colors.white70)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF0000)),
          onPressed: () { Navigator.pop(context); _SubStore.remove(ch.id); _loadChannels(); },
          child: const Text('Remove', style: TextStyle(color: Colors.white)),
        ),
      ],
    ));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// You Tab
// ─────────────────────────────────────────────────────────────────────────────
class _YouTab extends StatelessWidget {
  const _YouTab();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: const _YtAppBar(),
      body: ListView(children: [
        const SizedBox(height: 24),
        const CircleAvatar(radius: 42, backgroundColor: Color(0xFF6C63FF),
            child: Icon(Icons.person, size: 44, color: Colors.white)),
        const SizedBox(height: 12),
        const Center(child: Text('Your Account', style: TextStyle(
            color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600))),
        const SizedBox(height: 24),
        const Divider(color: Colors.white12),
        _YouItem(Icons.history, 'History', () {}),
        _YouItem(Icons.playlist_play, 'Your playlists', () {}),
        _YouItem(Icons.download_outlined, 'Downloads', () {}),
        _YouItem(Icons.watch_later_outlined, 'Watch later', () {}),
        const Divider(color: Colors.white12),
        _YouItem(Icons.settings_outlined, 'Settings', () {}),
        _YouItem(Icons.help_outline, 'Help & feedback', () {}),
      ]),
    );
  }
}

class _YouItem extends StatelessWidget {
  final IconData icon; final String label; final VoidCallback onTap;
  const _YouItem(this.icon, this.label, this.onTap);
  @override Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, color: Colors.white70),
    title: Text(label, style: const TextStyle(color: Colors.white, fontSize: 14)),
    onTap: onTap,
    trailing: const Icon(Icons.chevron_right, color: Colors.white30),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Video Card (vertical feed + compact/search mode)
// ─────────────────────────────────────────────────────────────────────────────
class _VCard extends StatelessWidget {
  final YtVid video;
  final VoidCallback onTap;
  final bool compact;
  const _VCard({required this.video, required this.onTap, this.compact = false});

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return InkWell(onTap: onTap, child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(children: [
          Stack(children: [
            ClipRRect(borderRadius: BorderRadius.circular(4),
                child: _Thumb(url: video.thumb, w: 160, h: 90)),
            if (video.duration.isNotEmpty)
              Positioned(bottom: 4, right: 4, child: _DurBadge(video.duration)),
          ]),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(video.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Text(video.channel, style: const TextStyle(color: Colors.white60, fontSize: 12)),
            if (video.viewCount.isNotEmpty || video.age.isNotEmpty)
              Text('${video.viewCount}${video.viewCount.isNotEmpty && video.age.isNotEmpty ? ' • ' : ''}${video.age}',
                  style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ])),
          IconButton(icon: const Icon(Icons.more_vert, color: Colors.white38, size: 18),
            onPressed: () {}, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
        ]),
      ));
    }
    // Full-width card (home feed)
    return InkWell(onTap: onTap, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Stack(children: [
        _Thumb(url: video.thumb, w: double.infinity, h: 210),
        if (video.duration.isNotEmpty)
          Positioned(bottom: 8, right: 8, child: _DurBadge(video.duration)),
      ]),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const CircleAvatar(radius: 18, backgroundColor: Color(0xFF333333),
              child: Icon(Icons.person, size: 18, color: Colors.white60)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(video.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
            const SizedBox(height: 3),
            Text([video.channel, if (video.viewCount.isNotEmpty) video.viewCount,
              if (video.age.isNotEmpty) video.age].join(' • '),
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ])),
          IconButton(icon: const Icon(Icons.more_vert, color: Colors.white54, size: 20),
            onPressed: () {}, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
        ]),
      ),
      const SizedBox(height: 4),
    ]));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Video Player Page
// ─────────────────────────────────────────────────────────────────────────────
class _VideoPage extends StatefulWidget {
  final YtVid video;
  final void Function(YtVid) onMinimize;
  const _VideoPage({required this.video, required this.onMinimize});
  @override State<_VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<_VideoPage> {
  final _ytLocal = YoutubeExplode();
  VideoPlayerController? _vpc;
  bool _loading = true, _error = false, _audioOnly = false, _ctrlVisible = true;
  Timer? _hideTimer;
  List<YtVid> _related = [];
  String _desc = '';
  bool _descExpanded = false;

  @override
  void initState() {
    super.initState();
    _initPlayer();
    _loadMeta();
    _loadRelated();
  }

  Future<void> _initPlayer() async {
    setState(() { _loading = true; _error = false; });
    try {
      final manifest = await _ytLocal.videos.streamsClient.getManifest(widget.video.id);
      // Try muxed (video+audio) first — available for ≤360p
      if (manifest.muxed.isNotEmpty) {
        final stream = manifest.muxed.withHighestBitrate();
        _vpc = VideoPlayerController.networkUrl(Uri.parse(stream.url.toString()));
        await _vpc!.initialize();
        await _vpc!.play();
        if (mounted) setState(() => _loading = false);
        _scheduleHide();
      } else {
        // Audio-only fallback — show thumbnail + audio
        setState(() { _audioOnly = true; });
        await _BgAudio.play(widget.video.id);
        if (mounted) setState(() => _loading = false);
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = true; });
    }
  }

  Future<void> _loadMeta() async {
    try {
      final v = await _ytLocal.videos.get(widget.video.id);
      if (mounted) setState(() => _desc = v.description);
    } catch (_) {}
  }

  Future<void> _loadRelated() async {
    final r = await _YtSvc.related(widget.video.id);
    if (mounted) setState(() => _related = r);
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _ctrlVisible = false);
    });
  }

  void _toggleControls() {
    setState(() => _ctrlVisible = !_ctrlVisible);
    if (_ctrlVisible) _scheduleHide();
  }

  void _minimize() {
    _vpc?.pause();
    _BgAudio.play(widget.video.id);
    widget.onMinimize(widget.video);
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _vpc?.dispose();
    _ytLocal.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: SafeArea(child: Column(children: [
        _buildPlayer(),
        Expanded(child: CustomScrollView(slivers: [
          SliverToBoxAdapter(child: _buildMeta()),
          SliverToBoxAdapter(child: _buildActions()),
          SliverToBoxAdapter(child: _buildDesc()),
          const SliverToBoxAdapter(child: Divider(color: Colors.white12, height: 1)),
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: const Text('Up next',
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
          )),
          if (_related.isEmpty)
            const SliverToBoxAdapter(child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator(color: Color(0xFFFF0000), strokeWidth: 2)),
            ))
          else
            SliverList(delegate: SliverChildBuilderDelegate(
              (_, i) => _VCard(
                video: _related[i],
                compact: true,
                onTap: () => Navigator.of(context).pushReplacement(MaterialPageRoute(
                  builder: (_) => _VideoPage(video: _related[i], onMinimize: widget.onMinimize),
                )),
              ),
              childCount: _related.length,
            )),
        ])),
      ])),
    );
  }

  Widget _buildPlayer() {
    final w = MediaQuery.of(context).size.width;
    final h = w * 9 / 16;
    return GestureDetector(
      onTap: _toggleControls,
      child: Container(width: w, height: h, color: Colors.black,
        child: Stack(alignment: Alignment.center, children: [
          if (_loading)
            const CircularProgressIndicator(color: Color(0xFFFF0000))
          else if (_error)
            Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 40),
              const SizedBox(height: 8),
              const Text('Could not load video', style: TextStyle(color: Colors.white70)),
              TextButton(onPressed: _initPlayer,
                  child: const Text('Retry', style: TextStyle(color: Color(0xFF3EA6FF)))),
            ])
          else if (_audioOnly)
            Stack(children: [
              _Thumb(url: widget.video.thumb, w: w, h: h),
              Container(width: w, height: h, color: Colors.black54),
              const Center(child: Icon(Icons.music_note, color: Colors.white60, size: 64)),
            ])
          else if (_vpc != null && _vpc!.value.isInitialized)
            AspectRatio(aspectRatio: _vpc!.value.aspectRatio, child: VideoPlayer(_vpc!)),

          // Controls
          if (_ctrlVisible && !_loading && !_error)
            _buildControls(w, h),

          // Back/minimize
          Positioned(top: 8, left: 8,
            child: GestureDetector(
              onTap: _minimize,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                child: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 24),
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
      opacity: _ctrlVisible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      child: Container(width: w, height: h,
        decoration: const BoxDecoration(gradient: LinearGradient(
          colors: [Colors.black54, Colors.transparent, Colors.black87],
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
        )),
        child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const SizedBox(),
          // Play/Pause
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(
              icon: const Icon(Icons.replay_10, color: Colors.white, size: 36),
              onPressed: () {
                if (_vpc != null) { _vpc!.seekTo(_vpc!.value.position - const Duration(seconds: 10)); }
              },
            ),
            const SizedBox(width: 16),
            IconButton(
              iconSize: 60,
              icon: Icon(playing ? Icons.pause_circle_filled : Icons.play_circle_filled,
                  color: Colors.white, size: 60),
              onPressed: () {
                setState(() {
                  if (_audioOnly) {
                    if (_BgAudio.isPlaying) { _BgAudio.player.pause(); } else { _BgAudio.player.play(); }
                  } else {
                    if (_vpc!.value.isPlaying) { _vpc!.pause(); } else { _vpc!.play(); }
                  }
                });
                _scheduleHide();
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 16),
            IconButton(
              icon: const Icon(Icons.forward_10, color: Colors.white, size: 36),
              onPressed: () {
                if (_vpc != null) { _vpc!.seekTo(_vpc!.value.position + const Duration(seconds: 10)); }
              },
            ),
          ]),
          // Progress bar
          if (!_audioOnly && _vpc != null)
            Column(children: [
              VideoProgressIndicator(_vpc!,
                allowScrubbing: true,
                colors: const VideoProgressColors(
                  playedColor: Color(0xFFFF0000),
                  backgroundColor: Colors.white24,
                  bufferedColor: Colors.white38,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              ),
              Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: ValueListenableBuilder(
                  valueListenable: _vpc!,
                  builder: (_, value, a) => Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_fmtDur(value.position), style: const TextStyle(color: Colors.white, fontSize: 11)),
                      Text(_fmtDur(value.duration), style: const TextStyle(color: Colors.white60, fontSize: 11)),
                    ],
                  ),
                )),
            ])
          else
            const SizedBox(height: 12),
        ]),
      ),
    );
  }

  Widget _buildMeta() => Padding(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(widget.video.title,
          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      Text([if (widget.video.viewCount.isNotEmpty) widget.video.viewCount,
        if (widget.video.age.isNotEmpty) widget.video.age].join(' • '),
          style: const TextStyle(color: Colors.white54, fontSize: 13)),
    ]),
  );

  Widget _buildActions() {
    final items = [
      (Icons.thumb_up_outlined, 'Like'),
      (Icons.thumb_down_outlined, 'Dislike'),
      (Icons.share_outlined, 'Share'),
      (Icons.download_outlined, 'Download'),
      (Icons.playlist_add, 'Save'),
    ];
    return SizedBox(height: 72, child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      children: items.map((e) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(color: const Color(0xFF272727), borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(e.$1, color: Colors.white, size: 18),
              const SizedBox(width: 6),
              Text(e.$2, style: const TextStyle(color: Colors.white, fontSize: 13)),
            ]),
          ),
        ]),
      )).toList(),
    ));
  }

  Widget _buildDesc() {
    if (_desc.isEmpty) return const SizedBox(height: 8);
    final show = _descExpanded ? _desc : (_desc.length > 120 ? _desc.substring(0, 120) : _desc);
    return GestureDetector(
      onTap: () => setState(() => _descExpanded = !_descExpanded),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(8)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(show, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5)),
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
// Mini Player
// ─────────────────────────────────────────────────────────────────────────────
class _MiniPlayer extends StatefulWidget {
  final YtVid video;
  final VoidCallback onExpand, onClose;
  const _MiniPlayer({required this.video, required this.onExpand, required this.onClose});
  @override State<_MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<_MiniPlayer> {
  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 56, left: 0, right: 0,
      child: GestureDetector(
        onTap: widget.onExpand,
        child: Container(
          height: 64,
          decoration: const BoxDecoration(
            color: Color(0xFF212121),
            border: Border(top: BorderSide(color: Color(0xFF333333))),
            boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 8)],
          ),
          child: Row(children: [
            ClipRRect(child: _Thumb(url: widget.video.thumb, w: 100, h: 64)),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(widget.video.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Text(widget.video.channel, maxLines: 1,
                  style: const TextStyle(color: Colors.white54, fontSize: 11)),
            ])),
            // Play/pause
            StreamBuilder<PlayerState>(
              stream: _BgAudio.player.playerStateStream,
              builder: (_, snap) {
                final playing = snap.data?.playing ?? false;
                return IconButton(
                  icon: Icon(playing ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 24),
                  onPressed: () {
                    if (playing) { _BgAudio.player.pause(); } else { _BgAudio.player.play(); }
                    setState(() {});
                  },
                );
              },
            ),
            IconButton(icon: const Icon(Icons.close, color: Colors.white54, size: 20),
              onPressed: widget.onClose, padding: const EdgeInsets.all(8)),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared Widgets
// ─────────────────────────────────────────────────────────────────────────────
class _Thumb extends StatelessWidget {
  final String url; final double w, h;
  const _Thumb({required this.url, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return Container(width: w, height: h, color: const Color(0xFF1A1A1A),
          child: const Icon(Icons.videocam, color: Colors.white24));
    }
    return Image.network(url, width: w, height: h, fit: BoxFit.cover,
        errorBuilder: (_, a, b) => Container(width: w, height: h, color: const Color(0xFF1A1A1A),
            child: const Icon(Icons.broken_image, color: Colors.white24)));
  }
}

class _DurBadge extends StatelessWidget {
  final String dur;
  const _DurBadge(this.dur);
  @override Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
    decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(3)),
    child: Text(dur, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
  );
}
