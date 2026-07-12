// ignore_for_file: deprecated_member_use
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

// ─────────────────────────────────────────────────────────────
// Data model
// ─────────────────────────────────────────────────────────────

class DownloadTask {
  final String id;
  final String url;
  String suggestedFilename;
  String savePath = '';

  double progress = 0;
  String status =
      'pending'; // pending | downloading | completed | error | paused | cancelled
  String speed = '0 B/s';
  int totalBytes = 0;
  int downloadedBytes = 0;
  String? errorMessage;

  String? cookies;
  String? userAgent;
  String? referer;

  CancelToken? cancelToken;
  DateTime? startTime;
  DateTime? lastUpdateTime;
  int lastUpdateBytes = 0;

  DownloadTask({
    required this.id,
    required this.url,
    required this.suggestedFilename,
    this.cookies,
    this.userAgent,
    this.referer,
  });
}

// ─────────────────────────────────────────────────────────────
// State / logic
// ─────────────────────────────────────────────────────────────

class BrowserDownloadManager extends ChangeNotifier {
  static final BrowserDownloadManager globalState = BrowserDownloadManager();

  final List<DownloadTask> tasks = [];
  final Dio dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(hours: 6),
      sendTimeout: const Duration(seconds: 60),
      followRedirects: true,
      maxRedirects: 15,
      validateStatus: (status) =>
          (status ?? 0) < 500, // Accept 2xx, 3xx, 4xx (some CDNs return 206)
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.6367.82 Mobile Safari/537.36',
        'Accept': '*/*',
        'Accept-Language': 'en-US,en;q=0.9',
        'Accept-Encoding': 'identity',
        'Connection': 'keep-alive',
        'DNT': '1',
        'Upgrade-Insecure-Requests': '1',
      },
    ),
  );
  int _blockedAdsCount = 0;
  bool isAdBlockEnabled = true;

  int get blockedAdsCount => _blockedAdsCount;

  void toggleAdBlock() {
    isAdBlockEnabled = !isAdBlockEnabled;
    notifyListeners();
  }

  void incrementBlockedAds() {
    _blockedAdsCount++;
    notifyListeners();
  }

  // ── Static helpers ───────────────────────────────────────────

  static void addDownload(
    String url,
    String filename, {
    String? userAgent,
    String? cookies,
    String? referer,
  }) {
    globalState.startDownload(
      url,
      filename,
      userAgent: userAgent,
      cookies: cookies,
      referer: referer,
    );
  }

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Color(0xFF0D0D22),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: BrowserDownloadManagerWidget(
                scrollController: scrollController,
              ),
            );
          },
        );
      },
    );
  }

  // ── Native MediaScanner ──────────────────────────────────────

  static const _mediaScannerChannel = MethodChannel(
    'com.jarvis.jarvis_ai/media_scanner',
  );

  Future<void> _scanMediaFile(String filePath) async {
    try {
      await _mediaScannerChannel.invokeMethod('scanFile', {'path': filePath});
    } catch (_) {}
  }

  // ── Storage path ─────────────────────────────────────────────

  Future<String> _getDownloadsDir() async {
    if (Platform.isAndroid) {
      final externalDirs = await getExternalStorageDirectories();
      if (externalDirs != null && externalDirs.isNotEmpty) {
        final sd = externalDirs.first.path.split('Android').first;
        final dir = Directory('${sd}Download/JARVIS');
        if (!await dir.exists()) await dir.create(recursive: true);
        return dir.path;
      }
    }
    final dir = await getApplicationDocumentsDirectory();
    final fallback = Directory('${dir.path}/Downloads');
    if (!await fallback.exists()) await fallback.create(recursive: true);
    return fallback.path;
  }

  // ── Filename resolver ─────────────────────────────────────────

  String _resolveFilename(String url, Response? response, String suggested) {
    // 1. Content-Disposition header
    if (response != null) {
      final cd = response.headers.value('content-disposition') ?? '';
      // Match: filename=value  or  filename*=UTF-8''value
      // Character class excludes ; \n " ' from the captured value
      final m = RegExp(
        'filename[^;\\n]*=\\s*(?:UTF-8\'\')?([^;\\n"\']+)',
        caseSensitive: false,
      ).firstMatch(cd);
      if (m != null) {
        final name = Uri.decodeComponent(
          m.group(1)!.trim().replaceAll('"', ''),
        );
        if (name.isNotEmpty) return _sanitize(name);
      }
    }
    // 2. Suggested filename (real filename, not a URL)
    if (suggested.isNotEmpty &&
        !suggested.startsWith('http') &&
        suggested.contains('.')) {
      return _sanitize(Uri.decodeComponent(suggested));
    }
    // 3. Last path segment of the URL
    try {
      final segs = Uri.parse(
        url,
      ).pathSegments.where((s) => s.isNotEmpty).toList();
      if (segs.isNotEmpty) {
        final last = _sanitize(Uri.decodeComponent(segs.last));
        if (last.isNotEmpty) return last;
      }
    } catch (_) {}
    // 4. Fallback
    return 'download_${DateTime.now().millisecondsSinceEpoch}';
  }

  String _sanitize(String name) =>
      name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();

  // ── Core download logic ───────────────────────────────────────

  Future<void> startDownload(
    String url,
    String filename, {
    String? userAgent,
    String? cookies,
    String? referer,
    DownloadTask? existingTask,
  }) async {
    final task =
        existingTask ??
        DownloadTask(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          url: url,
          suggestedFilename: filename,
          userAgent: userAgent,
          cookies: cookies,
          referer: referer,
        );

    if (existingTask == null) tasks.insert(0, task);
    notifyListeners();

    final ua = (userAgent?.isNotEmpty == true)
        ? userAgent!
        : 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/124.0.6367.82 Mobile Safari/537.36';

    final baseHeaders = <String, String>{
      'User-Agent': ua,
      'Accept': '*/*',
      'Accept-Language': 'en-US,en;q=0.9',
      'Accept-Encoding': 'identity',
      'Connection': 'keep-alive',
      if (cookies?.isNotEmpty == true) 'Cookie': cookies!,
      if (referer?.isNotEmpty == true) 'Referer': referer!,
    };

    try {
      final dirPath = await _getDownloadsDir();
      task.status = 'downloading';
      task.startTime = DateTime.now();
      task.lastUpdateTime = task.startTime;
      task.cancelToken = CancelToken();
      notifyListeners();

      // Step 1 — HEAD to resolve real filename
      String resolvedName = filename;
      try {
        final head = await dio.head(
          url,
          options: Options(
            followRedirects: true,
            headers: baseHeaders,
            receiveTimeout: const Duration(seconds: 15),
          ),
        );
        resolvedName = _resolveFilename(url, head, filename);
      } catch (_) {
        resolvedName = _resolveFilename(url, null, filename);
      }
      task.suggestedFilename = resolvedName;

      // Step 2 — Auto-rename if file exists
      String savePath = '$dirPath/$resolvedName';
      int counter = 1;
      while (await File(savePath).exists()) {
        final dot = resolvedName.lastIndexOf('.');
        savePath = dot != -1
            ? '$dirPath/${resolvedName.substring(0, dot)}_$counter${resolvedName.substring(dot)}'
            : '$dirPath/${resolvedName}_$counter';
        counter++;
      }
      if (task.savePath.isEmpty || existingTask == null) {
        task.savePath = savePath;
      }
      notifyListeners();

      // Progress callback
      void onProgress(int received, int total) {
        final now = DateTime.now();
        final ms = now.difference(task.lastUpdateTime!).inMilliseconds;
        if (ms > 400) {
          task.speed =
              '${_formatBytes(((received - task.lastUpdateBytes) / (ms / 1000)).round())}/s';
          task.lastUpdateTime = now;
          task.lastUpdateBytes = received;
          task.progress = total > 0 ? received / total : 0;
          task.totalBytes = total;
          task.downloadedBytes = received;
          notifyListeners();
        }
      }

      // Step 3 — Download (retry with minimal headers on failure)
      try {
        await dio.download(
          url,
          task.savePath,
          cancelToken: task.cancelToken,
          options: Options(
            followRedirects: true,
            maxRedirects: 10,
            headers: baseHeaders,
            receiveTimeout: const Duration(hours: 6),
            sendTimeout: const Duration(seconds: 30),
          ),
          onReceiveProgress: onProgress,
        );
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) rethrow;
        // Retry with minimal headers (some CDNs reject cookies / referer)
        await dio.download(
          url,
          task.savePath,
          cancelToken: task.cancelToken,
          options: Options(
            followRedirects: true,
            maxRedirects: 10,
            headers: {'User-Agent': ua, 'Accept': '*/*'},
            receiveTimeout: const Duration(hours: 6),
          ),
          onReceiveProgress: onProgress,
        );
      }

      task.status = 'completed';
      task.progress = 1.0;
      notifyListeners();
      await _scanMediaFile(task.savePath);
    } catch (e) {
      if (e is DioException && CancelToken.isCancel(e)) {
        task.status = 'cancelled';
      } else {
        task.status = 'error';
        task.errorMessage = e.toString();
      }
      notifyListeners();
    }
  }

  // ── Task controls ────────────────────────────────────────────

  void pauseTask(DownloadTask task) {
    task.cancelToken?.cancel();
    task.status = 'paused';
    notifyListeners();
  }

  void resumeTask(DownloadTask task) {
    if (task.status == 'paused' ||
        task.status == 'error' ||
        task.status == 'cancelled') {
      startDownload(
        task.url,
        task.suggestedFilename,
        userAgent: task.userAgent,
        cookies: task.cookies,
        referer: task.referer,
        existingTask: task,
      );
    }
  }

  void cancelTask(DownloadTask task) {
    task.cancelToken?.cancel();
    task.status = 'cancelled';
    notifyListeners();
  }

  void removeTask(DownloadTask task) {
    tasks.remove(task);
    if (task.savePath.isNotEmpty) {
      final f = File(task.savePath);
      if (f.existsSync()) f.deleteSync();
    }
    notifyListeners();
  }

  Future<void> openFile(DownloadTask task) async {
    if (task.status == 'completed' && await File(task.savePath).exists()) {
      OpenFilex.open(task.savePath);
    }
  }

  // ── Utilities ────────────────────────────────────────────────

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

// ─────────────────────────────────────────────────────────────
// UI Widget
// ─────────────────────────────────────────────────────────────

class BrowserDownloadManagerWidget extends StatefulWidget {
  final ScrollController scrollController;

  const BrowserDownloadManagerWidget({
    super.key,
    required this.scrollController,
  });

  @override
  State<BrowserDownloadManagerWidget> createState() =>
      _BrowserDownloadManagerWidgetState();
}

class _BrowserDownloadManagerWidgetState
    extends State<BrowserDownloadManagerWidget> {
  void _showAdBlockPopup(BuildContext context, BrowserDownloadManager state) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF10102A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'AdBlocker',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            state.isAdBlockEnabled
                ? 'AdBlocker is currently ON.\nWould you like to turn it off?'
                : 'AdBlocker is currently OFF.\nWould you like to turn it on?',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white38),
              ),
            ),
            TextButton(
              onPressed: () {
                state.toggleAdBlock();
                Navigator.pop(ctx);
              },
              child: Text(
                state.isAdBlockEnabled ? 'Turn OFF' : 'Turn ON',
                style: TextStyle(
                  color: state.isAdBlockEnabled
                      ? Colors.redAccent
                      : Colors.greenAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: BrowserDownloadManager.globalState,
      builder: (context, _) {
        final state = BrowserDownloadManager.globalState;
        final tasks = state.tasks;

        return Column(
          children: [
            // Drag handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 5),
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '⬇ Download Manager',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => _showAdBlockPopup(context, state),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: state.isAdBlockEnabled
                                ? Colors.blueAccent.withAlpha(25)
                                : Colors.redAccent.withAlpha(25),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: state.isAdBlockEnabled
                                  ? Colors.blueAccent.withAlpha(76)
                                  : Colors.redAccent.withAlpha(76),
                            ),
                          ),
                          child: Text(
                            state.isAdBlockEnabled
                                ? '🛡 ${state.blockedAdsCount} Ads Blocked'
                                : '🛡 AdBlock OFF',
                            style: TextStyle(
                              color: state.isAdBlockEnabled
                                  ? Colors.blueAccent
                                  : Colors.redAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white54),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const Divider(color: Colors.white10),

            Expanded(
              child: tasks.isEmpty
                  ? const Center(
                      child: Text(
                        'No downloads yet.',
                        style: TextStyle(color: Colors.white38),
                      ),
                    )
                  : ListView.builder(
                      controller: widget.scrollController,
                      itemCount: tasks.length,
                      itemBuilder: (context, index) => _buildItem(tasks[index]),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildItem(DownloadTask task) {
    Color statusColor;
    IconData statusIcon;
    switch (task.status) {
      case 'downloading':
        statusColor = Colors.blue;
        statusIcon = Icons.downloading;
        break;
      case 'paused':
        statusColor = Colors.orangeAccent;
        statusIcon = Icons.pause_circle;
        break;
      case 'completed':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case 'error':
        statusColor = Colors.red;
        statusIcon = Icons.error;
        break;
      case 'cancelled':
        statusColor = Colors.orange;
        statusIcon = Icons.cancel;
        break;
      default:
        statusColor = Colors.white54;
        statusIcon = Icons.hourglass_empty;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(statusIcon, color: statusColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  task.suggestedFilename.isNotEmpty
                      ? task.suggestedFilename
                      : task.url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // Actions
              if (task.status == 'downloading') ...[
                IconButton(
                  icon: const Icon(Icons.pause, color: Colors.orangeAccent),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () =>
                      BrowserDownloadManager.globalState.pauseTask(task),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.stop_circle, color: Colors.redAccent),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () =>
                      BrowserDownloadManager.globalState.cancelTask(task),
                ),
              ] else if (task.status == 'paused' ||
                  task.status == 'error' ||
                  task.status == 'cancelled') ...[
                IconButton(
                  icon: const Icon(Icons.play_arrow, color: Colors.blue),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () =>
                      BrowserDownloadManager.globalState.resumeTask(task),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.redAccent),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () =>
                      BrowserDownloadManager.globalState.removeTask(task),
                ),
              ] else if (task.status == 'completed') ...[
                IconButton(
                  icon: const Icon(Icons.folder_open, color: Colors.white70),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () =>
                      BrowserDownloadManager.globalState.openFile(task),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.white54),
                  color: const Color(0xFF1E1E2C),
                  onSelected: (val) {
                    if (val == 'share') {
                      SharePlus.instance.share(
                        ShareParams(
                          files: [XFile(task.savePath)],
                          text: task.suggestedFilename,
                        ),
                      );
                    } else if (val == 'delete') {
                      BrowserDownloadManager.globalState.removeTask(task);
                    }
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'share',
                      child: Text(
                        'Share',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text(
                        'Delete File',
                        style: TextStyle(color: Colors.redAccent),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          if (task.status == 'downloading') ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: task.progress > 0 ? task.progress : null,
                backgroundColor: Colors.white10,
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${(task.progress * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                Text(
                  '${BrowserDownloadManager.globalState._formatBytes(task.downloadedBytes)} / '
                  '${BrowserDownloadManager.globalState._formatBytes(task.totalBytes)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                Text(
                  task.speed,
                  style: const TextStyle(color: Colors.blue, fontSize: 12),
                ),
              ],
            ),
          ] else if (task.status == 'error' && task.errorMessage != null) ...[
            Text(
              task.status.toUpperCase(),
              style: TextStyle(
                color: statusColor,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              task.errorMessage!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.red, fontSize: 10),
            ),
          ] else ...[
            Text(
              task.status.toUpperCase(),
              style: TextStyle(
                color: statusColor,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
