// ignore_for_file: use_build_context_synchronously, unnecessary_underscores, deprecated_member_use, dead_code, dead_null_aware_expression
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:audio_service/audio_service.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart'
    hide VideoQuality;
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../main.dart' show ytAudioHandler;
import 'package:provider/provider.dart';
import 'youtube_download_manager.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Shared YoutubeExplode instance (uses YouTube Innertube API — no key needed)
// ─────────────────────────────────────────────────────────────────────────────
final _yt = YoutubeExplode();
const _kSprefsKey = 'yt_subscriptions';
const _kAccountKey = 'yt_account_info';

// ─────────────────────────────────────────────────────────────────────────────
// Account Info Model
// ─────────────────────────────────────────────────────────────────────────────
class YtAccount {
  final String name, email, photoUrl;
  const YtAccount({
    required this.name,
    required this.email,
    required this.photoUrl,
  });

  Map<String, String> toJson() => {
    'name': name,
    'email': email,
    'photo': photoUrl,
  };
  factory YtAccount.fromJson(Map<String, dynamic> j) => YtAccount(
    name: j['name'] ?? '',
    email: j['email'] ?? '',
    photoUrl: j['photo'] ?? '',
  );
  bool get isSignedIn => name.isNotEmpty;
}

// ─────────────────────────────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────────────────────────────
class YtVid {
  final String id, title, channel, channelId, thumb, duration, viewCount, age;
  const YtVid({
    required this.id,
    required this.title,
    required this.channel,
    required this.channelId,
    required this.thumb,
    required this.duration,
    this.viewCount = '',
    this.age = '',
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

  factory YtVid.fromJson(Map<String, dynamic> j) => YtVid(
    id: j['id'] ?? '',
    title: j['title'] ?? '',
    channel: j['channel'] ?? '',
    channelId: j['channelId'] ?? '',
    thumb: j['thumb'] ?? '',
    duration: j['duration'] ?? '',
    viewCount: j['viewCount'] ?? '',
    age: j['age'] ?? '',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'channel': channel,
    'channelId': channelId,
    'thumb': thumb,
    'duration': duration,
    'viewCount': viewCount,
    'age': age,
  };
}

class YtChannel {
  final String id, name, thumb, subs;
  const YtChannel({
    required this.id,
    required this.name,
    required this.thumb,
    this.subs = '',
  });

  Map<String, String> toJson() => {
    'id': id,
    'name': name,
    'thumb': thumb,
    'subs': subs,
  };
  factory YtChannel.fromJson(Map<String, dynamic> j) => YtChannel(
    id: j['id'] as String,
    name: j['name'] as String,
    thumb: j['thumb'] as String,
    subs: j['subs'] as String? ?? '',
  );
}

/// Holds raw adaptive + muxed format maps from InnerTube ANDROID player response.
class _StreamBundle {
  final List<Map<String, dynamic>> adaptive; // videoOnly + audioOnly
  final List<Map<String, dynamic>> muxed; // combined video+audio (360p/720p)
  const _StreamBundle({required this.adaptive, required this.muxed});

  // All video-only adaptive entries (mime starts with "video/")
  List<Map<String, dynamic>> get videoFormats => adaptive
      .where((f) => (f['mimeType'] as String? ?? '').startsWith('video/'))
      .toList();

  // All audio-only adaptive entries
  List<Map<String, dynamic>> get audioFormats => adaptive
      .where((f) => (f['mimeType'] as String? ?? '').startsWith('audio/'))
      .toList();

  // Pick best audio (highest bitrate, prefer mp4a/AAC)
  Map<String, dynamic>? get bestAudio {
    final all = audioFormats
      ..sort(
        (a, b) => ((b['bitrate'] as num?) ?? 0).compareTo(
          (a['bitrate'] as num?) ?? 0,
        ),
      );
    return all
        .firstWhere(
          (f) => (f['mimeType'] as String? ?? '').contains('mp4a'),
          orElse: () => all.isNotEmpty ? all.first : {},
        )
        .nullIfEmpty;
  }

  // Pick video closest to targetHeight (H.264/avc1 preferred only as tiebreaker)
  Map<String, dynamic>? videoForQuality(int targetHeight) {
    final vids = videoFormats
        .where((f) => ((f['height'] as num?) ?? 0) <= targetHeight)
        .toList();
    if (vids.isEmpty) {
      final all = List.of(videoFormats)
        ..sort(
          (a, b) => ((a['height'] as num?) ?? 0).compareTo(
            (b['height'] as num?) ?? 0,
          ),
        );
      return all.isNotEmpty ? all.first : null;
    }

    vids.sort((a, b) {
      final hA = (a['height'] as num?) ?? 0;
      final hB = (b['height'] as num?) ?? 0;
      if (hA != hB) return hB.compareTo(hA);
      final isAvcA = (a['mimeType'] as String? ?? '').contains('avc') ? 1 : 0;
      final isAvcB = (b['mimeType'] as String? ?? '').contains('avc') ? 1 : 0;
      return isAvcB.compareTo(isAvcA);
    });
    return vids.isNotEmpty ? vids.first : null;
  }

  // Best muxed stream closest to target
  Map<String, dynamic>? muxedForQuality(int targetHeight) {
    final sorted = [...muxed]
      ..sort(
        (a, b) =>
            ((b['height'] as num?) ?? 0).compareTo((a['height'] as num?) ?? 0),
      );
    for (final f in sorted) {
      if (((f['height'] as num?) ?? 0) <= targetHeight) return f;
    }
    return sorted.isNotEmpty ? sorted.last : null;
  }
}

extension _MapNullIfEmpty on Map<String, dynamic> {
  Map<String, dynamic>? get nullIfEmpty => isEmpty ? null : this;
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────
String _fmtDur(Duration? d) {
  if (d == null) return '';
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  return h > 0
      ? '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
      : '$m:${s.toString().padLeft(2, '0')}';
}

String _fmtViews(int n) {
  if (n >= 1000000000) return '${(n / 1000000000).toStringAsFixed(1)}B views';
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M views';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)}K views';
  return '$n views';
}

String _fmtAge(DateTime? dt) {
  if (dt == null) return '';
  final d = DateTime.now().difference(dt);
  if (d.inDays > 365) return '${(d.inDays / 365).toInt()} years ago';
  if (d.inDays > 30) return '${(d.inDays / 30).toInt()} months ago';
  if (d.inDays > 0) return '${d.inDays} days ago';
  if (d.inHours > 0) return '${d.inHours}h ago';
  return '${d.inMinutes}m ago';
}

// ─────────────────────────────────────────────────────────────────────────────
// Account Store
// ─────────────────────────────────────────────────────────────────────────────
class _AccountStore {
  static YtAccount _current = const YtAccount(
    name: '',
    email: '',
    photoUrl: '',
  );
  static final _listeners = <VoidCallback>[];

  static void addListener(VoidCallback cb) => _listeners.add(cb);
  static void removeListener(VoidCallback cb) => _listeners.remove(cb);
  static void _notify() {
    for (final cb in _listeners) {
      cb();
    }
  }

  static YtAccount get current => _current;

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kAccountKey);
    if (raw != null) {
      try {
        _current = YtAccount.fromJson(json.decode(raw));
      } catch (_) {}
    }
  }

  static Future<void> save(YtAccount a) async {
    _current = a;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kAccountKey, json.encode(a.toJson()));
    _notify();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Innertube API helper — uses browser cookies for personalized content
// ─────────────────────────────────────────────────────────────────────────────
class _InnertubeApi {
  static const _apiKey =
      'AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8'; // Public WEB client key
  static const _clientName = 'WEB';
  static const _clientVer = '2.20240101';

  static Future<Map<String, String>> _buildHeaders() async {
    final cookies = await CookieManager.instance().getCookies(
      url: WebUri('https://www.youtube.com'),
    );
    final cookieStr = cookies.map((c) => '${c.name}=${c.value}').join('; ');
    return {
      'Content-Type': 'application/json',
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 Chrome/100.0.4896.79 Mobile Safari/537.36',
      'Cookie': cookieStr,
      'X-YouTube-Client-Name': '1',
      'X-YouTube-Client-Version': _clientVer,
      'Origin': 'https://www.youtube.com',
      'Referer': 'https://www.youtube.com/',
    };
  }

  static Map<String, dynamic> _baseBody() => {
    'context': {
      'client': {
        'clientName': _clientName,
        'clientVersion': _clientVer,
        'hl': 'en',
        'gl': 'IN',
      },
    },
  };

  // ── ANDROID client — gives pre-signed URLs, no cipher/signature needed ──────
  // This is the same approach used by NewPipe & LibreTube for reliable streaming.
  static Future<_StreamBundle?> getAdaptiveStreams(String videoId) async {
    try {
      final resp = await http
          .post(
            Uri.parse(
              'https://www.youtube.com/youtubei/v1/player?key=$_apiKey',
            ),
            headers: {
              'Content-Type': 'application/json',
              'User-Agent':
                  'com.google.android.youtube/19.09.37 (Linux; U; Android 11) gzip',
            },
            body: json.encode({
              'videoId': videoId,
              'context': {
                'client': {
                  'clientName': 'ANDROID',
                  'clientVersion': '19.09.37',
                  'androidSdkVersion': 30,
                  'hl': 'en',
                  'gl': 'IN',
                },
              },
              'playbackContext': {
                'contentPlaybackContext': {
                  'html5Preference': 'HTML5_PREF_WANTS',
                },
              },
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) return null;
      final data = json.decode(resp.body) as Map<String, dynamic>;
      final sd = data['streamingData'] as Map<String, dynamic>?;
      if (sd == null) return null;

      final adaptive =
          (sd['adaptiveFormats'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final formats =
          (sd['formats'] as List?)?.cast<Map<String, dynamic>>() ?? [];

      return _StreamBundle(adaptive: adaptive, muxed: formats);
    } catch (e) {
      debugPrint('getAdaptiveStreams: $e');
      return null;
    }
  }

  /// Fetch home feed — personalized if logged in
  static Future<List<YtVid>> homeFeed() async {
    try {
      final headers = await _buildHeaders();
      final body = _baseBody();
      final resp = await http
          .post(
            Uri.parse(
              'https://www.youtube.com/youtubei/v1/browse?key=$_apiKey',
            ),
            headers: headers,
            body: json.encode({...body, 'browseId': 'FEwhat_to_watch'}),
          )
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode == 200) {
        return _parseVideoList(json.decode(resp.body));
      }
    } catch (e) {
      debugPrint('Innertube homeFeed: $e');
    }
    return [];
  }

  /// Fetch subscriptions feed
  static Future<List<YtVid>> subscriptionsFeed() async {
    try {
      final headers = await _buildHeaders();
      final body = _baseBody();
      final resp = await http
          .post(
            Uri.parse(
              'https://www.youtube.com/youtubei/v1/browse?key=$_apiKey',
            ),
            headers: headers,
            body: json.encode({...body, 'browseId': 'FEsubscriptions'}),
          )
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode == 200) {
        return _parseVideoList(json.decode(resp.body));
      }
    } catch (e) {
      debugPrint('Innertube subscriptionsFeed: $e');
    }
    return [];
  }

  /// Fetch subscribed channels list
  static Future<List<YtChannel>> subscribedChannels() async {
    try {
      final headers = await _buildHeaders();
      final body = _baseBody();
      final resp = await http
          .post(
            Uri.parse('https://www.youtube.com/youtubei/v1/guide?key=$_apiKey'),
            headers: headers,
            body: json.encode(body),
          )
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode == 200) {
        return _parseChannelList(json.decode(resp.body));
      }
    } catch (e) {
      debugPrint('Innertube subscribedChannels: $e');
    }
    return [];
  }

  /// Check if user is logged in via cookies
  static Future<bool> isLoggedIn() async {
    try {
      final cookies = await CookieManager.instance().getCookies(
        url: WebUri('https://www.youtube.com'),
      );
      // Check for SID, SSID, or APISID — Google auth cookies
      return cookies.any(
        (c) =>
            c.name == 'SID' ||
            c.name == '__Secure-1PSID' ||
            c.name == 'SAPISID',
      );
    } catch (_) {
      return false;
    }
  }

  /// Extract account info from YouTube page
  static Future<YtAccount?> fetchAccountInfo() async {
    try {
      final headers = await _buildHeaders();
      final body = _baseBody();
      final resp = await http
          .post(
            Uri.parse(
              'https://www.youtube.com/youtubei/v1/account/account_menu?key=$_apiKey',
            ),
            headers: headers,
            body: json.encode(body),
          )
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        // Navigate the JSON structure to find account details
        try {
          final items =
              data['actions']?[0]?['openPopupAction']?['popup']?['multiPageMenuRenderer']?['sections']?[0]?['multiPageMenuSectionRenderer']?['items']?[0]?['compactLinkRenderer']?['title']?['simpleText']
                  as String? ??
              '';
          final photo =
              data['actions']?[0]?['openPopupAction']?['popup']?['multiPageMenuRenderer']?['header']?['activeAccountHeaderRenderer']?['accountPhoto']?['thumbnails']?[0]?['url']
                  as String? ??
              '';
          final email =
              data['actions']?[0]?['openPopupAction']?['popup']?['multiPageMenuRenderer']?['header']?['activeAccountHeaderRenderer']?['email']?['simpleText']
                  as String? ??
              '';
          if (items.isNotEmpty || email.isNotEmpty) {
            return YtAccount(name: items, email: email, photoUrl: photo);
          }
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('fetchAccountInfo: $e');
    }
    return null;
  }

  static List<YtVid> _parseVideoList(Map<String, dynamic> data) {
    final results = <YtVid>[];
    try {
      // Navigate the complex Innertube response structure
      final contents =
          _deepFind(data, 'richGridRenderer')?['contents'] as List? ??
          (_deepFind(data, 'sectionListRenderer')?['contents'] as List? ?? []);

      _extractVideos(contents, results);
    } catch (e) {
      debugPrint('_parseVideoList: $e');
    }
    return results;
  }

  static void _extractVideos(dynamic node, List<YtVid> out) {
    if (out.length >= 25) return;
    if (node is List) {
      for (final item in node) {
        _extractVideos(item, out);
      }
    } else if (node is Map) {
      // richItemRenderer
      if (node.containsKey('richItemRenderer')) {
        _extractVideos(node['richItemRenderer']?['content'], out);
        return;
      }
      // sectionListItemRenderer / itemSectionRenderer
      if (node.containsKey('itemSectionRenderer')) {
        _extractVideos(node['itemSectionRenderer']?['contents'], out);
        return;
      }
      // shelfRenderer
      if (node.containsKey('shelfRenderer')) {
        _extractVideos(node['shelfRenderer']?['content'], out);
        return;
      }
      if (node.containsKey('expandedShelfContentsRenderer')) {
        _extractVideos(node['expandedShelfContentsRenderer']?['items'], out);
        return;
      }
      // The actual videoRenderer
      final vr = node['videoRenderer'] ?? node['compactVideoRenderer'];
      if (vr != null) {
        try {
          final id = vr['videoId'] as String? ?? '';
          final title = _getText(vr['title']) ?? '';
          final channel =
              _getText(
                vr['ownerText'] ??
                    vr['longBylineText'] ??
                    vr['shortBylineText'],
              ) ??
              '';
          final channelId =
              vr['ownerText']?['runs']?[0]?['navigationEndpoint']?['browseEndpoint']?['browseId']
                  as String? ??
              '';
          final dur = _getText(vr['lengthText']) ?? '';
          final views =
              _getText(vr['shortViewCountText'] ?? vr['viewCountText']) ?? '';
          final age = _getText(vr['publishedTimeText']) ?? '';
          if (id.isNotEmpty && title.isNotEmpty) {
            out.add(
              YtVid(
                id: id,
                title: title,
                channel: channel,
                channelId: channelId,
                thumb: 'https://i.ytimg.com/vi/$id/mqdefault.jpg',
                duration: dur,
                viewCount: views,
                age: age,
              ),
            );
          }
        } catch (_) {}
        return;
      }
      // Recurse into all values
      for (final v in node.values) {
        _extractVideos(v, out);
      }
    }
  }

  static String? _getText(dynamic node) {
    if (node == null) return null;
    if (node is String) return node;
    if (node['simpleText'] != null) return node['simpleText'] as String;
    if (node['runs'] is List) {
      return (node['runs'] as List).map((r) => r['text'] ?? '').join('');
    }
    return null;
  }

  static dynamic _deepFind(dynamic data, String key) {
    if (data is Map) {
      if (data.containsKey(key)) return data[key];
      for (final v in data.values) {
        final r = _deepFind(v, key);
        if (r != null) return r;
      }
    } else if (data is List) {
      for (final item in data) {
        final r = _deepFind(item, key);
        if (r != null) return r;
      }
    }
    return null;
  }

  static List<YtChannel> _parseChannelList(Map<String, dynamic> data) {
    final results = <YtChannel>[];
    try {
      _extractChannels(data, results);
    } catch (_) {}
    return results;
  }

  static void _extractChannels(dynamic node, List<YtChannel> out) {
    if (out.length >= 50) return;
    if (node is List) {
      for (final item in node) {
        _extractChannels(item, out);
      }
    } else if (node is Map) {
      if (node.containsKey('guideSubscriptionsSectionRenderer')) {
        _extractChannels(
          node['guideSubscriptionsSectionRenderer']?['items'],
          out,
        );
        return;
      }
      if (node.containsKey('guideEntryRenderer')) {
        try {
          final title =
              _getText(node['guideEntryRenderer']?['formattedTitle']) ?? '';
          final browseId =
              node['guideEntryRenderer']?['navigationEndpoint']?['browseEndpoint']?['browseId']
                  as String? ??
              '';
          final photo =
              node['guideEntryRenderer']?['thumbnail']?['thumbnails']
                      ?.last?['url']
                  as String? ??
              '';
          if (title.isNotEmpty && browseId.startsWith('UC')) {
            out.add(YtChannel(id: browseId, name: title, thumb: photo));
          }
        } catch (_) {}
        return;
      }
      for (final v in node.values) {
        _extractChannels(v, out);
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ─────────────────────────────────────────────────────────────────────────────
// Data Service (Innertube / youtube_explode_dart) — public content
// ─────────────────────────────────────────────────────────────────────────────
class _YtSvc {
  // ── Recency helper ────────────────────────────────────────────────────────
  /// Returns true if the video was published within the last [maxDays] days.
  /// Falls back to true if date unknown (don't drop it silently).
  static bool _isRecent(YtVid v, {int maxDays = 30}) {
    // age strings like "2 days ago", "1 week ago", "3 months ago", "1 year ago"
    final age = v.age.toLowerCase();
    if (age.isEmpty) return true; // no data, keep it
    if (age.contains('hour') ||
        age.contains('minute') ||
        age.contains('second'))
      return true;
    if (age.contains('day')) {
      final n =
          int.tryParse(RegExp(r'(\d+)').firstMatch(age)?.group(1) ?? '0') ?? 0;
      return n <= maxDays;
    }
    if (age.contains('week')) {
      final n =
          int.tryParse(RegExp(r'(\d+)').firstMatch(age)?.group(1) ?? '0') ?? 0;
      return n * 7 <= maxDays;
    }
    if (age.contains('month')) {
      return false; // 1+ months old → exclude
    }
    if (age.contains('year')) return false;
    return true;
  }

  // Current month/year for search query injection
  static String get _nowMonthYear {
    final now = DateTime.now();
    const months = [
      '',
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[now.month]} ${now.year}';
  }

  /// Home feed — personalized if logged in, else mixed subscriptions + trending
  static Future<List<YtVid>> home() async {
    // 1. Try personalized Innertube feed first
    final personalized = await _InnertubeApi.homeFeed();
    if (personalized.isNotEmpty) {
      // Filter personalized feed to recent too
      final recent = personalized.where((v) => _isRecent(v)).toList();
      return recent.isNotEmpty ? recent : personalized;
    }

    final results = <YtVid>[];

    // 2. Fetch from subscribed channels (latest 3 uploads each, parallel)
    final subs = await _SubStore.load();
    if (subs.isNotEmpty) {
      final channelFutures = subs.take(6).map((ch) async {
        try {
          final uploads = await _yt.channels.getUploads(ch.id).take(5).toList();
          return uploads
              .map((v) => YtVid.fromVideo(v))
              .where((v) => _isRecent(v))
              .toList();
        } catch (_) {
          return <YtVid>[];
        }
      });
      final all = await Future.wait(channelFutures);
      for (final list in all) {
        results.addAll(list);
      }
    }

    // 3. Trending — date-scoped queries for truly fresh content
    final trendingQueries = [
      'trending Tamil videos $_nowMonthYear',
      'trending India news $_nowMonthYear',
      'India trending music $_nowMonthYear',
      'viral India $_nowMonthYear',
      'top videos India this week',
    ];
    final trendingFutures = trendingQueries.map((q) async {
      try {
        final list = await _yt.search.search(q);
        return list
            .take(6)
            .map((v) => YtVid.fromVideo(v))
            .where((v) => _isRecent(v))
            .toList();
      } catch (_) {
        return <YtVid>[];
      }
    });
    final trending = await Future.wait(trendingFutures);
    for (final list in trending) {
      results.addAll(list);
    }

    // 4. Fallback: trending playlist (pick only recent)
    if (results.isEmpty) {
      try {
        const plId = 'PLrEnWoR732-BHrPp_Pm8_VleD68f9s14-';
        final plVideos = await _yt.playlists.getVideos(plId).take(25).toList();
        results.addAll(
          plVideos.map((v) => YtVid.fromPlaylist(v)).where((v) => _isRecent(v)),
        );
      } catch (_) {}
    }

    // De-dup by ID
    final seen = <String>{};
    return results.where((v) => seen.add(v.id)).toList();
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
      // 1. Personalized: fetch from subscribed channels first
      final subs = await _SubStore.load();
      if (subs.isNotEmpty) {
        final futures = subs.take(5).map((ch) async {
          final vids = <YtVid>[];
          try {
            await for (final v in _yt.channels.getUploads(ch.id)) {
              final vid = YtVid.fromVideo(v);
              // Shorts are typically < 60s
              if (_isRecent(vid)) vids.add(vid);
              if (vids.length >= 3) break;
            }
          } catch (_) {}
          return vids;
        }).toList();
        final results = await Future.wait(futures);
        for (final list in results) {
          out.addAll(list);
        }
      }
      // 2. Fill up to 20 from trending shorts search
      if (out.length < 20) {
        final list = await _yt.search.search('#shorts $_nowMonthYear');
        for (final v in list) {
          final vid = YtVid.fromVideo(v);
          if (_isRecent(vid) && !out.any((o) => o.id == vid.id)) {
            out.add(vid);
          }
          if (out.length >= 20) break;
        }
      }
      // Shuffle so subscriptions + trending mix naturally
      out.shuffle();
    } catch (_) {}
    return out;
  }

  /// Load first [limit] videos from a channel using StreamIterator for paginated loading
  static Stream<YtVid> channelVideoStream(String channelId) {
    return _yt.channels.getUploads(channelId).map((v) => YtVid.fromVideo(v));
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
        subs: ch.subscribersCount != null
            ? _fmtViews(ch.subscribersCount!)
            : '',
      );
    } catch (_) {
      return null;
    }
  }

  /// Related videos — recent only, based on video title keywords
  static Future<List<YtVid>> related(String videoId) async {
    final out = <YtVid>[];
    try {
      final v = await _yt.videos.get(videoId);
      // Use first 4 title words + current month to force recency
      final keywords = v.title.split(' ').take(4).join(' ');
      final q = '$keywords $_nowMonthYear';
      final list = await _yt.search.search(q);
      for (final r in list) {
        if (r.id.value == videoId) continue;
        final vid = YtVid.fromVideo(r);
        if (_isRecent(vid)) out.add(vid);
        if (out.length >= 15) break;
      }
      // If recency filter gave too few, relax it
      if (out.length < 5) {
        final list2 = await _yt.search.search(keywords);
        for (final r in list2) {
          if (r.id.value == videoId) continue;
          final vid = YtVid.fromVideo(r);
          if (!out.any((x) => x.id == vid.id)) out.add(vid);
          if (out.length >= 15) break;
        }
      }
    } catch (_) {}
    return out;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Background Audio — persistent, works even after app close
// ─────────────────────────────────────────────────────────────────────────────
class _BgAudio {
  // Delegates to the global YTAudioHandler registered in main.dart.
  // This runs inside Android's foreground service so audio persists
  // when the screen locks or the user presses Home.
  // Audio STOPS only when user clears the app from Recents (onTaskRemoved).

  static AudioPlayer get player => ytAudioHandler.player;
  // ignore: unused_field
  static String? _nowPlayingId; // tracks current playback id

  static Future<void> play(YtVid vid, {String? streamUrl}) async {
    // Always get a fresh URL — prevents stale CDN links

    _nowPlayingId = null;
    try {
      final url = streamUrl?.isNotEmpty == true
          ? streamUrl!
          : await _fetchBestAudioUrl(vid.id);
      _nowPlayingId = vid.id;
      await _startPlayback(vid, url);
    } catch (e) {
      debugPrint('BgAudio.play: $e');
      _nowPlayingId = null;
    }
  }

  static Future<String> _fetchBestAudioUrl(String videoId) async {
    final ytLocal = YoutubeExplode();
    try {
      final m = await ytLocal.videos.streamsClient
          .getManifest(videoId)
          .timeout(const Duration(seconds: 20));
      final audioStreams = m.audioOnly.sortByBitrate();
      // Prefer AAC (mp4a) codec
      StreamInfo? chosen;
      for (final s in audioStreams.reversed) {
        if (s.audioCodec.toLowerCase().contains('mp4a')) {
          chosen = s;
          break;
        }
      }
      chosen ??= audioStreams.last;
      return chosen.url.toString();
    } finally {
      ytLocal.close();
    }
  }

  static Future<void> _startPlayback(YtVid vid, String url) async {
    await ytAudioHandler.playUrl(
      url,
      MediaItem(
        id: vid.id,
        album: vid.channel,
        title: vid.title,
        artUri: Uri.parse(vid.thumb),
        displayTitle: vid.title,
        displaySubtitle: vid.channel,
      ),
    );
  }

  static Future<void> stop() async {
    _nowPlayingId = null;
    await ytAudioHandler.stop();
  }

  static bool get isPlaying => ytAudioHandler.player.playing;
}

// ─────────────────────────────────────────────────────────────────────────────
// Subscriptions store
// ─────────────────────────────────────────────────────────────────────────────
class _SubStore {
  static List<YtChannel> _cache = [];
  static const _kBlockedKey =
      'yt_blocked_channels'; // permanently removed channel IDs

  static Future<Set<String>> _loadBlocked() async {
    final p = await SharedPreferences.getInstance();
    return (p.getStringList(_kBlockedKey) ?? []).toSet();
  }

  static Future<void> _addBlocked(String id) async {
    final p = await SharedPreferences.getInstance();
    final set = (p.getStringList(_kBlockedKey) ?? []).toSet()..add(id);
    await p.setStringList(_kBlockedKey, set.toList());
  }

  static Future<List<YtChannel>> load() async {
    final p = await SharedPreferences.getInstance();
    final blocked = await _loadBlocked();
    final raw = p.getStringList(_kSprefsKey) ?? [];
    final all = raw
        .map((e) => YtChannel.fromJson(json.decode(e) as Map<String, dynamic>))
        .toList();
    // Keep only real UC channels that user hasn't permanently removed
    final valid = all
        .where((c) => c.id.startsWith('UC') && !blocked.contains(c.id))
        .toList();
    if (valid.length != all.length) {
      _cache = valid;
      await _save();
    } else {
      _cache = valid;
    }
    return _cache;
  }

  static Future<void> add(YtChannel ch) async {
    if (_cache.any((c) => c.id == ch.id)) return;
    _cache.add(ch);
    await _save();
  }

  static Future<void> remove(String id) async {
    _cache.removeWhere((c) => c.id == id);
    await _addBlocked(id); // permanently block — won't return from account API
    await _save();
  }

  static Future<void> setAll(List<YtChannel> channels) async {
    final blocked = await _loadBlocked();
    // Filter: real UC channels that user hasn't blocked
    _cache = channels
        .where((c) => c.id.startsWith('UC') && !blocked.contains(c.id))
        .toList();
    await _save();
  }

  static Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(
      _kSprefsKey,
      _cache.map((c) => json.encode(c.toJson())).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Root Screen
// ─────────────────────────────────────────────────────────────────────────────
class YouTubeScreen extends StatefulWidget {
  final String? initialVideoId;
  const YouTubeScreen({super.key, this.initialVideoId});
  @override
  State<YouTubeScreen> createState() => _YouTubeScreenState();
}

class _YouTubeScreenState extends State<YouTubeScreen> {
  int _tab = 0;
  YtVid? _miniVideo;
  YtAccount _account = _AccountStore.current;

  @override
  void initState() {
    super.initState();
    _AccountStore.load().then((_) {
      if (mounted) setState(() => _account = _AccountStore.current);
    });
    _AccountStore.addListener(_onAccountChanged);

    if (widget.initialVideoId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          final v = await _yt.videos.get(widget.initialVideoId);
          if (mounted) _openVideo(YtVid.fromVideo(v));
        } catch (_) {}
      });
    }

    // Sync account from webview cookies on open
    _syncAccountFromCookies();
  }

  @override
  void dispose() {
    _AccountStore.removeListener(_onAccountChanged);
    super.dispose();
  }

  void _onAccountChanged() {
    if (mounted) setState(() => _account = _AccountStore.current);
  }

  Future<void> _syncAccountFromCookies() async {
    await Future.delayed(const Duration(seconds: 2));
    final loggedIn = await _InnertubeApi.isLoggedIn();
    if (loggedIn) {
      final info = await _InnertubeApi.fetchAccountInfo();
      if (info != null && info.isSignedIn) {
        await _AccountStore.save(info);
      }
    }
  }

  void _openVideo(YtVid v) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, a1, a2) => _VideoPage(
          video: v,
          onMinimize: (vid) {
            setState(() => _miniVideo = vid);
          },
        ),
        transitionsBuilder: (_, anim, a2, child) => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 280),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      _HomeTab(onTap: _openVideo, account: _account),
      _ShortsTab(onTap: _openVideo),
      const _CreateTab(),
      _SubsTab(onTap: _openVideo, account: _account),
      _YouTab(
        onTap: _openVideo,
        onAccountChange: () {
          _syncAccountFromCookies();
          setState(() {});
        },
      ),
    ];

    return PopScope(
      // Back on YouTube root = exit the app directly, not back to Jarvis
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) SystemNavigator.pop();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0F0F0F),
        body: Stack(
          children: [
            IndexedStack(index: _tab, children: tabs),
            if (_miniVideo != null)
              _MiniPlayer(
                video: _miniVideo!,
                onExpand: () {
                  final v = _miniVideo!;
                  setState(() => _miniVideo = null);
                  _openVideo(v);
                },
                onClose: () {
                  setState(() => _miniVideo = null);
                  _BgAudio.stop();
                },
              ),
          ],
        ),
        bottomNavigationBar: _buildBottomNav(),
      ),
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
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _tab = i),
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        selected ? items[i].$2 : items[i].$1,
                        color: selected ? Colors.white : Colors.white38,
                        size: 22,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        items[i].$3,
                        style: TextStyle(
                          color: selected ? Colors.white : Colors.white38,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Top App Bar (shared) — shows real account avatar
// ─────────────────────────────────────────────────────────────────────────────
class _YtAppBar extends StatelessWidget implements PreferredSizeWidget {
  final void Function()? onSearch;
  final YtAccount? account;
  const _YtAppBar({this.onSearch, this.account});

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    final acct = account;
    return SafeArea(
      bottom: false,
      child: Container(
        height: 64,
        color: const Color(0xFF0F0F0F),
        padding: const EdgeInsets.fromLTRB(
          12,
          10,
          12,
          0,
        ), // extra top for breathing room
        child: Row(
          children: [
            // YouTube logo
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 28,
                  height: 20,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF0000),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.play_arrow,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                const Text(
                  'YouTube',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.cast, color: Colors.white, size: 22),
              onPressed: () {},
              padding: const EdgeInsets.all(8),
            ),
            IconButton(
              icon: const Icon(
                Icons.notifications_none,
                color: Colors.white,
                size: 22,
              ),
              onPressed: () {},
              padding: const EdgeInsets.all(8),
            ),
            if (onSearch != null)
              IconButton(
                icon: const Icon(Icons.search, color: Colors.white, size: 22),
                onPressed: onSearch,
                padding: const EdgeInsets.all(8),
              ),
            // Real account avatar
            _AccountAvatar(account: acct, size: 14),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Account Avatar Widget
// ─────────────────────────────────────────────────────────────────────────────
class _AccountAvatar extends StatelessWidget {
  final YtAccount? account;
  final double size;
  const _AccountAvatar({this.account, this.size = 14});

  @override
  Widget build(BuildContext context) {
    final radius = size;
    if (account != null &&
        account!.isSignedIn &&
        account!.photoUrl.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: NetworkImage(account!.photoUrl),
        backgroundColor: const Color(0xFF6C63FF),
        onBackgroundImageError: (_, __) {},
      );
    }
    if (account != null && account!.isSignedIn && account!.name.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: const Color(0xFF6C63FF),
        child: Text(
          account!.name[0].toUpperCase(),
          style: TextStyle(
            color: Colors.white,
            fontSize: radius * 0.9,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFF6C63FF),
      child: Icon(Icons.person, size: radius * 1.1, color: Colors.white),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Home Tab — personalized feed
// ─────────────────────────────────────────────────────────────────────────────
class _HomeTab extends StatefulWidget {
  final void Function(YtVid) onTap;
  final YtAccount account;
  const _HomeTab({required this.onTap, required this.account});
  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> with AutomaticKeepAliveClientMixin {
  List<YtVid> _videos = [];
  bool _loading = true;
  final _cats = [
    'All',
    'Music',
    'Gaming',
    'News',
    'Sports',
    'Tech',
    'Movies',
    'Live',
    'Tamil',
    'Finance',
  ];
  String _selCat = 'All';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_HomeTab old) {
    super.didUpdateWidget(old);
    // Refresh when account changes
    if (old.account.email != widget.account.email) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    List<YtVid> vids = await _YtSvc.home();
    if (_selCat != 'All') {
      vids = await _YtSvc.search(_selCat);
    }
    if (mounted)
      setState(() {
        _videos = vids;
        _loading = false;
      });
  }

  Future<void> _selectCat(String cat) async {
    setState(() {
      _selCat = cat;
      _loading = true;
    });
    final vids = cat == 'All' ? await _YtSvc.home() : await _YtSvc.search(cat);
    if (mounted)
      setState(() {
        _videos = vids;
        _loading = false;
      });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: _YtAppBar(
        onSearch: () => _pushSearch(context),
        account: widget.account,
      ),
      body: RefreshIndicator(
        color: const Color(0xFFFF0000),
        backgroundColor: const Color(0xFF1A1A1A),
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            // Category chips
            SliverToBoxAdapter(
              child: SizedBox(
                height: 46,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  itemCount: _cats.length,
                  itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => _selectCat(_cats[i]),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: _selCat == _cats[i]
                              ? Colors.white
                              : const Color(0xFF272727),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _cats[i],
                          style: TextStyle(
                            color: _selCat == _cats[i]
                                ? Colors.black
                                : Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Personalized banner
            if (widget.account.isSignedIn)
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A2A1A),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      _AccountAvatar(account: widget.account, size: 12),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Personalized for ${widget.account.name}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (_loading)
              const SliverFillRemaining(
                child: Center(
                  child: CircularProgressIndicator(color: Color(0xFFFF0000)),
                ),
              )
            else if (_videos.isEmpty)
              const SliverFillRemaining(
                child: Center(
                  child: Text(
                    'Could not load feed.\nPull down to retry.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white38),
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => _VCard(
                    video: _videos[i],
                    onTap: () => widget.onTap(_videos[i]),
                  ),
                  childCount: _videos.length,
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _pushSearch(BuildContext ctx) {
    Navigator.of(
      ctx,
    ).push(MaterialPageRoute(builder: (_) => _SearchPage(onTap: widget.onTap)));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Search Page
// ─────────────────────────────────────────────────────────────────────────────
class _SearchPage extends StatefulWidget {
  final void Function(YtVid) onTap;
  const _SearchPage({required this.onTap});
  @override
  State<_SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<_SearchPage> {
  final _ctrl = TextEditingController();
  List<YtVid> _results = [];
  List<String> _suggestions = [];
  bool _loading = false;
  bool _showSuggestions = false;
  bool _suppressSuggestions =
      false; // prevents re-trigger when setting ctrl.text
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.removeListener(_onTextChanged);
    _ctrl.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (_suppressSuggestions) return;
    final q = _ctrl.text.trim();
    if (q.isEmpty) {
      setState(() {
        _suggestions = [];
        _showSuggestions = false;
      });
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _fetchSuggestions(q),
    );
  }

  Future<void> _fetchSuggestions(String q) async {
    try {
      final s = await _yt.search.getQuerySuggestions(q);
      if (mounted)
        setState(() {
          _suggestions = s.take(7).toList();
          _showSuggestions = _suggestions.isNotEmpty;
        });
    } catch (_) {}
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) return;
    _debounce?.cancel();
    _suppressSuggestions = true;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _results = [];
      _showSuggestions = false;
      _suggestions = [];
    });
    _ctrl.text = q;
    final r = await _YtSvc.search(q);
    if (mounted)
      setState(() {
        _results = r;
        _loading = false;
      });
    // Small delay so setText event doesn't re-trigger suggestions
    await Future.delayed(const Duration(milliseconds: 200));
    _suppressSuggestions = false;
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
              onPressed: () {
                _ctrl.clear();
                setState(() {
                  _results = [];
                  _suggestions = [];
                  _showSuggestions = false;
                });
              },
            ),
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white),
            onPressed: () => _search(_ctrl.text),
          ),
        ],
      ),
      body: Column(
        children: [
          // Suggestions dropdown
          if (_showSuggestions)
            Container(
              color: const Color(0xFF1A1A1A),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _suggestions.length,
                itemBuilder: (_, i) {
                  final s = _suggestions[i];
                  return ListTile(
                    dense: true,
                    leading: const Icon(
                      Icons.search,
                      color: Colors.white38,
                      size: 18,
                    ),
                    title: Text(
                      s,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    trailing: IconButton(
                      icon: const Icon(
                        Icons.north_west,
                        color: Colors.white38,
                        size: 16,
                      ),
                      onPressed: () {
                        _ctrl.text = s;
                        _ctrl.selection = TextSelection.collapsed(
                          offset: s.length,
                        );
                        setState(() => _showSuggestions = false);
                      },
                    ),
                    onTap: () => _search(s),
                  );
                },
              ),
            ),
          // Results
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFFFF0000)),
                  )
                : _results.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.search,
                          size: 72,
                          color: Colors.white12,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Search for videos, channels\nor playlists',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white38, fontSize: 14),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (_, i) => _VCard(
                      video: _results[i],
                      onTap: () {
                        widget.onTap(_results[i]);
                      },
                      compact: true,
                    ),
                  ),
          ),
        ],
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
  @override
  State<_ShortsTab> createState() => _ShortsTabState();
}

class _ShortsTabState extends State<_ShortsTab>
    with AutomaticKeepAliveClientMixin {
  List<YtVid> _shorts = [];
  bool _loading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final v = await _YtSvc.shorts();
    if (mounted)
      setState(() {
        _shorts = v;
        _loading = false;
      });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _YtAppBar(
        onSearch: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => _SearchPage(onTap: widget.onTap)),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF0000)),
            )
          : _shorts.isEmpty
          ? const Center(
              child: Text(
                'No shorts loaded',
                style: TextStyle(color: Colors.white38),
              ),
            )
          : PageView.builder(
              scrollDirection: Axis.vertical,
              itemCount: _shorts.length,
              itemBuilder: (_, i) => _ShortCard(
                video: _shorts[i],
                onTap: () => widget.onTap(_shorts[i]),
              ),
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
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            video.thumb,
            fit: BoxFit.cover,
            errorBuilder: (_, a, b) =>
                Container(color: const Color(0xFF1A1A1A)),
          ),
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black87],
              ),
            ),
          ),
          Positioned(
            bottom: 80,
            left: 12,
            right: 60,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  video.channel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  video.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 80,
            right: 8,
            child: Column(
              children: [
                _ShortAction(Icons.thumb_up_outlined, 'Like'),
                const SizedBox(height: 20),
                _ShortAction(Icons.comment_outlined, 'Comment'),
                const SizedBox(height: 20),
                _ShortAction(Icons.share_outlined, 'Share'),
              ],
            ),
          ),
          const Positioned(
            top: 12,
            left: 16,
            child: Text(
              'Shorts',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShortAction extends StatelessWidget {
  final IconData icon;
  final String label;
  const _ShortAction(this.icon, this.label);
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Icon(icon, color: Colors.white, size: 28),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(color: Colors.white, fontSize: 11)),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Create Tab placeholder
// ─────────────────────────────────────────────────────────────────────────────
class _CreateTab extends StatelessWidget {
  const _CreateTab();
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF0F0F0F),
    appBar: const _YtAppBar(),
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.videocam_outlined, size: 80, color: Colors.white24),
          const SizedBox(height: 16),
          const Text(
            'Create',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Upload a video or Go live',
            style: TextStyle(color: Colors.white54),
          ),
          const SizedBox(height: 24),
          _CreateBtn(Icons.upload, 'Upload a video', () {}),
          const SizedBox(height: 12),
          _CreateBtn(Icons.circle, 'Create a Short', () {}),
          const SizedBox(height: 12),
          _CreateBtn(Icons.live_tv, 'Go live', () {}),
        ],
      ),
    ),
  );
}

class _CreateBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _CreateBtn(this.icon, this.label, this.onTap);
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      width: 240,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF272727),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 22),
          const SizedBox(width: 14),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Subscriptions Tab — shows channels from Google Account + manual add
// ─────────────────────────────────────────────────────────────────────────────
class _SubsTab extends StatefulWidget {
  final void Function(YtVid) onTap;
  final YtAccount account;
  const _SubsTab({required this.onTap, required this.account});
  @override
  State<_SubsTab> createState() => _SubsTabState();
}

class _SubsTabState extends State<_SubsTab> with AutomaticKeepAliveClientMixin {
  List<YtChannel> _channels = [];
  YtChannel? _selChannel;
  List<YtVid> _videos = [];
  bool _loadingVids = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _loadingChans = true;
  bool _showingFeed = false;
  List<YtVid> _subsFeed = [];
  bool _loadingFeed = false;
  TextEditingController _addCtrl = TextEditingController();
  StreamIterator<YtVid>? _uploadIter;
  final _channelScrollCtrl = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadChannels();
    _channelScrollCtrl.addListener(_onChannelScroll);
  }

  @override
  void dispose() {
    _channelScrollCtrl.dispose();
    _uploadIter?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(_SubsTab old) {
    super.didUpdateWidget(old);
    if (old.account.email != widget.account.email) _loadChannels();
  }

  void _onChannelScroll() {
    if (_channelScrollCtrl.hasClients &&
        _channelScrollCtrl.position.pixels >=
            _channelScrollCtrl.position.maxScrollExtent - 300) {
      _loadMoreVideos();
    }
  }

  Future<void> _loadChannels() async {
    setState(() => _loadingChans = true);

    List<YtChannel> channels = [];

    // Only load what the user explicitly saved locally
    final saved = await _SubStore.load();
    channels = List<YtChannel>.from(saved);

    // If Google-logged in, MERGE account subs — but don't overwrite local
    final loggedIn = await _InnertubeApi.isLoggedIn();
    if (loggedIn) {
      try {
        final fromAccount = await _InnertubeApi.subscribedChannels();
        for (final ch in fromAccount) {
          if (!channels.any((c) => c.id == ch.id)) {
            channels.add(ch);
          }
        }
        // Persist merged list — setAll() filters out blocked channels
        await _SubStore.setAll(channels);
        // MUST re-load: setAll filters blocked IDs but local `channels` var is unfiltered
        channels = await _SubStore.load();
      } catch (e) {
        debugPrint('Loading account subs: $e');
      }
    } else {
      // Not logged in — still apply block filter
      channels = await _SubStore.load();
    }

    if (mounted)
      setState(() {
        _channels = channels;
        _loadingChans = false;
      });
    // Don't auto-select a channel — let user pick
    _selChannel = null;
    _showingFeed = true;

    if (loggedIn) _loadSubsFeed();
  }

  Future<void> _loadSubsFeed() async {
    setState(() => _loadingFeed = true);
    final feed = await _InnertubeApi.subscriptionsFeed();
    if (mounted)
      setState(() {
        _subsFeed = feed;
        _loadingFeed = false;
      });
  }

  Future<void> _selectChannel(YtChannel ch) async {
    await _uploadIter?.cancel();
    _uploadIter = null;
    setState(() {
      _selChannel = ch;
      _loadingVids = true;
      _videos = [];
      _showingFeed = false;
      _hasMore = true;
      _loadingMore = false;
    });
    _uploadIter = StreamIterator(_YtSvc.channelVideoStream(ch.id));
    await _loadMoreVideos(isInitial: true);
  }

  Future<void> _loadMoreVideos({bool isInitial = false}) async {
    if (_loadingMore || !_hasMore || _uploadIter == null) return;
    setState(() => _loadingMore = true);
    int loaded = 0;
    while (loaded < 20) {
      bool hasNext = false;
      try {
        hasNext = await _uploadIter!.moveNext().timeout(
          const Duration(seconds: 15),
        );
      } catch (_) {
        break;
      }
      if (!hasNext) {
        if (mounted) setState(() => _hasMore = false);
        break;
      }
      if (mounted) setState(() => _videos.add(_uploadIter!.current));
      loaded++;
    }
    if (mounted)
      setState(() {
        _loadingMore = false;
        if (isInitial) _loadingVids = false;
      });
  }

  Future<void> _addChannel(String query) async {
    if (query.trim().isEmpty) return;
    final ch = await _YtSvc.findChannel(query.trim());
    if (ch == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Channel not found'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    await _SubStore.add(ch);
    await _loadChannels();
    _addCtrl.clear();
  }

  /// Shows an unsubscribe confirmation dialog, then removes channel if confirmed
  Future<void> _confirmRemove(YtChannel ch) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text(
          'Unsubscribe from ${ch.name}?',
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: const Text(
          'You can resubscribe anytime.',
          style: TextStyle(color: Colors.white54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Unsubscribe',
              style: TextStyle(color: Color(0xFFFF0000)),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _SubStore.remove(ch.id);
      if (mounted) {
        setState(() {
          _channels.removeWhere((c) => c.id == ch.id);
          _selChannel = null;
          _showingFeed = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unsubscribed from ${ch.name}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: _YtAppBar(
        onSearch: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => _SearchPage(onTap: widget.onTap)),
        ),
        account: widget.account,
      ),
      body: _loadingChans
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF0000)),
            )
          : Column(
              children: [
                // ── Tabs: All / channel avatars ──────────────────────────────
                SizedBox(
                  height: 100,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    children: [
                      // "All" / Feed button
                      Padding(
                        padding: const EdgeInsets.only(right: 16),
                        child: GestureDetector(
                          onTap: () => setState(() {
                            _showingFeed = true;
                            _selChannel = null;
                          }),
                          child: Column(
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: _showingFeed
                                      ? const Color(0xFFFF0000)
                                      : const Color(0xFF272727),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.dynamic_feed,
                                  color: Colors.white,
                                  size: 26,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'All',
                                style: TextStyle(
                                  color: _showingFeed
                                      ? Colors.white
                                      : Colors.white54,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Add button
                      Padding(
                        padding: const EdgeInsets.only(right: 16),
                        child: GestureDetector(
                          onTap: () => _showAddDialog(context),
                          child: Column(
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF272727),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white24),
                                ),
                                child: const Icon(
                                  Icons.add,
                                  color: Colors.white,
                                  size: 26,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Add',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Channel avatars
                      ..._channels.map(
                        (ch) => Padding(
                          padding: const EdgeInsets.only(right: 16),
                          child: GestureDetector(
                            onTap: () => _selectChannel(ch),
                            onLongPress: () => _confirmRemove(ch),
                            child: Column(
                              children: [
                                Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: _selChannel?.id == ch.id
                                          ? const Color(0xFFFF0000)
                                          : Colors.transparent,
                                      width: 2.5,
                                    ),
                                  ),
                                  child: ClipOval(
                                    child: ch.thumb.isNotEmpty
                                        ? Image.network(
                                            ch.thumb,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, a, b) =>
                                                _avatarFallback(ch.name),
                                          )
                                        : _avatarFallback(ch.name),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                SizedBox(
                                  width: 60,
                                  child: Text(
                                    ch.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: _selChannel?.id == ch.id
                                          ? Colors.white
                                          : Colors.white60,
                                      fontSize: 11,
                                      fontWeight: _selChannel?.id == ch.id
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(color: Colors.white12, height: 1),

                // ── Content area ─────────────────────────────────────────────
                if (_showingFeed)
                  Expanded(
                    child: _loadingFeed
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: Color(0xFFFF0000),
                            ),
                          )
                        : _subsFeed.isEmpty
                        ? _emptySubsState(context)
                        : ListView.builder(
                            itemCount: _subsFeed.length,
                            itemBuilder: (_, i) => _VCard(
                              video: _subsFeed[i],
                              onTap: () => widget.onTap(_subsFeed[i]),
                              compact: true,
                            ),
                          ),
                  )
                else if (_selChannel != null) ...[
                  // Channel header
                  Container(
                    color: const Color(0xFF1A1A1A),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        ClipOval(
                          child: _selChannel!.thumb.isNotEmpty
                              ? Image.network(
                                  _selChannel!.thumb,
                                  width: 40,
                                  height: 40,
                                  fit: BoxFit.cover,
                                )
                              : _avatarFallback(_selChannel!.name),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _selChannel!.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                              if (_selChannel!.subs.isNotEmpty)
                                Text(
                                  _selChannel!.subs,
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _confirmRemove(_selChannel!),
                          icon: const Icon(
                            Icons.notifications_outlined,
                            size: 16,
                          ),
                          label: const Text('Subscribed'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white24),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            textStyle: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _loadingVids
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: Color(0xFFFF0000),
                            ),
                          )
                        : _videos.isEmpty
                        ? const Center(
                            child: Text(
                              'No videos found',
                              style: TextStyle(color: Colors.white38),
                            ),
                          )
                        : ListView.builder(
                            controller: _channelScrollCtrl,
                            itemCount:
                                _videos.length +
                                (_loadingMore || _hasMore ? 1 : 0),
                            itemBuilder: (_, i) {
                              if (i == _videos.length) {
                                return Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: _loadingMore
                                      ? const Center(
                                          child: CircularProgressIndicator(
                                            color: Color(0xFFFF0000),
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : TextButton(
                                          onPressed: _loadMoreVideos,
                                          child: const Text(
                                            'Load more',
                                            style: TextStyle(
                                              color: Color(0xFFFF0000),
                                            ),
                                          ),
                                        ),
                                );
                              }
                              return _VCard(
                                video: _videos[i],
                                onTap: () => widget.onTap(_videos[i]),
                                compact: true,
                              );
                            },
                          ),
                  ),
                ] else
                  Expanded(child: _emptySubsState(context)),
              ],
            ),
    );
  }

  Widget _emptySubsState(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.subscriptions_outlined,
          size: 80,
          color: Colors.white12,
        ),
        const SizedBox(height: 16),
        const Text(
          'Your subscriptions will appear here',
          style: TextStyle(color: Colors.white54, fontSize: 15),
        ),
        const SizedBox(height: 8),
        const Text(
          'Sign in to sync your YouTube subscriptions automatically',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white30, fontSize: 13),
        ),
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
      ],
    ),
  );

  Widget _avatarFallback(String name) => Container(
    width: 56,
    height: 56,
    color: const Color(0xFF333333),
    child: Center(
      child: Text(
        name.isEmpty ? '?' : name[0].toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.bold,
        ),
      ),
    ),
  );

  void _showAddDialog(BuildContext context) {
    _addCtrl.clear();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Add Channel', style: TextStyle(color: Colors.white)),
        content: Autocomplete<String>(
          optionsBuilder: (TextEditingValue tv) async {
            if (tv.text.isEmpty) return const Iterable<String>.empty();
            try {
              final queries = await _yt.search.getQuerySuggestions(tv.text);
              return queries;
            } catch (_) {
              return const Iterable<String>.empty();
            }
          },
          onSelected: (String selection) {
            _addCtrl.text = selection;
          },
          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
            _addCtrl = controller;
            return TextField(
              controller: controller,
              focusNode: focusNode,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: '@channelname or channel name',
                hintStyle: TextStyle(color: Colors.white38),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFFFF0000)),
                ),
              ),
              onSubmitted: (q) {
                Navigator.pop(context);
                _addChannel(q);
              },
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                color: const Color(0xFF272727),
                elevation: 4.0,
                child: SizedBox(
                  width: 250,
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: options.length,
                    itemBuilder: (context, index) {
                      final option = options.elementAt(index);
                      return ListTile(
                        title: Text(
                          option,
                          style: const TextStyle(color: Colors.white),
                        ),
                        onTap: () => onSelected(option),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF0000),
            ),
            onPressed: () {
              Navigator.pop(context);
              _addChannel(_addCtrl.text);
            },
            child: const Text('Add', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// You Tab — WebView for Google sign-in + account management
// ─────────────────────────────────────────────────────────────────────────────
class _YouTab extends StatefulWidget {
  final void Function(YtVid) onTap;
  final VoidCallback onAccountChange;
  const _YouTab({required this.onTap, required this.onAccountChange});
  @override
  State<_YouTab> createState() => _YouTabState();
}

class _YouTabState extends State<_YouTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // Ad-blocking script — injects CSS to hide ads and sponsorship banners
  static const _adblockCss = '''
    (function() {
      const style = document.createElement('style');
      style.textContent = `
        ytm-promoted-sparkles-web-renderer, 
        ytm-paid-content-overlay-renderer,
        ytm-companion-ad-renderer,
        ytm-display-ad-renderer,
        ytm-full-bleed-interstitial-ad,
        .ytd-promoted-sparkles-web-renderer,
        .ytd-compact-promoted-video-renderer,
        [class*="ad-showing"],
        [class*="advertisement"],
        .video-ads,
        .ytp-ad-module,
        .ytp-ad-image-overlay,
        .ytp-ad-text-overlay,
        .ytp-ad-skip-button-container,
        ytm-ads-renderer,
        .masthead-ad,
        [data-ad-slot] { display: none !important; }
      `;
      document.head.appendChild(style);
    })();
  ''';

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final acc = _AccountStore.current;

    if (!acc.isSignedIn) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.account_circle, size: 80, color: Colors.white54),
            const SizedBox(height: 16),
            const Text(
              'Sign in to YouTube',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Access your subscriptions & personalized feed',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 12,
                ),
              ),
              onPressed: () {
                _openGoogleSignIn();
              },
              child: const Text(
                'Continue with Google',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
    }

    // Signed in Native Dashboard
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 36,
              backgroundImage: acc.photoUrl.isNotEmpty
                  ? NetworkImage(acc.photoUrl)
                  : null,
              child: acc.photoUrl.isEmpty
                  ? Text(
                      acc.name.isNotEmpty ? acc.name[0] : 'U',
                      style: const TextStyle(fontSize: 24),
                    )
                  : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    acc.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    acc.email.isNotEmpty
                        ? acc.email
                        : '@${acc.name.replaceAll(' ', '').toLowerCase()}',
                    style: const TextStyle(color: Colors.white54, fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
        _buildListTile(
          Icons.history,
          'History',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => YtHistoryScreen(
                onTap: (v) {
                  Navigator.of(context).pop();
                  widget.onTap(v);
                },
              ),
            ),
          ),
        ),
        _buildListTile(
          Icons.playlist_play,
          'Playlists',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => YtPlaylistsScreen(
                onTap: (v) {
                  Navigator.of(context).pop();
                  widget.onTap(v);
                },
              ),
            ),
          ),
        ),
        _buildListTile(
          Icons.thumb_up_alt_outlined,
          'Liked videos',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => YtLikedScreen(
                onTap: (v) {
                  Navigator.of(context).pop();
                  widget.onTap(v);
                },
              ),
            ),
          ),
        ),
        _buildListTile(
          Icons.bookmark_outlined,
          'Saved videos',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => YtSavedScreen(
                onTap: (v) {
                  Navigator.of(context).pop();
                  widget.onTap(v);
                },
              ),
            ),
          ),
        ),
        _buildListTile(
          Icons.download_done_outlined,
          'Downloads',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const YTDownloaderScreen()),
            );
          },
        ),
        const SizedBox(height: 16),
        const Divider(color: Colors.white24),
        _buildListTile(
          Icons.settings,
          'Settings',
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const YtSettingsScreen())),
        ),
        _buildListTile(Icons.help_outline, 'Help & Feedback'),
      ],
    );
  }

  Widget _buildListTile(IconData icon, String title, {VoidCallback? onTap}) {
    return ListTile(
      leading: Icon(icon, color: Colors.white),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      trailing: const Icon(
        Icons.chevron_right,
        color: Colors.white54,
        size: 20,
      ),
      onTap: onTap ?? () {},
    );
  }

  void _openGoogleSignIn() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetContext) => Container(
        height: MediaQuery.of(context).size.height * 0.9,
        decoration: const BoxDecoration(
          color: Color(0xFF0F0F0F),
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          child: _buildWebView(bottomSheetContext),
        ),
      ),
    );
  }

  Widget _buildWebView(BuildContext dialogContext) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F0F),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(dialogContext).pop(),
        ),
        title: const Text(
          'Sign in with Google',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
      ),
      body: SafeArea(
        child: InAppWebView(
          initialUrlRequest: URLRequest(
            url: WebUri(
              'https://accounts.google.com/ServiceLogin?service=youtube',
            ),
          ),
          initialSettings: InAppWebViewSettings(
            transparentBackground: true,
            useShouldOverrideUrlLoading: true,
            verticalScrollBarEnabled: false,
            horizontalScrollBarEnabled: false,
            supportZoom: false,
            sharedCookiesEnabled: true,
            thirdPartyCookiesEnabled: true,
            userAgent:
                "Mozilla/5.0 (Linux; Android 10; SM-G975F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.120 Mobile Safari/537.36",
          ),
          onWebViewCreated: (_) {},
          onLoadStop: (ctrl, url) async {
            await ctrl.evaluateJavascript(source: _adblockCss);
            final urlStr = url.toString();
            if (urlStr.contains('youtube.com') &&
                !urlStr.contains('accounts.google')) {
              final loggedIn = await _InnertubeApi.isLoggedIn();
              if (loggedIn) {
                final nameJs = await ctrl.evaluateJavascript(
                  source: '''
                  (function() {
                    try {
                      var el = document.querySelector('ytm-account-option-renderer .account-name');
                      if (el) return el.textContent.trim();
                      el = document.querySelector('.account-name, [class*="account-name"]');
                      if (el) return el.textContent.trim();
                    } catch(e) {}
                    return '';
                  })()
                ''',
                );
                final photoJs = await ctrl.evaluateJavascript(
                  source: '''
                  (function() {
                    try {
                      var img = document.querySelector('img.account-avatar, ytm-account-option-renderer img');
                      if (img) return img.src;
                    } catch(e) {}
                    return '';
                  })()
                ''',
                );
                final name = (nameJs?.toString() ?? '')
                    .replaceAll('"', '')
                    .trim();
                final photo = (photoJs?.toString() ?? '')
                    .replaceAll('"', '')
                    .trim();

                if (name.isNotEmpty) {
                  final account = YtAccount(
                    name: name,
                    email: '',
                    photoUrl: photo,
                  );
                  await _AccountStore.save(account);
                } else {
                  final info = await _InnertubeApi.fetchAccountInfo();
                  if (info != null && info.isSignedIn) {
                    await _AccountStore.save(info);
                  } else {
                    await _AccountStore.save(
                      const YtAccount(
                        name: 'YouTube User',
                        email: '',
                        photoUrl: '',
                      ),
                    );
                  }
                }
                if (mounted) {
                  Navigator.of(dialogContext).pop();
                }
                widget.onAccountChange();
              }
            }
          },
          shouldOverrideUrlLoading: (controller, action) async {
            final url = action.request.url.toString();
            final reg = RegExp(r'(?:v=|youtu\.be/|shorts/)([^&?\s]+)');
            final match = reg.firstMatch(url);
            if (match != null) {
              final String vidId = match.group(1) ?? '';
              if (vidId.isNotEmpty) {
                try {
                  final v = await _yt.videos.get(vidId);
                  if (mounted) {
                    Navigator.of(dialogContext).pop();
                    widget.onTap(YtVid.fromVideo(v));
                  }
                } catch (_) {}
                return NavigationActionPolicy.CANCEL;
              }
            }
            return NavigationActionPolicy.ALLOW;
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Video Card (vertical feed + compact/search mode)
// ─────────────────────────────────────────────────────────────────────────────
class _VCard extends StatelessWidget {
  final YtVid video;
  final VoidCallback onTap;
  final bool compact;
  const _VCard({
    required this.video,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: _Thumb(url: video.thumb, w: 160, h: 90),
                  ),
                  if (video.duration.isNotEmpty)
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: _DurBadge(video.duration),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      video.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      video.channel,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                    ),
                    if (video.viewCount.isNotEmpty || video.age.isNotEmpty)
                      Text(
                        '${video.viewCount}${video.viewCount.isNotEmpty && video.age.isNotEmpty ? ' • ' : ''}${video.age}',
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.more_vert,
                  color: Colors.white38,
                  size: 18,
                ),
                onPressed: () {},
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
      );
    }
    // Full-width card (home feed)
    return InkWell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              _Thumb(url: video.thumb, w: double.infinity, h: 210),
              if (video.duration.isNotEmpty)
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: _DurBadge(video.duration),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CircleAvatar(
                  radius: 18,
                  backgroundColor: Color(0xFF333333),
                  child: Icon(Icons.person, size: 18, color: Colors.white60),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        video.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        [
                          video.channel,
                          if (video.viewCount.isNotEmpty) video.viewCount,
                          if (video.age.isNotEmpty) video.age,
                        ].join(' • '),
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.more_vert,
                    color: Colors.white54,
                    size: 20,
                  ),
                  onPressed: () {},
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Video Player Page
// ─────────────────────────────────────────────────────────────────────────────
class _VideoPage extends StatefulWidget {
  final YtVid video;
  final void Function(YtVid) onMinimize;
  const _VideoPage({required this.video, required this.onMinimize});
  @override
  State<_VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<_VideoPage> {
  final _ytLocal = YoutubeExplode();
  VideoPlayerController? _vpc;
  AudioPlayer? _adaptiveAudio; // Synced audio for 720p+ dual-stream mode
  bool _isAdaptive = false; // true = videoOnly+audioOnly playing together
  Timer? _syncTimer; // Periodic drift correction (audio vs video)
  String? _actualQualityLabel; // Displayed quality badge, e.g. '720p' or '360p'
  bool _loading = true, _error = false, _audioOnly = false, _ctrlVisible = true;
  bool _isFullscreen = false;
  bool _liked = false, _disliked = false, _saved = false;
  bool _subscribed = false;
  Timer? _hideTimer;
  List<YtVid> _related = [];
  String _desc = '';
  String? _audioStreamUrl;
  bool _descExpanded = false;

  // ── Quality helpers ──────────────────────────────────────────────────────
  static int _qHeight(String label) {
    const m = {
      '144p': 144,
      '240p': 240,
      '360p': 360,
      '480p': 480,
      '720p': 720,
      '1080p': 1080,
      '1440p': 1440,
      '2160p': 2160,
    };
    return m[label.toLowerCase()] ?? 720;
  }

  @override
  void initState() {
    super.initState();
    _initPlayer();
    _loadMeta();
    _loadRelated();
    _addToHistory();
    _checkSavedState();
  }

  Future<void> _checkSavedState() async {
    final prefs = await SharedPreferences.getInstance();
    final likedRaw = prefs.getStringList('yt_liked') ?? [];
    final savedRaw = prefs.getStringList('yt_saved') ?? [];
    final subs = await _SubStore.load();
    if (mounted) {
      setState(() {
        _liked = likedRaw.any(
          (e) => (json.decode(e) as Map)['id'] == widget.video.id,
        );
        _saved = savedRaw.any(
          (e) => (json.decode(e) as Map)['id'] == widget.video.id,
        );
        _subscribed = subs.any((c) => c.id == widget.video.channelId);
      });
    }
  }

  Future<void> _addToHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final v = widget.video;
    final raw = prefs.getStringList('yt_history') ?? [];
    final entry = json.encode({
      'id': v.id,
      'title': v.title,
      'channel': v.channel,
      'thumb': v.thumb,
      'duration': v.duration,
      'viewCount': v.viewCount,
      'age': v.age,
      'channelId': v.channelId,
    });
    raw.removeWhere((e) => (json.decode(e) as Map)['id'] == v.id);
    raw.insert(0, entry);
    await prefs.setStringList('yt_history', raw.take(100).toList());
  }

  Future<void> _initPlayer() async {
    setState(() {
      _loading = true;
      _error = false;
      _audioOnly = false;
    });

    final prefs = await SharedPreferences.getInstance();
    final prefQuality = prefs.getString('yt_video_quality') ?? '480p';
    final isSmart = prefQuality == 'Smart';
    final targetH = isSmart ? 9999 : _qHeight(prefQuality);

    // Headers for ExoPlayer / just_audio CDN requests
    const dlHdrs = {
      'User-Agent':
          'com.google.android.youtube/19.09.37 (Linux; U; Android 11) gzip',
      'Referer': 'https://www.youtube.com/',
    };

    // ── PASS 1: InnerTube ANDROID client (pre-signed URLs, no cipher) ─────────
    try {
      final bundle = await _InnertubeApi.getAdaptiveStreams(widget.video.id);
      if (bundle != null) {
        final audioFmt = bundle.bestAudio;
        final videoFmt = bundle.videoForQuality(targetH);
        debugPrint(
          '▶ InnerTube quality chosen: ${videoFmt?['height']}p  audio: ${audioFmt?['mimeType']}',
        );

        if (videoFmt != null && audioFmt != null) {
          final videoUrl = videoFmt['url'] as String?;
          final audioUrl = audioFmt['url'] as String?;
          if (videoUrl != null && audioUrl != null) {
            try {
              _audioStreamUrl = audioUrl;
              final ctrl = VideoPlayerController.networkUrl(
                Uri.parse(videoUrl),
                httpHeaders: dlHdrs,
              );
              await ctrl.initialize().timeout(const Duration(seconds: 25));
              await ctrl.setVolume(0.0); // audio comes from _adaptiveAudio

              final adAudio = AudioPlayer();
              await adAudio
                  .setUrl(audioUrl, headers: Map<String, String>.from(dlHdrs))
                  .timeout(const Duration(seconds: 15));

              _vpc = ctrl;
              _adaptiveAudio = adAudio;
              _isAdaptive = true;
              _actualQualityLabel = '${videoFmt['height']}p';
              _vpc!.addListener(_syncAudioState);
              await _vpc!.play();
              await _adaptiveAudio!.play();
              _startSyncTimer();
              WakelockPlus.enable();
              if (mounted) setState(() => _loading = false);
              _scheduleHide();
              return; // ✅ InnerTube adaptive success
            } catch (e) {
              debugPrint('InnerTube adaptive init failed: $e');
              _syncTimer?.cancel();
              _syncTimer = null;
              await _vpc?.dispose();
              _vpc = null;
              await _adaptiveAudio?.dispose();
              _adaptiveAudio = null;
              _isAdaptive = false;
            }
          }
        }

        // Muxed fallback from InnerTube bundle
        final muxedFmt = bundle.muxedForQuality(targetH);
        final muxedUrl = muxedFmt?['url'] as String?;
        if (muxedUrl != null) {
          try {
            _vpc = VideoPlayerController.networkUrl(
              Uri.parse(muxedUrl),
              httpHeaders: dlHdrs,
            );
            await _vpc!.initialize().timeout(const Duration(seconds: 20));
            _isAdaptive = false;
            _actualQualityLabel = '${muxedFmt!['height']}p';
            await _vpc!.play();
            WakelockPlus.enable();
            if (mounted) setState(() => _loading = false);
            _scheduleHide();
            return; // ✅ InnerTube muxed success
          } catch (e) {
            debugPrint('InnerTube muxed init failed: $e');
            await _vpc?.dispose();
            _vpc = null;
          }
        }
      }
    } catch (e) {
      debugPrint('InnerTube PASS 1 error: $e');
    }

    // ── PASS 2: youtube_explode_dart (fallback) ───────────────────────────────
    for (int attempt = 1; attempt <= 2; attempt++) {
      try {
        final manifest = await _ytLocal.videos.streamsClient
            .getManifest(widget.video.id)
            .timeout(Duration(seconds: 20 + attempt * 10));

        final audioStreams = manifest.audioOnly.toList()
          ..sort((a, b) => b.bitrate.compareTo(a.bitrate));
        final bestAudio = audioStreams.isNotEmpty
            ? audioStreams.firstWhere(
                (s) => s.audioCodec.toLowerCase().contains('mp4a'),
                orElse: () => audioStreams.first,
              )
            : null;
        if (bestAudio != null) _audioStreamUrl = bestAudio.url.toString();

        // Video-only: closest to target, H.264 tiebreaker
        final videoValid = manifest.videoOnly
            .where((s) => s.videoResolution.height <= targetH)
            .toList();
        VideoOnlyStreamInfo? pick;
        if (videoValid.isEmpty) {
          final all = manifest.videoOnly.toList()
            ..sort(
              (a, b) =>
                  a.videoResolution.height.compareTo(b.videoResolution.height),
            );
          pick = all.isNotEmpty ? all.first : null;
        } else {
          videoValid.sort((a, b) {
            final hCmp = b.videoResolution.height.compareTo(
              a.videoResolution.height,
            );
            if (hCmp != 0) return hCmp;
            final isAvcA = a.videoCodec.toLowerCase().contains('avc') ? 1 : 0;
            final isAvcB = b.videoCodec.toLowerCase().contains('avc') ? 1 : 0;
            return isAvcB.compareTo(isAvcA);
          });
          pick = videoValid.isNotEmpty ? videoValid.first : null;
        }

        if (pick != null && bestAudio != null) {
          try {
            final ctrl = VideoPlayerController.networkUrl(
              Uri.parse(pick.url.toString()),
              httpHeaders: dlHdrs,
            );
            await ctrl.initialize().timeout(const Duration(seconds: 25));
            await ctrl.setVolume(0.0);

            final adAudio = AudioPlayer();
            await adAudio
                .setUrl(
                  _audioStreamUrl!,
                  headers: Map<String, String>.from(dlHdrs),
                )
                .timeout(const Duration(seconds: 15));

            _vpc = ctrl;
            _adaptiveAudio = adAudio;
            _isAdaptive = true;
            _actualQualityLabel = '${pick.videoResolution.height}p';
            _vpc!.addListener(_syncAudioState);
            await _vpc!.play();
            await _adaptiveAudio!.play();
            _startSyncTimer();
            WakelockPlus.enable();
            if (mounted) setState(() => _loading = false);
            _scheduleHide();
            return; // ✅ explode adaptive success
          } catch (e) {
            debugPrint('explode adaptive attempt $attempt: $e');
            _syncTimer?.cancel();
            _syncTimer = null;
            await _vpc?.dispose();
            _vpc = null;
            await _adaptiveAudio?.dispose();
            _adaptiveAudio = null;
            _isAdaptive = false;
          }
        }

        // Muxed fallback
        final muxed = manifest.muxed.toList()
          ..sort(
            (a, b) =>
                b.videoResolution.height.compareTo(a.videoResolution.height),
          );
        for (final s in muxed) {
          try {
            _vpc = VideoPlayerController.networkUrl(
              Uri.parse(s.url.toString()),
              httpHeaders: dlHdrs,
            );
            await _vpc!.initialize().timeout(const Duration(seconds: 20));
            _isAdaptive = false;
            _actualQualityLabel = '${s.videoResolution.height}p';
            await _vpc!.play();
            WakelockPlus.enable();
            if (mounted) setState(() => _loading = false);
            _scheduleHide();
            return; // ✅ explode muxed success
          } catch (_) {
            await _vpc?.dispose();
            _vpc = null;
          }
        }

        // Audio-only last resort
        if (_audioStreamUrl != null) {
          if (mounted)
            setState(() {
              _audioOnly = true;
            });
          await _BgAudio.play(widget.video, streamUrl: _audioStreamUrl);
          if (mounted) setState(() => _loading = false);
          return;
        }
      } catch (e) {
        debugPrint('_initPlayer PASS2 attempt $attempt: $e');
        if (attempt == 2) {
          if (mounted)
            setState(() {
              _loading = false;
              _error = true;
            });
        } else {
          await Future.delayed(const Duration(seconds: 3));
        }
      }
    }
  }

  void _startSyncTimer() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted || _vpc == null || _adaptiveAudio == null) return;
      final vPos = _vpc!.value.position;
      final aPos = _adaptiveAudio!.position;
      if ((vPos - aPos).abs() > const Duration(milliseconds: 800)) {
        _adaptiveAudio!.seek(vPos);
      }
    });
  }

  /// Sync audio play/pause state to video player state
  void _syncAudioState() {
    if (_adaptiveAudio == null || _vpc == null) return;
    if (_vpc!.value.isPlaying && !_adaptiveAudio!.playing) {
      _adaptiveAudio!.play();
    } else if (!_vpc!.value.isPlaying && _adaptiveAudio!.playing) {
      _adaptiveAudio!.pause();
    }
  }

  /// Seek both video and synced audio to the same position
  Future<void> _seekBoth(Duration position) async {
    await _vpc?.seekTo(position);
    if (_isAdaptive && _adaptiveAudio != null) {
      await _adaptiveAudio!.seek(position);
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
    _syncTimer?.cancel();
    _vpc?.pause();
    if (_isAdaptive) _adaptiveAudio?.pause();
    WakelockPlus.disable();
    _BgAudio.play(widget.video, streamUrl: _audioStreamUrl);
    widget.onMinimize(widget.video);
    Navigator.of(context).pop();
  }

  void _toggleFullscreen() {
    setState(() => _isFullscreen = !_isFullscreen);
    if (_isFullscreen) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  void _showQualityPicker() async {
    _scheduleHide();
    final prefs = await SharedPreferences.getInstance();
    final savedPref = prefs.getString('yt_video_quality') ?? '480p';
    if (!mounted) return;
    const options = ['Smart', '1080p', '720p', '480p', '360p', '240p', '144p'];
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Video Quality',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (_actualQualityLabel != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: _isAdaptive
                          ? const Color(0xFFCC0000)
                          : Colors.white12,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Playing: $_actualQualityLabel',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          ...options.map((q) {
            final isCurrent = q == savedPref; // highlight saved preference
            return ListTile(
              dense: true,
              leading: Icon(
                q == 'Smart'
                    ? Icons.auto_awesome
                    : (q == '1080p' || q == '720p')
                    ? Icons.hd
                    : Icons.sd,
                color: isCurrent ? const Color(0xFFFF0000) : Colors.white54,
                size: 20,
              ),
              title: Text(
                q == 'Smart' ? 'Smart (Auto)' : q,
                style: TextStyle(
                  color: isCurrent ? const Color(0xFFFF0000) : Colors.white,
                  fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              subtitle: q == 'Smart'
                  ? const Text(
                      'Best for your network',
                      style: TextStyle(color: Colors.white38, fontSize: 11),
                    )
                  : null,
              trailing: isCurrent
                  ? const Icon(Icons.check, color: Color(0xFFFF0000), size: 18)
                  : null,
              onTap: () async {
                Navigator.pop(context);
                if (q != savedPref) await _changeQuality(q);
              },
            );
          }),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Future<void> _changeQuality(String quality) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('yt_video_quality', quality);
    if (!mounted) return;
    // Stop current streams cleanly
    _syncTimer?.cancel();
    _syncTimer = null;
    _vpc?.removeListener(_syncAudioState);
    await _adaptiveAudio?.pause();
    await _adaptiveAudio?.dispose();
    _adaptiveAudio = null;
    await _vpc?.pause();
    final oldVpc = _vpc;
    _vpc = null;
    await oldVpc?.dispose();
    _isAdaptive = false;
    _actualQualityLabel = null;
    WakelockPlus.disable();
    if (mounted)
      setState(() {
        _loading = true;
        _error = false;
      });
    await _initPlayer();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _syncTimer?.cancel();
    _vpc?.removeListener(_syncAudioState);
    _vpc?.dispose();
    _adaptiveAudio?.dispose();
    _ytLocal.close();
    WakelockPlus.disable();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: SafeArea(
        child: Column(
          children: [
            _buildPlayer(),
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _buildMeta()),
                  SliverToBoxAdapter(child: _buildActions()),
                  SliverToBoxAdapter(child: _buildDesc()),
                  const SliverToBoxAdapter(
                    child: Divider(color: Colors.white12, height: 1),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                      child: const Text(
                        'Up next',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  if (_related.isEmpty)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFFFF0000),
                            strokeWidth: 2,
                          ),
                        ),
                      ),
                    )
                  else
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (_, i) => _VCard(
                          video: _related[i],
                          compact: true,
                          onTap: () => Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (_) => _VideoPage(
                                video: _related[i],
                                onMinimize: widget.onMinimize,
                              ),
                            ),
                          ),
                        ),
                        childCount: _related.length,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayer() {
    final w = MediaQuery.of(context).size.width;
    final h = w * 9 / 16;
    return GestureDetector(
      onTap: _toggleControls,
      child: Container(
        width: w,
        height: h,
        color: Colors.black,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (_loading)
              const CircularProgressIndicator(color: Color(0xFFFF0000))
            else if (_error)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 40),
                  const SizedBox(height: 8),
                  const Text(
                    'Could not load video',
                    style: TextStyle(color: Colors.white70),
                  ),
                  TextButton(
                    onPressed: _initPlayer,
                    child: const Text(
                      'Retry',
                      style: TextStyle(color: Color(0xFF3EA6FF)),
                    ),
                  ),
                ],
              )
            else if (_audioOnly)
              Stack(
                children: [
                  _Thumb(url: widget.video.thumb, w: w, h: h),
                  Container(width: w, height: h, color: Colors.black54),
                  const Center(
                    child: Icon(
                      Icons.music_note,
                      color: Colors.white60,
                      size: 64,
                    ),
                  ),
                ],
              )
            else if (_vpc != null && _vpc!.value.isInitialized)
              AspectRatio(
                aspectRatio: _vpc!.value.aspectRatio,
                child: VideoPlayer(_vpc!),
              ),

            // Controls overlay
            if (_ctrlVisible && !_loading && !_error) _buildControls(w, h),

            // Back/minimize chevron + Fullscreen button + Quality button — auto-hide
            IgnorePointer(
              ignoring: !_ctrlVisible,
              child: AnimatedOpacity(
                opacity: _ctrlVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                child: SizedBox(
                  width: w,
                  height: h,
                  child: Stack(
                    children: [
                      // ← Minimize / close (top-left)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: GestureDetector(
                          onTap: _minimize,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Icon(
                              Icons.keyboard_arrow_down,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                      // Quality picker button (top-right, left of fullscreen)
                      Positioned(
                        top: 10,
                        right: 46,
                        child: GestureDetector(
                          onTap: _showQualityPicker,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: _isAdaptive
                                  ? const Color(0xFFCC0000)
                                  : Colors.black54,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _actualQualityLabel ?? '480p',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                      // → Fullscreen / landscape toggle (top-right)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: GestureDetector(
                          onTap: _toggleFullscreen,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Icon(
                              _isFullscreen
                                  ? Icons.fullscreen_exit
                                  : Icons.fullscreen,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControls(double w, double h) {
    final playing = _audioOnly
        ? _BgAudio.isPlaying
        : (_vpc?.value.isPlaying ?? false);
    return AnimatedOpacity(
      opacity: _ctrlVisible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      child: Container(
        width: w,
        height: h,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.black54, Colors.transparent, Colors.black87],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Quality badge
            if (_actualQualityLabel != null)
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 40, 52, 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _isAdaptive
                          ? const Color(0xFFFF0000)
                          : Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _actualQualityLabel!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              )
            else
              const SizedBox(),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(
                    Icons.replay_10,
                    color: Colors.white,
                    size: 36,
                  ),
                  onPressed: () {
                    if (_vpc != null) {
                      _seekBoth(
                        _vpc!.value.position - const Duration(seconds: 10),
                      );
                    }
                  },
                ),
                const SizedBox(width: 16),
                IconButton(
                  iconSize: 60,
                  icon: Icon(
                    playing
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_filled,
                    color: Colors.white,
                    size: 60,
                  ),
                  onPressed: () {
                    setState(() {
                      if (_audioOnly) {
                        if (_BgAudio.isPlaying) {
                          _BgAudio.player.pause();
                        } else {
                          _BgAudio.player.play();
                        }
                      } else if (_vpc != null) {
                        if (_vpc!.value.isPlaying) {
                          _vpc!.pause();
                          if (_isAdaptive) _adaptiveAudio?.pause();
                        } else {
                          _vpc!.play();
                          if (_isAdaptive) _adaptiveAudio?.play();
                        }
                      }
                    });
                    _scheduleHide();
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 16),
                IconButton(
                  icon: const Icon(
                    Icons.forward_10,
                    color: Colors.white,
                    size: 36,
                  ),
                  onPressed: () {
                    if (_vpc != null) {
                      _seekBoth(
                        _vpc!.value.position + const Duration(seconds: 10),
                      );
                    }
                  },
                ),
              ],
            ),
            if (!_audioOnly && _vpc != null)
              ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: _vpc!,
                builder: (_, value, __) {
                  final pos = value.position.inMilliseconds.toDouble();
                  final dur = value.duration.inMilliseconds.toDouble();
                  final buf = value.buffered.isNotEmpty
                      ? value.buffered.last.end.inMilliseconds.toDouble()
                      : 0.0;
                  return Column(
                    children: [
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 14,
                          ),
                          activeTrackColor: const Color(0xFFFF0000),
                          inactiveTrackColor: Colors.white24,
                          secondaryActiveTrackColor: Colors.white38, // buffered
                          thumbColor: Colors.white,
                          overlayColor: Colors.white24,
                        ),
                        child: Slider(
                          value: dur > 0 ? pos.clamp(0.0, dur) : 0.0,
                          max: dur > 0 ? dur : 1.0,
                          secondaryTrackValue: dur > 0
                              ? buf.clamp(0.0, dur)
                              : 0.0,
                          onChanged: (v) {
                            // Show position preview without seeking yet
                            setState(() {});
                          },
                          onChangeEnd: (v) {
                            _seekBoth(Duration(milliseconds: v.toInt()));
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _fmtDur(value.position),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                              ),
                            ),
                            Text(
                              _fmtDur(value.duration),
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              )
            else
              const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildMeta() => Padding(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.video.title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          [
            if (widget.video.viewCount.isNotEmpty) widget.video.viewCount,
            if (widget.video.age.isNotEmpty) widget.video.age,
          ].join(' • '),
          style: const TextStyle(color: Colors.white54, fontSize: 13),
        ),
        const SizedBox(height: 12),
        // Channel row
        Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFF333333),
              child: Text(
                widget.video.channel.isNotEmpty
                    ? widget.video.channel[0].toUpperCase()
                    : 'C',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.video.channel,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            GestureDetector(
              onTap: _toggleSubscribe,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _subscribed
                      ? const Color(0xFF272727)
                      : const Color(0xFFFF0000),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _subscribed ? 'Subscribed' : 'Subscribe',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
      ],
    ),
  );

  Widget _buildActions() {
    return SizedBox(
      height: 72,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          // Like
          _ActionChip(
            icon: _liked ? Icons.thumb_up : Icons.thumb_up_outlined,
            label: 'Like',
            active: _liked,
            onTap: () {
              setState(() {
                _liked = !_liked;
                if (_liked) {
                  _disliked = false;
                  _saveLikedVideo();
                }
              });
            },
          ),
          // Dislike
          _ActionChip(
            icon: _disliked ? Icons.thumb_down : Icons.thumb_down_outlined,
            label: 'Dislike',
            active: _disliked,
            onTap: () {
              setState(() {
                _disliked = !_disliked;
                if (_disliked) {
                  _liked = false;
                  _saveLikedVideo(remove: true);
                }
              });
            },
          ),
          // Share
          _ActionChip(
            icon: Icons.share_outlined,
            label: 'Share',
            onTap: () => Share.share(
              'https://www.youtube.com/watch?v=${widget.video.id}',
              subject: widget.video.title,
            ),
          ),
          // Download — best quality
          _ActionChip(
            icon: Icons.download_outlined,
            label: 'Download',
            onTap: () async {
              context.read<YTDownloadProvider>().addDownload(
                'https://www.youtube.com/watch?v=${widget.video.id}',
                VideoQuality.p1080,
              );
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Downloading best quality...'),
                  duration: Duration(seconds: 2),
                ),
              );
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const YTDownloaderScreen()),
              );
            },
          ),
          // Save to bookmarks
          _ActionChip(
            icon: _saved ? Icons.bookmark : Icons.bookmark_border,
            label: 'Save',
            active: _saved,
            onTap: () => _showSaveSheet(context),
          ),
          // Background play — minimizes to mini-player, audio continues when screen off / app closed
          _ActionChip(
            icon: Icons.headphones,
            label: 'BG Play',
            onTap: () => _minimize(),
          ),
        ],
      ),
    );
  }

  Future<void> _saveLikedVideo({bool remove = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final v = widget.video;
    final raw = prefs.getStringList('yt_liked') ?? [];
    final entry = json.encode({
      'id': v.id,
      'title': v.title,
      'channel': v.channel,
      'thumb': v.thumb,
      'duration': v.duration,
      'viewCount': v.viewCount,
      'age': v.age,
      'channelId': v.channelId,
    });
    if (remove) {
      raw.removeWhere((e) => (json.decode(e) as Map)['id'] == v.id);
    } else {
      raw.removeWhere((e) => (json.decode(e) as Map)['id'] == v.id);
      raw.insert(0, entry);
      if (mounted) setState(() => _liked = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saved to Liked Videos'),
          duration: Duration(seconds: 1),
        ),
      );
    }
    await prefs.setStringList('yt_liked', raw.take(500).toList());
  }

  /// Shows a bottom sheet: save to "Saved Videos" or a user playlist
  void _showSaveSheet(BuildContext ctx) {
    showModalBottomSheet(
      context: ctx,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _SaveToSheet(
        video: widget.video,
        isSaved: _saved,
        onSavedChanged: (saved) {
          if (mounted) setState(() => _saved = saved);
        },
      ),
    );
  }

  Future<void> _toggleSubscribe() async {
    if (widget.video.channelId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Channel info not available'),
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }
    if (_subscribed) {
      await _SubStore.remove(widget.video.channelId);
      if (mounted) setState(() => _subscribed = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unsubscribed from ${widget.video.channel}'),
          duration: const Duration(seconds: 1),
        ),
      );
    } else {
      final ch = YtChannel(
        id: widget.video.channelId,
        name: widget.video.channel,
        thumb: '',
        subs: '',
      );
      try {
        final found = await _YtSvc.findChannel(widget.video.channel);
        await _SubStore.add(found ?? ch);
      } catch (_) {
        await _SubStore.add(ch);
      }
      if (mounted) setState(() => _subscribed = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Subscribed to ${widget.video.channel}'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  Widget _buildDesc() {
    if (_desc.isEmpty) return const SizedBox(height: 8);
    final show = _descExpanded
        ? _desc
        : (_desc.length > 120 ? _desc.substring(0, 120) : _desc);
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                show,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _descExpanded ? 'Show less' : 'Show more',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Mini Player — persistent audio playback UI
// ─────────────────────────────────────────────────────────────────────────────
class _MiniPlayer extends StatefulWidget {
  final YtVid video;
  final VoidCallback onExpand, onClose;
  const _MiniPlayer({
    required this.video,
    required this.onExpand,
    required this.onClose,
  });
  @override
  State<_MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<_MiniPlayer> {
  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 56,
      left: 0,
      right: 0,
      child: GestureDetector(
        onTap: widget.onExpand,
        child: Container(
          height: 64,
          decoration: const BoxDecoration(
            color: Color(0xFF212121),
            border: Border(top: BorderSide(color: Color(0xFF333333))),
            boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 8)],
          ),
          child: Row(
            children: [
              ClipRRect(child: _Thumb(url: widget.video.thumb, w: 100, h: 64)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      widget.video.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.video.channel,
                      maxLines: 1,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              // Play/pause
              StreamBuilder<PlayerState>(
                stream: _BgAudio.player.playerStateStream,
                builder: (_, snap) {
                  final playing = snap.data?.playing ?? false;
                  return IconButton(
                    icon: Icon(
                      playing ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                      size: 24,
                    ),
                    onPressed: () {
                      if (playing) {
                        _BgAudio.player.pause();
                      } else {
                        _BgAudio.player.play();
                      }
                      setState(() {});
                    },
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                onPressed: widget.onClose,
                padding: const EdgeInsets.all(8),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared Widgets
// ─────────────────────────────────────────────────────────────────────────────
class _Thumb extends StatelessWidget {
  final String url;
  final double w, h;
  const _Thumb({required this.url, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return Container(
        width: w,
        height: h,
        color: const Color(0xFF1A1A1A),
        child: const Icon(Icons.videocam, color: Colors.white24),
      );
    }
    return Image.network(
      url,
      width: w,
      height: h,
      fit: BoxFit.cover,
      errorBuilder: (_, a, b) => Container(
        width: w,
        height: h,
        color: const Color(0xFF1A1A1A),
        child: const Icon(Icons.broken_image, color: Colors.white24),
      ),
    );
  }
}

class _DurBadge extends StatelessWidget {
  final String dur;
  const _DurBadge(this.dur);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
    decoration: BoxDecoration(
      color: Colors.black87,
      borderRadius: BorderRadius.circular(3),
    ),
    child: Text(
      dur,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Action Chip — reusable pill button for video actions
// ─────────────────────────────────────────────────────────────────────────────
class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 16),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFFFF0000).withValues(alpha: 0.25)
              : const Color(0xFF272727),
          borderRadius: BorderRadius.circular(20),
          border: active
              ? Border.all(color: const Color(0xFFFF0000), width: 1.5)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: active ? const Color(0xFFFF0000) : Colors.white,
              size: 18,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: active ? const Color(0xFFFF0000) : Colors.white,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// History Screen
// ─────────────────────────────────────────────────────────────────────────────
class YtHistoryScreen extends StatefulWidget {
  final void Function(YtVid) onTap;
  const YtHistoryScreen({super.key, required this.onTap});
  @override
  State<YtHistoryScreen> createState() => _YtHistoryScreenState();
}

class _YtHistoryScreenState extends State<YtHistoryScreen> {
  List<YtVid> _history = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('yt_history') ?? [];
    setState(
      () => _history = raw
          .map((e) => YtVid.fromJson(json.decode(e) as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<void> _clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('yt_history');
    setState(() => _history = []);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF0F0F0F),
    appBar: AppBar(
      backgroundColor: const Color(0xFF0F0F0F),
      title: const Text('History', style: TextStyle(color: Colors.white)),
      iconTheme: const IconThemeData(color: Colors.white),
      actions: [
        if (_history.isNotEmpty)
          TextButton(
            onPressed: _clear,
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
      ],
    ),
    body: _history.isEmpty
        ? const Center(
            child: Text(
              'No watch history',
              style: TextStyle(color: Colors.white38),
            ),
          )
        : ListView.builder(
            itemCount: _history.length,
            itemBuilder: (_, i) => _VCard(
              video: _history[i],
              onTap: () => widget.onTap(_history[i]),
              compact: true,
            ),
          ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Liked Videos Screen
// ─────────────────────────────────────────────────────────────────────────────
class YtLikedScreen extends StatefulWidget {
  final void Function(YtVid) onTap;
  const YtLikedScreen({super.key, required this.onTap});
  @override
  State<YtLikedScreen> createState() => _YtLikedScreenState();
}

class _YtLikedScreenState extends State<YtLikedScreen> {
  List<YtVid> _liked = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('yt_liked') ?? [];
    if (mounted)
      setState(
        () => _liked = raw
            .map((e) => YtVid.fromJson(json.decode(e) as Map<String, dynamic>))
            .toList(),
      );
  }

  Future<void> _remove(int index) async {
    final removed = _liked[index];
    setState(() => _liked.removeAt(index));
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('yt_liked') ?? [];
    raw.removeWhere((e) => (json.decode(e) as Map)['id'] == removed.id);
    await prefs.setStringList('yt_liked', raw);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Removed from Liked Videos'),
          duration: const Duration(seconds: 2),
          action: SnackBarAction(
            label: 'Undo',
            textColor: const Color(0xFFFF0000),
            onPressed: () async {
              final prefs2 = await SharedPreferences.getInstance();
              final raw2 = prefs2.getStringList('yt_liked') ?? [];
              raw2.insert(0, json.encode(removed.toJson()));
              await prefs2.setStringList('yt_liked', raw2.take(500).toList());
              _load();
            },
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF0F0F0F),
    appBar: AppBar(
      backgroundColor: const Color(0xFF0F0F0F),
      title: Text(
        'Liked Videos (${_liked.length})',
        style: const TextStyle(color: Colors.white),
      ),
      iconTheme: const IconThemeData(color: Colors.white),
    ),
    body: _liked.isEmpty
        ? const Center(
            child: Text(
              'No liked videos yet',
              style: TextStyle(color: Colors.white38),
            ),
          )
        : ListView.builder(
            itemCount: _liked.length,
            itemBuilder: (_, i) => Dismissible(
              key: ValueKey(_liked[i].id),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                color: Colors.red.shade800,
                child: const Icon(Icons.delete, color: Colors.white),
              ),
              onDismissed: (_) => _remove(i),
              child: _VCard(
                video: _liked[i],
                onTap: () => widget.onTap(_liked[i]),
                compact: true,
              ),
            ),
          ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Playlists Screen (local user-created playlists)
// ─────────────────────────────────────────────────────────────────────────────
class YtPlaylistsScreen extends StatefulWidget {
  final void Function(YtVid) onTap;
  const YtPlaylistsScreen({super.key, required this.onTap});
  @override
  State<YtPlaylistsScreen> createState() => _YtPlaylistsScreenState();
}

class _YtPlaylistsScreenState extends State<YtPlaylistsScreen> {
  Map<String, List<YtVid>> _playlists = {};
  final _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs
        .getKeys()
        .where((k) => k.startsWith('yt_playlist_'))
        .toList();
    final result = <String, List<YtVid>>{};
    for (final k in keys) {
      final name = k.replaceFirst('yt_playlist_', '');
      final raw = prefs.getStringList(k) ?? [];
      result[name] = raw
          .map((e) => YtVid.fromJson(json.decode(e) as Map<String, dynamic>))
          .toList();
    }
    setState(() => _playlists = result);
  }

  Future<void> _createPlaylist(String name) async {
    if (name.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('yt_playlist_${name.trim()}', []);
    _load();
  }

  Future<void> _deletePlaylist(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('yt_playlist_$name');
    _load();
  }

  void _showCreate() {
    _ctrl.clear();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'New Playlist',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: _ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Playlist name',
            hintStyle: TextStyle(color: Colors.white38),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF0000),
            ),
            onPressed: () {
              Navigator.pop(context);
              _createPlaylist(_ctrl.text);
            },
            child: const Text('Create', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF0F0F0F),
    appBar: AppBar(
      backgroundColor: const Color(0xFF0F0F0F),
      title: const Text('Playlists', style: TextStyle(color: Colors.white)),
      iconTheme: const IconThemeData(color: Colors.white),
      actions: [
        IconButton(
          icon: const Icon(Icons.add, color: Colors.white),
          onPressed: _showCreate,
        ),
      ],
    ),
    body: _playlists.isEmpty
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.playlist_play,
                  size: 80,
                  color: Colors.white12,
                ),
                const SizedBox(height: 12),
                const Text(
                  'No playlists yet',
                  style: TextStyle(color: Colors.white38),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _showCreate,
                  icon: const Icon(Icons.add),
                  label: const Text('Create Playlist'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF0000),
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          )
        : ListView(
            children: _playlists.entries
                .map(
                  (e) => ListTile(
                    leading: const Icon(
                      Icons.playlist_play,
                      color: Colors.white,
                    ),
                    title: Text(
                      e.key,
                      style: const TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(
                      '${e.value.length} videos',
                      style: const TextStyle(color: Colors.white54),
                    ),
                    trailing: IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Colors.white38,
                      ),
                      onPressed: () => _deletePlaylist(e.key),
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => _PlaylistDetailScreen(
                          name: e.key,
                          videos: e.value,
                          onTap: widget.onTap,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
  );
}

class _PlaylistDetailScreen extends StatelessWidget {
  final String name;
  final List<YtVid> videos;
  final void Function(YtVid) onTap;
  const _PlaylistDetailScreen({
    required this.name,
    required this.videos,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF0F0F0F),
    appBar: AppBar(
      backgroundColor: const Color(0xFF0F0F0F),
      title: Text(name, style: const TextStyle(color: Colors.white)),
      iconTheme: const IconThemeData(color: Colors.white),
    ),
    body: videos.isEmpty
        ? const Center(
            child: Text(
              'No videos in this playlist',
              style: TextStyle(color: Colors.white38),
            ),
          )
        : ListView.builder(
            itemCount: videos.length,
            itemBuilder: (_, i) => _VCard(
              video: videos[i],
              onTap: () => onTap(videos[i]),
              compact: true,
            ),
          ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// YouTube Settings Screen — audio boost & preferences
// ─────────────────────────────────────────────────────────────────────────────
class YtSettingsScreen extends StatefulWidget {
  const YtSettingsScreen({super.key});
  @override
  State<YtSettingsScreen> createState() => _YtSettingsScreenState();
}

class _YtSettingsScreenState extends State<YtSettingsScreen> {
  double _audioBoost = 1.0; // 1.0 = normal, up to 3.0 = triple boost
  bool _autoplay = true;
  bool _hdOnWifi = true;
  String _videoQuality = '480p'; // default
  static const _qualityOptions = [
    'Smart',
    '144p',
    '240p',
    '360p',
    '480p',
    '720p',
    '1080p',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _audioBoost = prefs.getDouble('yt_audio_boost') ?? 1.0;
      _autoplay = prefs.getBool('yt_autoplay') ?? true;
      _hdOnWifi = prefs.getBool('yt_hd_wifi') ?? true;
      _videoQuality = prefs.getString('yt_video_quality') ?? '480p';
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('yt_audio_boost', _audioBoost);
    await prefs.setBool('yt_autoplay', _autoplay);
    await prefs.setBool('yt_hd_wifi', _hdOnWifi);
    await prefs.setString('yt_video_quality', _videoQuality);
    // Apply boost via the handler which knows the REAL ExoPlayer session ID
    await ytAudioHandler.player.setVolume(1.0);
    await ytAudioHandler.applyBoost(_audioBoost);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF0F0F0F),
    appBar: AppBar(
      backgroundColor: const Color(0xFF0F0F0F),
      title: const Text(
        'YouTube Settings',
        style: TextStyle(color: Colors.white),
      ),
      iconTheme: const IconThemeData(color: Colors.white),
    ),
    body: ListView(
      children: [
        // Audio Boost
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Row(
            children: [
              const Icon(Icons.volume_up, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Audio Boost',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF0000),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _audioBoost > 1.0
                      ? '+${(((_audioBoost - 1.0) / 2.0) * 15).toStringAsFixed(1)} dB'
                      : 'Normal',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
        Slider(
          value: _audioBoost,
          min: 1.0,
          max: 3.0,
          divisions: 40,
          activeColor: const Color(0xFFFF0000),
          inactiveColor: Colors.white24,
          onChanged: (v) {
            setState(() => _audioBoost = v);
            _save();
          },
        ),
        // Quick preset buttons
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final preset in [1.0, 1.5, 2.0, 2.5, 3.0])
                GestureDetector(
                  onTap: () {
                    setState(() => _audioBoost = preset);
                    _save();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: _audioBoost == preset
                          ? const Color(0xFFFF0000)
                          : Colors.white12,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      preset == 1.0 ? 'Normal' : '${preset}x',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: Text(
            _audioBoost > 1.0
                ? 'Hardware boost: +${(((_audioBoost - 1.0) / 2.0) * 15).toStringAsFixed(1)} dB via LoudnessEnhancer'
                : 'Normal volume (no boost)',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ),
        const Divider(color: Colors.white12, height: 32),
        SwitchListTile(
          title: const Text(
            'Autoplay next video',
            style: TextStyle(color: Colors.white),
          ),
          subtitle: const Text(
            'Automatically plays next recommended video',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          value: _autoplay,
          activeColor: const Color(0xFFFF0000),
          onChanged: (v) {
            setState(() => _autoplay = v);
            _save();
          },
        ),
        SwitchListTile(
          title: const Text(
            'HD on Wi-Fi only',
            style: TextStyle(color: Colors.white),
          ),
          subtitle: const Text(
            'Stream best quality when connected to Wi-Fi',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          value: _hdOnWifi,
          activeColor: const Color(0xFFFF0000),
          onChanged: (v) {
            setState(() => _hdOnWifi = v);
            _save();
          },
        ),
        const Divider(color: Colors.white12),
        // Video Quality Selector
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              const Icon(Icons.hd, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Video Quality',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text(
            _videoQuality == 'Smart'
                ? 'Smart: auto-selects best quality for your network'
                : 'Fixed at $_videoQuality',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ),
        ..._qualityOptions.map(
          (q) => RadioListTile<String>(
            title: Text(
              q == 'Smart' ? '⚡ Smart (auto)' : q,
              style: const TextStyle(color: Colors.white),
            ),
            subtitle: q == 'Smart'
                ? const Text(
                    'Adapts to network speed',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  )
                : q == '480p'
                ? const Text(
                    'Default — balanced quality & speed',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  )
                : q == '1080p'
                ? const Text(
                    'Full HD — needs fast connection',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  )
                : q == '144p'
                ? const Text(
                    'Lowest — very slow connections',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  )
                : null,
            value: q,
            groupValue: _videoQuality,
            activeColor: const Color(0xFFFF0000),
            onChanged: (v) {
              if (v != null) {
                setState(() => _videoQuality = v);
                _save();
              }
            },
          ),
        ),
        const Divider(color: Colors.white12),
        ListTile(
          leading: const Icon(Icons.delete_outline, color: Colors.red),
          title: const Text(
            'Clear Watch History',
            style: TextStyle(color: Colors.white),
          ),
          onTap: () async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.remove('yt_history');
            if (context.mounted)
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('History cleared')));
          },
        ),
        ListTile(
          leading: const Icon(Icons.thumb_up_outlined, color: Colors.white),
          title: const Text(
            'Clear Liked Videos',
            style: TextStyle(color: Colors.white),
          ),
          onTap: () async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.remove('yt_liked');
            if (context.mounted)
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Liked videos cleared')),
              );
          },
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Saved Videos Screen
// ─────────────────────────────────────────────────────────────────────────────
class YtSavedScreen extends StatefulWidget {
  final void Function(YtVid) onTap;
  const YtSavedScreen({super.key, required this.onTap});
  @override
  State<YtSavedScreen> createState() => _YtSavedScreenState();
}

class _YtSavedScreenState extends State<YtSavedScreen> {
  List<YtVid> _saved = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('yt_saved') ?? [];
    setState(
      () => _saved = raw
          .map((e) => YtVid.fromJson(json.decode(e) as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<void> _remove(int index) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('yt_saved') ?? [];
    raw.removeAt(index);
    await prefs.setStringList('yt_saved', raw);
    setState(() => _saved.removeAt(index));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF0F0F0F),
    appBar: AppBar(
      backgroundColor: const Color(0xFF0F0F0F),
      title: const Text('Saved Videos', style: TextStyle(color: Colors.white)),
      iconTheme: const IconThemeData(color: Colors.white),
    ),
    body: _saved.isEmpty
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.bookmark_border,
                  size: 80,
                  color: Colors.white12,
                ),
                const SizedBox(height: 12),
                const Text(
                  'No saved videos yet',
                  style: TextStyle(color: Colors.white38),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Tap Save on any video to add it here',
                  style: TextStyle(color: Colors.white24, fontSize: 13),
                ),
              ],
            ),
          )
        : ListView.builder(
            itemCount: _saved.length,
            itemBuilder: (_, i) => Dismissible(
              key: ValueKey(_saved[i].id),
              direction: DismissDirection.endToStart,
              onDismissed: (_) => _remove(i),
              background: Container(
                color: Colors.red,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 16),
                child: const Icon(Icons.delete, color: Colors.white),
              ),
              child: _VCard(
                video: _saved[i],
                onTap: () => widget.onTap(_saved[i]),
                compact: true,
              ),
            ),
          ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Save-to Sheet — shows "Saved Videos" + user playlists
// ─────────────────────────────────────────────────────────────────────────────
class _SaveToSheet extends StatefulWidget {
  final YtVid video;
  final bool isSaved;
  final void Function(bool saved) onSavedChanged;
  const _SaveToSheet({
    required this.video,
    required this.isSaved,
    required this.onSavedChanged,
  });
  @override
  State<_SaveToSheet> createState() => _SaveToSheetState();
}

class _SaveToSheetState extends State<_SaveToSheet> {
  List<Map<String, dynamic>> _playlists = [];
  late bool _inSaved;

  @override
  void initState() {
    super.initState();
    _inSaved = widget.isSaved;
    _loadPlaylists();
  }

  /// Loads playlists stored as individual keys `yt_playlist_NAME`
  /// matching the format used by YtPlaylistsScreen
  Future<void> _loadPlaylists() async {
    final prefs = await SharedPreferences.getInstance();
    final keys =
        prefs.getKeys().where((k) => k.startsWith('yt_playlist_')).toList()
          ..sort();
    final result = <Map<String, dynamic>>[];
    for (final k in keys) {
      final name = k.replaceFirst('yt_playlist_', '');
      final videos = prefs.getStringList(k) ?? [];
      result.add({'name': name, 'key': k, 'count': videos.length});
    }
    if (mounted) setState(() => _playlists = result);
  }

  Future<void> _toggleSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('yt_saved') ?? [];
    final v = widget.video;
    final entry = json.encode({
      'id': v.id,
      'title': v.title,
      'channel': v.channel,
      'thumb': v.thumb,
      'duration': v.duration,
      'viewCount': v.viewCount,
      'age': v.age,
      'channelId': v.channelId,
    });
    if (_inSaved) {
      raw.removeWhere((e) => (json.decode(e) as Map)['id'] == v.id);
      setState(() => _inSaved = false);
    } else {
      raw.removeWhere((e) => (json.decode(e) as Map)['id'] == v.id);
      raw.insert(0, entry);
      setState(() => _inSaved = true);
    }
    await prefs.setStringList('yt_saved', raw.take(500).toList());
    widget.onSavedChanged(_inSaved);
  }

  Future<void> _addToPlaylist(int idx) async {
    final prefs = await SharedPreferences.getInstance();
    final pl = _playlists[idx];
    final plKey = pl['key'] as String;
    final plName = pl['name'] as String;
    final raw = prefs.getStringList(plKey) ?? [];
    final v = widget.video;
    final entry = json.encode({
      'id': v.id,
      'title': v.title,
      'channel': v.channel,
      'thumb': v.thumb,
      'duration': v.duration,
      'viewCount': v.viewCount,
      'age': v.age,
      'channelId': v.channelId,
    });
    // Avoid duplicate by video ID
    final alreadyIn = raw.any((e) {
      try {
        return (json.decode(e) as Map)['id'] == v.id;
      } catch (_) {
        return false;
      }
    });
    if (!alreadyIn) {
      raw.insert(0, entry);
      await prefs.setStringList(plKey, raw);
    }
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(alreadyIn ? 'Already in $plName' : 'Added to $plName'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Save video to…',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          ListTile(
            leading: Icon(
              _inSaved ? Icons.bookmark : Icons.bookmark_border,
              color: _inSaved ? const Color(0xFFFF0000) : Colors.white,
            ),
            title: const Text(
              'Saved Videos',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              _inSaved ? 'Tap to remove' : 'Add to your saved list',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            trailing: _inSaved
                ? const Icon(
                    Icons.check_circle,
                    color: Color(0xFFFF0000),
                    size: 20,
                  )
                : null,
            onTap: () async {
              await _toggleSaved();
              if (mounted) Navigator.pop(context);
            },
          ),
          const Divider(color: Colors.white12, height: 1),
          if (_playlists.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No playlists yet — create one in the You tab',
                style: TextStyle(color: Colors.white38, fontSize: 13),
              ),
            )
          else
            ...List.generate(_playlists.length, (i) {
              final pl = _playlists[i];
              final count = pl['count'] as int? ?? 0;
              return ListTile(
                leading: const Icon(Icons.playlist_add, color: Colors.white70),
                title: Text(
                  pl['name'] as String? ?? 'Playlist',
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  '$count video${count == 1 ? '' : 's'}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                onTap: () => _addToPlaylist(i),
              );
            }),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
