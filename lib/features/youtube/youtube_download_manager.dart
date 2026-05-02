import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:dio/dio.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:math' as math;

// ─────────────────────────────────────────────
// NOTIFICATION SERVICE
// ─────────────────────────────────────────────
class YTNotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(settings: const InitializationSettings(android: android));
    _initialized = true;
  }

  static Future<void> showProgress(
      int id, String title, int progress) async {
    await init();
    await _plugin.show(
      id: id,
      title: title,
      body: '$progress% downloaded',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'yt_download_channel',
          'YouTube Downloads',
          channelDescription: 'YouTube video downloads',
          importance: Importance.low,
          priority: Priority.low,
          showProgress: true,
          maxProgress: 100,
          progress: progress,
          onlyAlertOnce: true,
        ),
      ),
    );
  }

  static Future<void> showComplete(int id, String title) async {
    await init();
    await _plugin.show(
      id: id,
      title: '✅ Download Complete',
      body: title,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'yt_download_channel',
          'YouTube Downloads',
          channelDescription: 'YouTube video downloads',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }

  static Future<void> cancel(int id) async {
    await init();
    return _plugin.cancel(id: id);
  }
}

// ─────────────────────────────────────────────
// MODELS
// ─────────────────────────────────────────────
enum DownloadStatus { pending, fetching, downloading, completed, failed, cancelled }

enum VideoQuality { p1080, p720, p480, p360, audioOnly }

extension VideoQualityLabel on VideoQuality {
  String get label {
    switch (this) {
      case VideoQuality.p1080: return '1080p HD';
      case VideoQuality.p720:  return '720p HD';
      case VideoQuality.p480:  return '480p';
      case VideoQuality.p360:  return '360p';
      case VideoQuality.audioOnly: return 'Audio MP3';
    }
  }
  String get ext => this == VideoQuality.audioOnly ? 'mp3' : 'mp4';
  IconData get icon => this == VideoQuality.audioOnly
      ? Icons.music_note_rounded
      : Icons.video_file_rounded;
}

class DownloadItem {
  final String id;
  final String url;
  String title;
  String? thumbnailUrl;
  String? duration;
  String? author;
  VideoQuality quality;
  DownloadStatus status;
  double progress;
  String? filePath;
  String? errorMessage;
  String? fileSize;
  CancelToken? cancelToken;
  DateTime createdAt;

  DownloadItem({
    required this.id,
    required this.url,
    this.title = 'Fetching info...',
    this.thumbnailUrl,
    this.duration,
    this.author,
    this.quality = VideoQuality.p720,
    this.status = DownloadStatus.pending,
    this.progress = 0,
    this.filePath,
    this.errorMessage,
    this.fileSize,
    this.cancelToken,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  String get statusText {
    switch (status) {
      case DownloadStatus.pending:     return 'Waiting';
      case DownloadStatus.fetching:    return 'Fetching info...';
      case DownloadStatus.downloading: return '${(progress * 100).toStringAsFixed(1)}%';
      case DownloadStatus.completed:   return 'Completed';
      case DownloadStatus.failed:      return 'Failed';
      case DownloadStatus.cancelled:   return 'Cancelled';
    }
  }

  Color get statusColor {
    switch (status) {
      case DownloadStatus.pending:     return Colors.grey;
      case DownloadStatus.fetching:    return const Color(0xFFFFB347);
      case DownloadStatus.downloading: return const Color(0xFF00D4FF);
      case DownloadStatus.completed:   return const Color(0xFF00E676);
      case DownloadStatus.failed:      return const Color(0xFFFF4444);
      case DownloadStatus.cancelled:   return Colors.grey;
    }
  }
}

// ─────────────────────────────────────────────
// DOWNLOAD PROVIDER
// ─────────────────────────────────────────────
class YTDownloadProvider extends ChangeNotifier {
  final List<DownloadItem> _items = [];
  final YoutubeExplode _yt = YoutubeExplode();
  final Dio _dio = Dio();

  List<DownloadItem> get items => List.unmodifiable(_items);
  int get activeCount => _items
      .where((i) => i.status == DownloadStatus.downloading ||
                    i.status == DownloadStatus.fetching)
      .length;

  static const String _downloadFolder = '/storage/emulated/0/Download/YouTubeDL';

  Future<void> addDownload(String rawUrl, VideoQuality quality) async {
    final cleanUrl = _sanitizeUrl(rawUrl);
    if (cleanUrl == null) throw Exception('Invalid YouTube URL');

    final item = DownloadItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      url: cleanUrl,
      quality: quality,
      status: DownloadStatus.fetching,
    );

    _items.insert(0, item);
    notifyListeners();

    await _startDownload(item);
  }

  Future<void> _startDownload(DownloadItem item) async {
    try {
      await _ensurePermissions();

      final dir = Directory(_downloadFolder);
      if (!await dir.exists()) await dir.create(recursive: true);

      item.status = DownloadStatus.fetching;
      notifyListeners();

      final video = await _yt.videos.get(item.url);
      item.title = video.title;
      item.thumbnailUrl = video.thumbnails.highResUrl;
      item.duration = _formatDuration(video.duration);
      item.author = video.author;
      notifyListeners();

      final manifest = await _yt.videos.streamsClient.getManifest(item.url);

      String downloadUrl;
      String fileName;
      final safeTitle = video.title
          .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
          .substring(0, math.min(video.title.length, 60));

      if (item.quality == VideoQuality.audioOnly) {
        final audioStream = manifest.audioOnly
            .where((s) => s.codec.mimeType.contains('mp4'))
            .toList()
          ..sort((a, b) => b.bitrate.compareTo(a.bitrate));

        if (audioStream.isEmpty) throw Exception('No audio stream found');

        downloadUrl = audioStream.first.url.toString();
        fileName = '${safeTitle}_audio.mp3';
      } else {
        final targetHeight = _qualityToHeight(item.quality);

        // Sort muxed streams from highest to lowest resolution
        final muxed = manifest.muxed.toList()
          ..sort((a, b) => b.videoResolution.height.compareTo(a.videoResolution.height));

        // Prefer exact match, then closest below target, then closest above target
        MuxedStreamInfo? chosen;

        // 1. Try to find stream at or below the target height
        for (final s in muxed) {
          if (s.videoResolution.height <= targetHeight) {
            chosen = s;
            break;
          }
        }

        // 2. If nothing found at or below, take the lowest available (closest to target from above)
        chosen ??= muxed.isNotEmpty ? muxed.last : null;

        // 3. Absolute fallback: highest bitrate muxed
        if (chosen == null && manifest.muxed.isNotEmpty) {
          chosen = manifest.muxed.withHighestBitrate();
        }

        if (chosen == null) throw Exception('No video stream found for ${item.quality.label}');

        downloadUrl = chosen.url.toString();
        fileName = '${safeTitle}_${item.quality.label}.mp4';
      }

      final filePath = '$_downloadFolder/$fileName';
      item.filePath = filePath;
      item.status = DownloadStatus.downloading;
      item.cancelToken = CancelToken();
      notifyListeners();

      await _dio.download(
        downloadUrl,
        filePath,
        cancelToken: item.cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            item.progress = received / total;
            final sizeMB = (total / 1024 / 1024).toStringAsFixed(1);
            item.fileSize = '$sizeMB MB';
            notifyListeners();

            if ((item.progress * 100).toInt() % 5 == 0) {
              YTNotificationService.showProgress(
                int.parse(item.id.substring(item.id.length - 6)),
                item.title,
                (item.progress * 100).toInt(),
              );
            }
          }
        },
        options: Options(
          headers: {
            'User-Agent': 'Mozilla/5.0',
            'Accept': '*/*',
          },
          receiveTimeout: const Duration(minutes: 30),
        ),
      );

      item.status = DownloadStatus.completed;
      item.progress = 1.0;
      notifyListeners();

      await _scanMediaFile(filePath);

      final notifId = int.parse(item.id.substring(item.id.length - 6));
      await YTNotificationService.cancel(notifId);
      await YTNotificationService.showComplete(notifId, item.title);

    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        item.status = DownloadStatus.cancelled;
      } else {
        item.status = DownloadStatus.failed;
        item.errorMessage = _friendlyError(e.message ?? 'Download failed');
      }
      notifyListeners();
    } catch (e) {
      item.status = DownloadStatus.failed;
      item.errorMessage = _friendlyError(e.toString());
      notifyListeners();
    }
  }

  Future<void> cancelDownload(String id) async {
    final item = _items.firstWhere((i) => i.id == id);
    item.cancelToken?.cancel('User cancelled');
    item.status = DownloadStatus.cancelled;
    notifyListeners();
  }

  Future<void> retryDownload(String id) async {
    final item = _items.firstWhere((i) => i.id == id);
    item.status = DownloadStatus.pending;
    item.progress = 0;
    item.errorMessage = null;
    item.cancelToken = null;
    notifyListeners();
    await _startDownload(item);
  }

  void removeDownload(String id) {
    _items.removeWhere((i) => i.id == id);
    notifyListeners();
  }

  String? _sanitizeUrl(String raw) {
    try {
      final decoded = Uri.decodeFull(raw.trim());
      final videoId = _extractVideoId(decoded);
      if (videoId != null) {
        return 'https://www.youtube.com/watch?v=$videoId';
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  String? _extractVideoId(String url) {
    final patterns = [
      RegExp(r'[?&]v=([a-zA-Z0-9_-]{11})'),
      RegExp(r'youtu\.be/([a-zA-Z0-9_-]{11})'),
      RegExp(r'shorts/([a-zA-Z0-9_-]{11})'),
      RegExp(r'embed/([a-zA-Z0-9_-]{11})'),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(url);
      if (m != null) return m.group(1);
    }
    return null;
  }

  int _qualityToHeight(VideoQuality q) {
    switch (q) {
      case VideoQuality.p1080: return 1080;
      case VideoQuality.p720:  return 720;
      case VideoQuality.p480:  return 480;
      case VideoQuality.p360:  return 360;
      default: return 720;
    }
  }

  String _formatDuration(Duration? d) {
    if (d == null) return '';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '$h:${m.toString().padLeft(2,'0')}:${s.toString().padLeft(2,'0')}';
    return '$m:${s.toString().padLeft(2,'0')}';
  }

  String _friendlyError(String e) {
    if (e.contains('percent encoding') || e.contains('URI')) {
      return 'Invalid URL. Please copy the link directly from YouTube.';
    }
    if (e.contains('network') || e.contains('socket')) {
      return 'Network error. Check your internet connection.';
    }
    if (e.contains('403') || e.contains('forbidden')) {
      return 'Access denied. The video may be age-restricted or private.';
    }
    return e.length > 100 ? '${e.substring(0, 100)}...' : e;
  }

  Future<void> _scanMediaFile(String path) async {
    try {
      const channel = MethodChannel('media_scanner');
      await channel.invokeMethod('scanFile', {'path': path});
    } catch (_) {
      try {
        final result = await Process.run('am', [
          'broadcast',
          '-a', 'android.intent.action.MEDIA_SCANNER_SCAN_FILE',
          '-d', 'file://$path',
        ]);
        debugPrint('MediaScanner: ${result.stdout}');
      } catch (_) {}
    }
  }

  Future<void> _ensurePermissions() async {
    if (Platform.isAndroid) {
      final sdkInt = await _getAndroidSdkInt();
      if (sdkInt >= 33) {
        await Permission.videos.request();
        await Permission.audio.request();
        await Permission.notification.request();
      } else if (sdkInt >= 30) {
        final status = await Permission.manageExternalStorage.status;
        if (!status.isGranted) {
          await Permission.manageExternalStorage.request();
        }
      } else {
        await Permission.storage.request();
      }
    }
  }

  Future<int> _getAndroidSdkInt() async {
    try {
      const channel = MethodChannel('flutter/platform');
      final version = await channel.invokeMethod<String>('getAndroidVersion');
      return int.tryParse(version ?? '29') ?? 29;
    } catch (_) {
      return 29;
    }
  }

  @override
  void dispose() {
    _yt.close();
    super.dispose();
  }
}

// ─────────────────────────────────────────────
// UI COMPONENT
// ─────────────────────────────────────────────
class YTDownloaderScreen extends StatefulWidget {
  final String? initialUrl;
  const YTDownloaderScreen({super.key, this.initialUrl});
  @override
  State<YTDownloaderScreen> createState() => _YTDownloaderScreenState();
}

class _YTDownloaderScreenState extends State<YTDownloaderScreen> {
  late TextEditingController _urlController;
  VideoQuality _selectedQuality = VideoQuality.p720;
  bool _isAdding = false;
  String? _urlError;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.initialUrl ?? '');
    if (widget.initialUrl != null && widget.initialUrl!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _addDownload());
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _addDownload() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _urlError = 'Please paste a YouTube URL');
      return;
    }

    setState(() {
      _isAdding = true;
      _urlError = null;
    });

    try {
      await context.read<YTDownloadProvider>().addDownload(url, _selectedQuality);
      _urlController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download started!', style: GoogleFonts.spaceGrotesk()),
            backgroundColor: const Color(0xFF00E676),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      setState(() => _urlError = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isAdding = false);
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      _urlController.text = data!.text!;
      setState(() => _urlError = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A0000),
        elevation: 0,
        title: Text('YouTube Downloads', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold)),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1A0000), Color(0xFF0A0A0F)],
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF0000),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.download_rounded,
                                color: Colors.white, size: 24),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('YT Downloader',
                                  style: GoogleFonts.spaceGrotesk(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  )),
                              Text('Save to Downloads folder',
                                  style: GoogleFonts.spaceGrotesk(
                                    fontSize: 12,
                                    color: Colors.white38,
                                  )),
                            ],
                          ),
                          const Spacer(),
                          Consumer<YTDownloadProvider>(
                            builder: (_, p, child) => p.activeCount > 0
                                ? Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF00D4FF)
                                          .withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                          color: const Color(0xFF00D4FF),
                                          width: 1),
                                    ),
                                    child: Row(
                                      children: [
                                        const SizedBox(
                                          width: 8,
                                          height: 8,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Color(0xFF00D4FF),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text('${p.activeCount} active',
                                            style: GoogleFonts.spaceGrotesk(
                                              fontSize: 11,
                                              color: const Color(0xFF00D4FF),
                                              fontWeight: FontWeight.w600,
                                            )),
                                      ],
                                    ),
                                  ).animate().fadeIn()
                                : const SizedBox(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF13131A),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _urlError != null
                                ? const Color(0xFFFF4444)
                                : const Color(0xFF2A2A35),
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                const SizedBox(width: 16),
                                const Icon(Icons.link_rounded,
                                    color: Colors.white38, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: _urlController,
                                    style: GoogleFonts.spaceGrotesk(
                                      color: Colors.white,
                                      fontSize: 14,
                                    ),
                                    decoration: InputDecoration(
                                      hintText: 'Paste YouTube URL here...',
                                      hintStyle: GoogleFonts.spaceGrotesk(
                                        color: Colors.white24,
                                        fontSize: 14,
                                      ),
                                      border: InputBorder.none,
                                      contentPadding: const EdgeInsets.symmetric(
                                          vertical: 16),
                                    ),
                                    onChanged: (_) =>
                                        setState(() => _urlError = null),
                                  ),
                                ),
                                GestureDetector(
                                  onTap: _pasteFromClipboard,
                                  child: Container(
                                    margin: const EdgeInsets.all(8),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text('PASTE',
                                        style: GoogleFonts.spaceGrotesk(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white54,
                                        )),
                                  ),
                                ),
                              ],
                            ),
                            if (_urlError != null)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                                child: Row(
                                  children: [
                                    const Icon(Icons.error_outline,
                                        color: Color(0xFFFF4444), size: 14),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(_urlError!,
                                          style: GoogleFonts.spaceGrotesk(
                                            color: const Color(0xFFFF4444),
                                            fontSize: 12,
                                          )),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 40,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: VideoQuality.values.map((q) {
                            final selected = _selectedQuality == q;
                            return GestureDetector(
                              onTap: () =>
                                  setState(() => _selectedQuality = q),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                margin: const EdgeInsets.only(right: 8),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 0),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? const Color(0xFFFF0000)
                                      : const Color(0xFF13131A),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: selected
                                        ? const Color(0xFFFF0000)
                                        : const Color(0xFF2A2A35),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(q.icon,
                                        size: 14,
                                        color: selected
                                            ? Colors.white
                                            : Colors.white38),
                                    const SizedBox(width: 6),
                                    Text(q.label,
                                        style: GoogleFonts.spaceGrotesk(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: selected
                                              ? Colors.white
                                              : Colors.white38,
                                        )),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _isAdding ? null : _addDownload,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF0000),
                            disabledBackgroundColor:
                                const Color(0xFFFF0000).withValues(alpha: 0.4),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                            elevation: 0,
                          ),
                          child: _isAdding
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.download_rounded,
                                        color: Colors.white, size: 20),
                                    const SizedBox(width: 8),
                                    Text('DOWNLOAD NOW',
                                        style: GoogleFonts.spaceGrotesk(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                          letterSpacing: 1,
                                        )),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Row(
                children: [
                  Text('DOWNLOADS',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.white24,
                        letterSpacing: 2,
                      )),
                  const Spacer(),
                  Consumer<YTDownloadProvider>(
                    builder: (_, p, child) => Text(
                      '${p.items.length} items',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 11,
                        color: Colors.white24,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Consumer<YTDownloadProvider>(
            builder: (_, provider, child) {
              if (provider.items.isEmpty) {
                return SliverToBoxAdapter(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(60),
                      child: Column(
                        children: [
                          const Icon(Icons.download_rounded,
                              size: 64, color: Colors.white12),
                          const SizedBox(height: 16),
                          Text('No downloads yet',
                              style: GoogleFonts.spaceGrotesk(
                                color: Colors.white24,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              )),
                          const SizedBox(height: 8),
                          Text('Paste a YouTube URL above to start',
                              style: GoogleFonts.spaceGrotesk(
                                color: Colors.white12,
                                fontSize: 13,
                              )),
                        ],
                      ),
                    ),
                  ),
                );
              }
              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => _YTDownloadCard(
                    item: provider.items[i],
                    onCancel: () => provider.cancelDownload(provider.items[i].id),
                    onRetry: () => provider.retryDownload(provider.items[i].id),
                    onRemove: () => provider.removeDownload(provider.items[i].id),
                  ).animate().fadeIn(delay: Duration(milliseconds: i * 50)),
                  childCount: provider.items.length,
                ),
              );
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }
}

class _YTDownloadCard extends StatelessWidget {
  final DownloadItem item;
  final VoidCallback onCancel;
  final VoidCallback onRetry;
  final VoidCallback onRemove;

  const _YTDownloadCard({
    required this.item,
    required this.onCancel,
    required this.onRetry,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = item.status == DownloadStatus.downloading || item.status == DownloadStatus.fetching;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF13131A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive ? item.statusColor.withValues(alpha: 0.3) : const Color(0xFF1E1E2A),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: item.thumbnailUrl != null
                      ? Image.network(
                          item.thumbnailUrl!,
                          width: 80,
                          height: 56,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => _placeholderThumb(),
                        )
                      : _placeholderThumb(),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title,
                        style: GoogleFonts.spaceGrotesk(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _Tag(item.quality.label, const Color(0xFF2A2A35)),
                          if (item.duration != null) ...[
                            const SizedBox(width: 4),
                            _Tag(item.duration!, const Color(0xFF2A2A35)),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  children: [
                    if (isActive)
                      GestureDetector(onTap: onCancel, child: const Icon(Icons.stop_circle_rounded, color: Color(0xFFFF4444), size: 24))
                    else if (item.status == DownloadStatus.failed || item.status == DownloadStatus.cancelled)
                      GestureDetector(onTap: onRetry, child: const Icon(Icons.refresh_rounded, color: Color(0xFF00D4FF), size: 24))
                    else if (item.status == DownloadStatus.completed)
                      const Icon(Icons.check_circle_rounded, color: Color(0xFF00E676), size: 24),
                    const SizedBox(height: 8),
                    GestureDetector(onTap: onRemove, child: const Icon(Icons.close_rounded, color: Colors.white24, size: 18)),
                  ],
                ),
              ],
            ),
          ),
          if (isActive || item.status == DownloadStatus.completed)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: item.progress,
                  backgroundColor: const Color(0xFF2A2A35),
                  valueColor: AlwaysStoppedAnimation<Color>(item.statusColor),
                  minHeight: 4,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                Container(width: 6, height: 6, decoration: BoxDecoration(color: item.statusColor, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(
                  item.status == DownloadStatus.failed && item.errorMessage != null ? item.errorMessage! : item.statusText,
                  style: GoogleFonts.spaceGrotesk(fontSize: 11, color: item.status == DownloadStatus.failed ? const Color(0xFFFF4444) : Colors.white38),
                ),
                if (item.status == DownloadStatus.completed && item.filePath != null) ...[
                  const Spacer(),
                  GestureDetector(
                    onTap: () => _openFile(item.filePath!),
                    child: Row(
                      children: [
                        Text('Open folder', style: GoogleFonts.spaceGrotesk(fontSize: 11, color: const Color(0xFF00D4FF), fontWeight: FontWeight.w600)),
                        const SizedBox(width: 4),
                        const Icon(Icons.folder_open_rounded, size: 14, color: Color(0xFF00D4FF)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholderThumb() => Container(
        width: 80, height: 56, color: const Color(0xFF1E1E2A),
        child: const Icon(Icons.play_circle_outline_rounded, color: Colors.white24, size: 28),
      );

  Future<void> _openFile(String path) async {
    try {
      const platform = MethodChannel('jarvis.ai.os/file_open');
      await platform.invokeMethod('openFolder', {'path': '/storage/emulated/0/Download/YouTubeDL'});
    } catch (_) {}
  }
}

class _Tag extends StatelessWidget {
  final String text;
  final Color color;
  const _Tag(this.text, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
      child: Text(text, style: GoogleFonts.spaceGrotesk(fontSize: 10, color: Colors.white54, fontWeight: FontWeight.w600)),
    );
  }
}
