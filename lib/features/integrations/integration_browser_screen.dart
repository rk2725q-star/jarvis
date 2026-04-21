// ignore_for_file: unnecessary_brace_in_string_interps, prefer_interpolation_to_compose_strings, use_build_context_synchronously
import 'dart:async';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/router/ai_router.dart';
import 'integrations_model.dart';
import 'browser_download_manager.dart';
import 'browser_adblock_scripts.dart';

class AgentMessage {
  final String text;
  final bool isUser;
  AgentMessage(this.text, {required this.isUser});
}

class BrowserTab {
  final String id;
  InAppWebViewController? controller;
  String url;
  String title;
  double progress = 0;
  bool isLoading = true;
  bool canGoBack = false;
  bool canGoForward = false;
  late Widget webViewWidget;

  BrowserTab({required this.id, required this.url, this.title = 'New Tab'});
}

class IntegrationBrowserScreen extends StatefulWidget {
  final AIIntegration integration;
  const IntegrationBrowserScreen({super.key, required this.integration});

  @override
  State<IntegrationBrowserScreen> createState() =>
      _IntegrationBrowserScreenState();
}

class _IntegrationBrowserScreenState extends State<IntegrationBrowserScreen>
    with SingleTickerProviderStateMixin {
  
  final List<BrowserTab> _tabs = [];
  int _currentTabIndex = 0;

  BrowserTab get _currentTab => _tabs[_currentTabIndex];

  // Whitelist: domains that must never be blocked
  // Movie/streaming sites are allowed — only truly malicious content is blocked
  static const _safedomains = [
    // Search & productivity
    'google.com', 'google.co.in', 'google.',
    'gstatic.com', 'googleapis.com', 'youtube.com',
    'youtu.be', 'docs.google.com', 'forms.google.com',
    'accounts.google.com', 'cloudflare.com',
    // Shopping
    'amazon.com', 'amazon.in', 'flipkart.com',
    'myntra.com', 'meesho.com', 'snapdeal.com',
    // Social
    'facebook.com', 'instagram.com', 'twitter.com',
    'whatsapp.com', 'telegram.org', 'reddit.com',
    // Tech
    'microsoft.com', 'apple.com', 'github.com',
    'stackoverflow.com', 'wikipedia.org',
    // Movie download sites — unrestricted access
    'moviesda', 'isaidub', 'tamilrockers', 'kuttymovies',
    'filmyzilla', 'bollyflix', 'vegamovies', 'skymovieshd',
    'sdmoviespoint', '9xmovies', 'mp4moviez', 'downloadhub',
    'movies4u', 'movierulz', 'jalshamoviez', 'cinemavilla',
    'tamilyogi', 'tamilblasters', 'kuttymovies', 'cinevood',
    'katmovie', 'ibomma', 'hdmovie2', 'dvdplay',
    'filmyhit', 'worldfree4u', '1337x.to', 'rarbg',
    'thepiratebay', 'yts.mx', 'eztv', 'limetorrents',
    'torrentgalaxy', 'torlock', 'kickasstorrents',
    // Music
    'pagalworld', 'mr-jatt', 'djpunjab', 'songspk',
    'wynk.in', 'gaana.com', 'jiosaavn.com',
  ];

  // Only block sites that are genuinely dangerous (malware, fraud, phishing)
  // Movie piracy sites are NOT blocked — user has freedom of access
  static const _dangerousDomains = [
    'malware', 'phishing', 'ransomware',
    'funinr.com', 'bet365fraud', 'scam-',
  ];

  bool _isAd(String url) {
    if (!BrowserDownloadManager.globalState.isAdBlockEnabled) return false;
    if (url.isEmpty) return false;
    final lowerUrl = url.toLowerCase();

    // Always allow safe/movie domains
    if (_safedomains.any((d) => lowerUrl.contains(d))) return false;

    // Block only pure ad-network/tracker domains
    if (BrowserAdBlockRules.adBlockDomains.any((d) => lowerUrl.contains(d))) return true;

    // Block genuinely dangerous sites
    if (_dangerousDomains.any((d) => lowerUrl.contains(d))) return true;

    return false;
  }

  // Agent panel
  bool _agentPanelOpen = false;
  final _agentController = TextEditingController();
  bool _agentRunning = false;
  String _agentStatus = '';
  final List<AgentMessage> _agentMessages = [
    AgentMessage('Hello! I can analyze this page or automate tasks like clicking and filling forms. What would you like to do?', isUser: false),
  ];
  late AnimationController _agentAnim;
  
  // AdBlock tools
  final List<ContentBlocker> _contentBlockers = [];
  late final UserScript _youtubeAdScript;
  late final UserScript _generalAdScript;

  Color get _primary => Color(widget.integration.gradientColors[0]);
  Color get _secondary => Color(widget.integration.gradientColors[1]);

  @override
  void initState() {
    super.initState();
    _agentAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    // Setup ContentBlockers for Ad domains
    for (final domain in BrowserAdBlockRules.adBlockDomains) {
      _contentBlockers.add(ContentBlocker(
        trigger: ContentBlockerTrigger(urlFilter: '.*$domain.*'),
        action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK)
      ));
    }

    _youtubeAdScript = UserScript(
      source: BrowserAdBlockRules.youtubeAdScript,
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
    );
    _generalAdScript = UserScript(
      source: BrowserAdBlockRules.generalAdScript,
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
    );

    _addNewTab(widget.integration.url, widget.integration.name);
  }

  void _addNewTab(String url, String title) {
    final newTab = BrowserTab(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      url: url,
      title: title,
    );
    newTab.webViewWidget = _buildWebViewForTab(newTab);
    setState(() {
      _tabs.add(newTab);
      _currentTabIndex = _tabs.length - 1;
    });
  }

  Widget _buildWebViewForTab(BrowserTab tab) {
    return InAppWebView(
      key: ValueKey(tab.id),
      initialUrlRequest: URLRequest(url: WebUri(tab.url)),
      initialSettings: InAppWebViewSettings(
        // ── Core JS & storage ─────────────────────────────────────────────
        javaScriptEnabled: true,
        domStorageEnabled: true,
        databaseEnabled: true,
        cacheEnabled: true,
        cacheMode: CacheMode.LOAD_DEFAULT,

        // ── Media ─────────────────────────────────────────────────────────
        allowsInlineMediaPlayback: true,
        mediaPlaybackRequiresUserGesture: false,

        // ── Cookies & security ────────────────────────────────────────────
        thirdPartyCookiesEnabled: true,
        sharedCookiesEnabled: true,
        mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,

        // ── Viewport: app-like full-width rendering ────────────────────────
        useWideViewPort: true,
        loadWithOverviewMode: true,
        supportZoom: true,
        builtInZoomControls: true,
        displayZoomControls: false,

        // ── Download intercept for ALL file types ─────────────────────────
        useOnDownloadStart: true,
        allowFileAccess: true,
        allowContentAccess: true,

        // ── Multi-window / tabs ───────────────────────────────────────────
        javaScriptCanOpenWindowsAutomatically: true,
        supportMultipleWindows: true,

        // ── App-like UX: scroll, overscroll, selection ────────────────────
        disableHorizontalScroll: false,
        disableVerticalScroll: false,
        overScrollMode: OverScrollMode.NEVER,
        verticalScrollBarEnabled: false,
        horizontalScrollBarEnabled: false,

        // ── AdBlock content rules ─────────────────────────────────────────
        contentBlockers: BrowserDownloadManager.globalState.isAdBlockEnabled
            ? _contentBlockers
            : [],

        // ── UA: Android Chrome — maximizes site compatibility ─────────────
        userAgent:
            'Mozilla/5.0 (Linux; Android 14; Pixel 8) '
            'AppleWebKit/537.36 (KHTML, like Gecko) '
            'Chrome/124.0.6367.82 Mobile Safari/537.36',

        // ── Long-press context menu for image save ────────────────────────
        disableContextMenu: false,

        // ── Transparent background so loading doesn't flash white ─────────
        transparentBackground: true,
      ),
      initialUserScripts: UnmodifiableListView<UserScript>([
        _youtubeAdScript,
        _generalAdScript,
        // Inject CSS that makes websites feel app-like (no blue tap highlight, smooth scroll)
        UserScript(
          source: '''
(function() {
  // Prevent iOS-style tap flash / Android blue rectangle
  var s = document.createElement('style');
  s.textContent = '* { -webkit-tap-highlight-color: transparent !important; } '
    + 'html, body { overflow-x: hidden !important; scroll-behavior: smooth !important; }'
    + '::-webkit-scrollbar { display: none !important; }';
  document.head.appendChild(s);
})();
''',
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        ),
      ]),

      onWebViewCreated: (c) => tab.controller = c,

      onLoadStart: (c, url) {
        tab.isLoading = true;
        tab.url = url?.toString() ?? '';
        if (_currentTab == tab && mounted) setState(() {});
      },
      onProgressChanged: (c, p) {
        tab.progress = p / 100;
        if (_currentTab == tab && mounted) setState(() {});
      },
      onLoadStop: (c, url) async {
        tab.isLoading = false;
        tab.url = url?.toString() ?? '';
        tab.canGoBack = await c.canGoBack();
        tab.canGoForward = await c.canGoForward();
        tab.title = await c.getTitle() ?? tab.url;
        if (_currentTab == tab && mounted) setState(() {});
      },

      onCreateWindow: (c, req) async {
        final url = req.request.url?.toString() ?? '';
        if (url.isEmpty) return false;
        if (_isAd(url)) {
          BrowserDownloadManager.globalState.incrementBlockedAds();
          return false;
        }
        _addNewTab(url, url);
        return true;
      },

      // ── URL interception: torrents, audio, video, downloads ──────────────
      shouldOverrideUrlLoading: (c, action) async {
        final url = action.request.url?.toString() ?? '';
        final lower = url.toLowerCase();

        // Magnet links → external torrent client
        if (lower.startsWith('magnet:')) {
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
          return NavigationActionPolicy.CANCEL;
        }

        // .torrent files → download manager
        if (lower.contains('.torrent')) {
          _triggerDownload(url, action);
          return NavigationActionPolicy.CANCEL;
        }

        // Direct audio/video file links → download manager
        final dlExts = [
          '.mp3', '.mp4', '.m4a', '.flac', '.aac', '.ogg', '.wav', '.opus',
          '.mkv', '.avi', '.webm', '.mov',
          '.zip', '.rar', '.7z', '.tar', '.gz',
          '.apk', '.xapk',
          '.pdf', '.doc', '.docx', '.xls', '.xlsx',
        ];
        final urlPath = (Uri.tryParse(url)?.path.toLowerCase()) ?? lower;
        if (dlExts.any((ext) => urlPath.endsWith(ext))) {
          _triggerDownload(url, action);
          return NavigationActionPolicy.CANCEL;
        }

        // Ad-block
        if (_isAd(url)) {
          BrowserDownloadManager.globalState.incrementBlockedAds();
          return NavigationActionPolicy.CANCEL;
        }

        return NavigationActionPolicy.ALLOW;
      },

      // ── System download intercept (e.g. Content-Disposition: attachment) ──
      onDownloadStartRequest: (controller, request) async {
        String cookiesString = '';
        try {
          final cookies =
              await CookieManager.instance().getCookies(url: request.url);
          cookiesString =
              cookies.map((c) => '${c.name}=${c.value}').join('; ');
        } catch (_) {}
        final referer =
            _currentTab.url.isNotEmpty ? _currentTab.url : null;
        BrowserDownloadManager.addDownload(
          request.url.toString(),
          request.suggestedFilename ?? '',
          userAgent: request.userAgent,
          cookies: cookiesString,
          referer: referer,
        );
        if (!mounted) return;
        BrowserDownloadManager.show(context);
      },

      // ── Long-press: image / link / text context menu ──────────────────────
      onLongPressHitTestResult: (controller, hitTestResult) async {
        final extra = hitTestResult.extra ?? '';
        final type = hitTestResult.type;

        // ── Image long-press ────────────────────────────────────────────────
        if (type == InAppWebViewHitTestResultType.IMAGE_TYPE ||
            type == InAppWebViewHitTestResultType.SRC_IMAGE_ANCHOR_TYPE) {
          if (!mounted) return;
          final imgUrl = extra;
          // Also try to grab selected text for copy
          final selectedText = (await controller.getSelectedText())?.trim() ?? '';
          if (!mounted) return;
          showModalBottomSheet(
            context: context,
            backgroundColor: const Color(0xFF10102A),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            builder: (ctx) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Copy URL
                  ListTile(
                    leading: const Icon(Icons.copy, color: Colors.amber),
                    title: const Text('Copy Image URL',
                        style: TextStyle(color: Colors.white)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _copyToClipboard(imgUrl);
                    },
                  ),
                  if (selectedText.isNotEmpty)
                    ListTile(
                      leading: const Icon(Icons.text_snippet, color: Colors.greenAccent),
                      title: Text('Copy "${selectedText.length > 40 ? selectedText.substring(0, 40) + "…" : selectedText}"',
                          style: const TextStyle(color: Colors.white)),
                      onTap: () {
                        Navigator.pop(ctx);
                        _copyToClipboard(selectedText);
                      },
                    ),
                  ListTile(
                    leading: const Icon(Icons.download, color: Colors.blueAccent),
                    title: const Text('Save Image',
                        style: TextStyle(color: Colors.white)),
                    subtitle: Text(
                      imgUrl.length > 55
                          ? '…${imgUrl.substring(imgUrl.length - 55)}'
                          : imgUrl,
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                      maxLines: 1,
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      BrowserDownloadManager.addDownload(
                        imgUrl, '', referer: _currentTab.url,
                      );
                      BrowserDownloadManager.show(context);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.open_in_browser, color: Colors.white54),
                    title: const Text('Open in New Tab',
                        style: TextStyle(color: Colors.white)),
                    onTap: () { Navigator.pop(ctx); _addNewTab(imgUrl, imgUrl); },
                  ),
                ],
              ),
            ),
          );
          return;
        }

        // ── Link / anchor long-press ────────────────────────────────────────
        if ((type == InAppWebViewHitTestResultType.SRC_ANCHOR_TYPE ||
                type == InAppWebViewHitTestResultType.SRC_IMAGE_ANCHOR_TYPE) &&
            extra.isNotEmpty) {
          if (!mounted) return;
          final selectedText = (await controller.getSelectedText())?.trim() ?? '';
          if (!mounted) return;
          showModalBottomSheet(
            context: context,
            backgroundColor: const Color(0xFF10102A),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            builder: (ctx) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.copy, color: Colors.amber),
                    title: const Text('Copy Link',
                        style: TextStyle(color: Colors.white)),
                    subtitle: Text(
                      extra.length > 55 ? '…${extra.substring(extra.length - 55)}' : extra,
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                      maxLines: 1,
                    ),
                    onTap: () { Navigator.pop(ctx); _copyToClipboard(extra); },
                  ),
                  if (selectedText.isNotEmpty)
                    ListTile(
                      leading: const Icon(Icons.text_snippet, color: Colors.greenAccent),
                      title: Text('Copy "${selectedText.length > 40 ? selectedText.substring(0, 40) + "…" : selectedText}"',
                          style: const TextStyle(color: Colors.white)),
                      onTap: () { Navigator.pop(ctx); _copyToClipboard(selectedText); },
                    ),
                  ListTile(
                    leading: const Icon(Icons.download, color: Colors.blueAccent),
                    title: const Text('Download Link',
                        style: TextStyle(color: Colors.white)),
                    onTap: () {
                      Navigator.pop(ctx);
                      BrowserDownloadManager.addDownload(
                        extra, '', referer: _currentTab.url,
                      );
                      BrowserDownloadManager.show(context);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.open_in_new, color: Colors.white54),
                    title: const Text('Open in New Tab',
                        style: TextStyle(color: Colors.white)),
                    onTap: () { Navigator.pop(ctx); _addNewTab(extra, extra); },
                  ),
                ],
              ),
            ),
          );
          return;
        }

        // ── Plain text selection → show Copy menu ──────────────────────────
        if (type == InAppWebViewHitTestResultType.UNKNOWN_TYPE ||
            extra.isEmpty) {
          final selectedText = (await controller.getSelectedText())?.trim() ?? '';
          if (selectedText.isNotEmpty && mounted) {
            showModalBottomSheet(
              context: context,
              backgroundColor: const Color(0xFF10102A),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              builder: (ctx) => SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.copy, color: Colors.amber),
                      title: Text(
                        'Copy: "${selectedText.length > 50 ? selectedText.substring(0, 50) : selectedText}…"',
                        style: const TextStyle(color: Colors.white),
                      ),
                      onTap: () { Navigator.pop(ctx); _copyToClipboard(selectedText); },
                    ),
                    ListTile(
                      leading: const Icon(Icons.search, color: Colors.blueAccent),
                      title: Text('Search: "${selectedText.length > 30 ? '${selectedText.substring(0, 30)}…' : selectedText}"',
                          style: const TextStyle(color: Colors.white)),
                      onTap: () {
                        Navigator.pop(ctx);
                        _addNewTab('https://www.google.com/search?q=${Uri.encodeComponent(selectedText)}', 'Search');
                      },
                    ),
                  ],
                ),
              ),
            );
          }
        }
      },
    );
  }

  /// Helper: extract cookies and fire a download
  Future<void> _triggerDownload(String url, NavigationAction action) async {
    String cookiesString = '';
    try {
      final cookies =
          await CookieManager.instance().getCookies(url: WebUri(url));
      cookiesString = cookies.map((c) => '${c.name}=${c.value}').join('; ');
    } catch (_) {}
    BrowserDownloadManager.addDownload(
      url,
      '',
      userAgent: action.request.headers?['User-Agent'],
      cookies: cookiesString,
      referer: _currentTab.url.isNotEmpty ? _currentTab.url : null,
    );
    if (mounted) BrowserDownloadManager.show(context);
  }

  @override
  void dispose() {
    _agentController.dispose();
    _agentAnim.dispose();
    super.dispose();
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_tabs.isEmpty) return const Scaffold(backgroundColor: Color(0xFF07070F));
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: const Color(0xFF07070F),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildTopBar(),
            if (_currentTab.isLoading)
              LinearProgressIndicator(
                value: _currentTab.progress == 0 ? null : _currentTab.progress,
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation(_primary),
                minHeight: 2,
              )
            else
              const SizedBox(height: 2),

            // ── WebView Tabs ───────────────────────────────────────────────
            Expanded(
              child: Stack(
                children: [
                  IndexedStack(
                    index: _currentTabIndex,
                    children: _tabs.map((t) => t.webViewWidget).toList(),
                  ),
                  if (_agentPanelOpen) _buildAgentPanel(),
                ],
              ),
            ),

            _buildBottomBar(bottomPad),
          ],
        ),
      ),
    );
  }

  // ─── Top bar: JARVIS-branded address bar ────────────────────────────────────

  Widget _buildTopBar() {
    final displayUrl = _currentTab.url.isEmpty
        ? widget.integration.url
        : _currentTab.url
            .replaceAll('https://', '')
            .replaceAll('http://', '');

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A18),
        border: const Border(
          bottom: BorderSide(color: Color(0xFF1A1A2E), width: 0.8),
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _primary.withAlpha(15),
            const Color(0xFF0A0A18),
          ],
        ),
      ),
      child: Row(
        children: [
          // Integration identity
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                _primary.withAlpha(38),
                _secondary.withAlpha(25),
              ]),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _primary.withAlpha(64)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.integration.emoji,
                    style: const TextStyle(fontSize: 13)),
                const SizedBox(width: 4),
                ShaderMask(
                  shaderCallback: (b) =>
                      LinearGradient(colors: [_primary, _secondary])
                          .createShader(b),
                  child: Text(
                    widget.integration.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          // URL pill
          Expanded(
            child: GestureDetector(
              onTap: _showAddressBarInput,
              child: Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(10),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: Colors.white.withAlpha(20)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lock_rounded,
                        size: 10, color: _primary.withAlpha(178)),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        displayUrl,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(width: 8),

          // Reload / Stop
          _TopBarBtn(
            icon:
                _currentTab.isLoading ? Icons.close_rounded : Icons.refresh_rounded,
            onTap: () {
              if (_currentTab.isLoading) {
                _currentTab.controller?.stopLoading();
              } else {
                _currentTab.controller?.reload();
              }
            },
          ),
        ],
      ),
    );
  }

  void _showAddressBarInput() {
    final c = TextEditingController(text: _currentTab.url);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF10102A),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Navigate to URL',
            style: TextStyle(color: Colors.white, fontSize: 15)),
        content: TextField(
          controller: c,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white.withAlpha(12),
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            hintText: 'https://',
            hintStyle: const TextStyle(color: Colors.white30),
          ),
          onSubmitted: (input) {
            Navigator.of(ctx).pop();
            final url = _resolveUrl(input.trim());
            _currentTab.controller?.loadUrl(
                urlRequest: URLRequest(url: WebUri(url)));
          },
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.white38))),
        ],
      ),
    );
  }

  // ─── Tabs Manager Menu ──────────────────────────────────────────────────
  void _showTabsMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF10102A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheetState) {
          return SizedBox(
            height: MediaQuery.of(context).size.height * 0.7,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Tabs (${_tabs.length})', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.add_circle, color: Colors.blueAccent),
                        onPressed: () {
                          _addNewTab('https://google.com', 'New Tab');
                          Navigator.pop(ctx);
                        },
                      )
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _tabs.length,
                    itemBuilder: (ctx, index) {
                      final tab = _tabs[index];
                      final isSelected = index == _currentTabIndex;
                      return ListTile(
                        selected: isSelected,
                        selectedTileColor: Colors.white.withAlpha(20),
                        title: Text(tab.title.isNotEmpty ? tab.title : tab.url, style: TextStyle(color: isSelected ? Colors.blueAccent : Colors.white)),
                        subtitle: Text(tab.url, style: const TextStyle(color: Colors.white30, fontSize: 11), maxLines: 1),
                        trailing: IconButton(
                          icon: const Icon(Icons.close, color: Colors.white54),
                          onPressed: () {
                            if (_tabs.length == 1) return; // don't close last tab
                            setState(() {
                              _tabs.removeAt(index);
                              if (_currentTabIndex >= _tabs.length) _currentTabIndex = _tabs.length - 1;
                            });
                            setSheetState((){});
                          },
                        ),
                        onTap: () {
                          setState(() => _currentTabIndex = index);
                          Navigator.pop(ctx);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  // ─── JARVIS Agentic Control Panel ──────────────────────────────────────────

  Widget _buildAgentPanel() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Material(
        color: Colors.transparent,
        child: Container(
          height: MediaQuery.of(context).size.height * 0.55,
          decoration: BoxDecoration(
            color: const Color(0xFF0D0D22),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: _primary.withAlpha(76), width: 0.8),
            boxShadow: [
              BoxShadow(
                color: _primary.withAlpha(38),
                blurRadius: 30,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.only(top: 10),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    ShaderMask(
                      shaderCallback: (b) => LinearGradient(colors: [_primary, _secondary]).createShader(b),
                      child: const Text('⚡ JARVIS Web Agent', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => setState(() => _agentPanelOpen = false),
                      child: const Icon(Icons.close, color: Colors.white30, size: 18),
                    ),
                  ],
                ),
              ),
              
              // Chat History
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  reverse: false,
                  itemCount: _agentMessages.length,
                  itemBuilder: (ctx, i) {
                    final msg = _agentMessages[i];
                    return Align(
                      alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.92),
                        decoration: BoxDecoration(
                          color: msg.isUser ? _primary.withAlpha(38) : Colors.white.withAlpha(12),
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(16),
                            topRight: const Radius.circular(16),
                            bottomLeft: Radius.circular(msg.isUser ? 16 : 4),
                            bottomRight: Radius.circular(msg.isUser ? 4 : 16),
                          ),
                          border: Border.all(color: msg.isUser ? _primary.withAlpha(76) : Colors.white12),
                        ),
                        child: _buildAgentMessageContent(msg.text, msg.isUser),
                      ),
                    );
                  },
                ),
              ),

              // Status line
              if (_agentStatus.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    children: [
                      if (_agentRunning)
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.5, valueColor: AlwaysStoppedAnimation(_primary)),
                        ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _agentStatus,
                          style: TextStyle(color: _primary, fontSize: 11),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),

              // Input
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(12),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: _primary.withAlpha(102)),
                        ),
                        child: TextField(
                          controller: _agentController,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            hintText: 'Tell JARVIS what to do here...',
                            hintStyle: TextStyle(color: Colors.white30, fontSize: 13),
                            contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          ),
                          onSubmitted: (_) => _runAgent(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: _agentRunning ? null : _runAgent,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(colors: [_primary, _secondary]),
                          boxShadow: [
                            BoxShadow(color: _primary.withAlpha(102), blurRadius: 12, offset: const Offset(0, 4)),
                          ],
                        ),
                        child: _agentRunning
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)),
                              )
                            : const Icon(Icons.bolt_rounded, color: Colors.white, size: 22),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Smartly resolve user input to a URL — never fall through to a search engine
  String _resolveUrl(String input) {
    if (input.isEmpty) return 'https://www.google.com';
    // Already a full URL
    if (input.startsWith('http://') || input.startsWith('https://')) return input;
    // Looks like a domain: contains a dot and no spaces
    final hasDot = input.contains('.');
    final hasSpace = input.contains(' ');
    if (hasDot && !hasSpace) return 'https://$input';
    // Otherwise search
    return 'https://www.google.com/search?q=${Uri.encodeComponent(input)}';
  }

  /// Strip markdown from text while preserving content.
  /// IMPORTANT: In Dart, replaceAll with regex does NOT support $1 backreferences.
  /// Must use replaceAllMapped() for capture-group substitutions.
  String _cleanAgentText(String text) {
    return text
        // Bold **text** → text
        .replaceAllMapped(RegExp(r'\*\*([^*]+)\*\*'), (m) => m.group(1) ?? '')
        // Italic *text* → text
        .replaceAllMapped(RegExp(r'\*([^*]+)\*'), (m) => m.group(1) ?? '')
        // Headings ## → remove hashes
        .replaceAll(RegExp(r'#{1,6}\s*'), '')
        // Inline code `code` → code (keep content)
        .replaceAllMapped(RegExp(r'`{1,3}([^`]*)`{1,3}'), (m) => m.group(1) ?? '')
        // Bullets - item → • item
        .replaceAll(RegExp(r'^[-*]\s+', multiLine: true), '• ')
        // Literal \n in strings → real newline
        .replaceAll(r'\n', '\n')
        // Collapse 3+ newlines → 2
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  /// Detect if text contains a markdown table (has | separators)
  bool _hasMarkdownTable(String text) {
    return text.contains('|') &&
        text.split('\n').any((l) => l.contains('|') && l.trim().startsWith('|'));
  }

  /// Render agent message — shows proper table for markdown tables,
  /// selectable text otherwise
  Widget _buildAgentMessageContent(String text, bool isUser) {
    if (!isUser && _hasMarkdownTable(text)) {
      return _renderMarkdownTable(text);
    }
    return SelectableText(
      text,
      style: TextStyle(
        color: isUser ? Colors.white : Colors.white.withAlpha(230),
        fontSize: 13,
        height: 1.45,
      ),
    );
  }

  /// Parse and render a markdown table as a real Flutter table
  Widget _renderMarkdownTable(String text) {
    final lines = text.split('\n');
    final tableLines = <String>[];
    final beforeLines = <String>[];
    final afterLines = <String>[];
    bool inTable = false;
    bool pastTable = false;
    for (final line in lines) {
      final isTableRow = line.trim().startsWith('|');
      if (isTableRow && !pastTable) {
        inTable = true;
        // Skip separator lines (---|---)
        if (!RegExp(r'^\|[-:\s|]+\|$').hasMatch(line.trim())) {
          tableLines.add(line);
        }
      } else if (inTable && !isTableRow) {
        pastTable = true;
        inTable = false;
        afterLines.add(line);
      } else if (!inTable) {
        beforeLines.add(line);
      } else {
        afterLines.add(line);
      }
    }

    final cells = tableLines.map((row) {
      return row.split('|')
          .map((c) => c.trim())
          .where((c) => c.isNotEmpty)
          .toList();
    }).toList();

    if (cells.isEmpty) {
      return SelectableText(text, style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.45));
    }

    final header = cells.first;
    final rows = cells.skip(1).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (beforeLines.any((l) => l.trim().isNotEmpty))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SelectableText(
              beforeLines.join('\n').trim(),
              style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.45),
            ),
          ),
        // Table
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Table(
            defaultColumnWidth: const IntrinsicColumnWidth(),
            border: TableBorder.all(color: Colors.white12, width: 0.5),
            children: [
              // Header row
              TableRow(
                decoration: BoxDecoration(color: Colors.white.withAlpha(20)),
                children: header.map((h) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Text(h,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                )).toList(),
              ),
              // Data rows
              ...rows.map((row) => TableRow(
                children: List.generate(header.length, (ci) {
                  final cell = ci < row.length ? row[ci] : '';
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    child: Text(cell,
                      style: TextStyle(
                        color: Colors.white.withAlpha(200),
                        fontSize: 12,
                      ),
                    ),
                  );
                }),
              )),
            ],
          ),
        ),
        if (afterLines.any((l) => l.trim().isNotEmpty))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SelectableText(
              afterLines.join('\n').trim(),
              style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.45),
            ),
          ),
      ],
    );
  }

  /// Copy text to clipboard and show a brief snackbar
  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Copied: ${text.length > 40 ? text.substring(0, 40) : text}…'),
          duration: const Duration(seconds: 2),
          backgroundColor: const Color(0xFF1A1A3E),
        ),
      );
    }
  }


  // ─────────────────────────────────────────────────────────────────────────
  // JARVIS Web Agent — Parallel Multi-Tab ReAct System
  // ─────────────────────────────────────────────────────────────────────────

  /// Split a query into parallel subtasks when the user lists multiple goals.
  /// e.g. "compare S24FE on flipkart and amazon and give me ratings"
  /// → ["compare S24FE on flipkart", "compare S24FE on amazon"]
  List<String> _parseSubtasks(String query) {
    // AI will handle complex decomposition; here we do quick heuristic split
    final patterns = [
      RegExp(r'\band\s+(?:also\s+)?(?:on|in|from|check|compare|open|go to|visit|search)\b', caseSensitive: false),
      RegExp(r'\n[-•\*]\s+'),
    ];
    for (final p in patterns) {
      if (p.hasMatch(query)) {
        final parts = query.split(p).map((s) => s.trim()).where((s) => s.length > 5).toList();
        if (parts.length >= 2) return parts;
      }
    }
    return [query];
  }

  // ── Entry point called from the UI send button ────────────────────────────
  Future<void> _runAgent() async {
    final command = _agentController.text.trim();
    if (command.isEmpty) return;

    setState(() {
      _agentMessages.add(AgentMessage(command, isUser: true));
      _agentRunning = true;
      _agentStatus = '🤖 JARVIS analyzing task...';
    });
    _agentController.clear();
    final subtasks = _parseSubtasks(command);

    try {
      if (subtasks.length > 1) {
        // ── PARALLEL multi-tab mode ──────────────────────────────────────
        setState(() => _agentStatus = '⚡ Launching ${subtasks.length} parallel tasks...');

        // Ensure enough tabs exist
        while (_tabs.length < subtasks.length) {
          _addNewTab('https://www.google.com', 'Working...');
          await Future.delayed(const Duration(milliseconds: 200));
        }

        // Show which tab is doing what
        for (int i = 0; i < subtasks.length; i++) {
          setState(() {
            _tabs[i].title = 'Task ${i + 1}';
            _agentMessages.add(AgentMessage(
              '🗂 Tab ${i + 1}: ${subtasks[i]}',
              isUser: false,
            ));
          });
        }

        // Run all agents concurrently
        final futures = <Future<String>>[];
        for (int i = 0; i < subtasks.length; i++) {
          futures.add(_runAgentOnTab(_tabs[i], subtasks[i], taskIndex: i + 1));
        }

        final results = await Future.wait(futures);

        if (mounted) {
          setState(() {
            _agentRunning = false;
            _agentStatus = '';
            final summary = results.asMap().entries
                .map((e) => '📌 Task ${e.key + 1}: ${e.value}')
                .join('\n\n');
            _agentMessages.add(AgentMessage(
              '✅ All ${subtasks.length} tasks completed!\n\n$summary',
              isUser: false,
            ));
          });
        }
      } else {
        // ── SINGLE task on current tab ───────────────────────────────────
        await _runAgentOnTab(_currentTab, command);
        if (mounted) {
          setState(() {
            _agentRunning = false;
            _agentStatus = '';
          });
        }
        // result message already added inside _runAgentOnTab
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _agentRunning = false;
          _agentStatus = '';
          _agentMessages.add(AgentMessage('⚠️ Agent error: $e', isUser: false));
        });
      }
    }
  }

  // ── Core single-tab ReAct loop — OpenClaw-style snapshot+ref system ─────────
  Future<String> _runAgentOnTab(
    BrowserTab tab,
    String command, {
    int taskIndex = 0,
  }) async {
    final router = context.read<AIRouter>();
    final List<Map<String, String>> history = [];
    int step = 0;
    int consecutiveErrors = 0;
    final Set<String> visitedUrls = {};

    // ── SOUL: build persistent context assembly (OpenClaw style) ──────────────
    // Extracts the target site domain so JARVIS can fetch site-specific hints.
    String siteKnowledge = '';
    final siteMatch = RegExp(
      r'(?:on|from|at|via|using|in|open)?\s*([a-zA-Z0-9-]+\.(?:com|in|org|net|io|co\.in)[^\s]*)',
      caseSensitive: false,
    ).firstMatch(command);
    if (siteMatch != null) {
      final site = siteMatch.group(1)!.trim();
      final label = taskIndex > 0 ? '[Task $taskIndex] ' : '';
      if (mounted) setState(() => _agentStatus = '${label}🔍 Learning $site...');
      try {
        final hint = await router.generateDirectResponse(
          prompt: 'Task: "$command" on $site.\n'
              'Give 4 bullet points MAX:\n'
              '• Exact URL to navigate to first\n'
              '• Search box: what to type and its label/placeholder\n'
              '• Which button/link to click for results\n'
              '• Where the download/buy/final action button appears\n'
              'Be extremely concise. Real site knowledge only.',
          systemOverride: 'You are a web automation expert. Output 4 bullets, 80 words max. No fluff.',
        );
        siteKnowledge = hint.trim();
      } catch (_) {}
    }

    try {
      while (true) {
        if (!mounted) break;
        step++;
        final label = taskIndex > 0 ? '[T$taskIndex] ' : '';

        // ── OBSERVE — OpenClaw-style accessibility snapshot with numbered refs ──
        if (mounted) setState(() => _agentStatus = '${label}👁 Step $step: Snapshot...');

        final snapshotRaw = await tab.controller?.evaluateJavascript(source: r'''
(function(){
  try {
    var url = window.location.href;
    var title = document.title;
    var readyState = document.readyState;

    // Build ARIA/accessibility snapshot with numbered refs — OpenClaw style
    // Ref numbers let the AI say "click ref:5" instead of fragile selectors
    var SEL = 'a[href],button:not([disabled]),input:not([type="hidden"]),select,textarea,[role="button"],[role="link"],[role="tab"],[role="menuitem"],label[for]';
    var nodes = document.querySelectorAll(SEL);
    var refs = [];
    var dlLinks = [];

    for (var i = 0; i < Math.min(nodes.length, 80); i++) {
      var el = nodes[i];
      var tag = el.tagName.toLowerCase();
      var type = el.type || '';
      var role = el.getAttribute('role') || '';
      var label = (
        el.getAttribute('aria-label') ||
        el.getAttribute('placeholder') ||
        el.getAttribute('title') ||
        el.innerText ||
        el.value ||
        el.getAttribute('alt') ||
        el.getAttribute('name') ||
        el.getAttribute('href') || ''
      ).trim().replace(/\s+/g,' ').slice(0,70);
      var href = (el.href || el.src || el.getAttribute('href') || '').slice(0,150);
      var isInput = tag === 'input' || tag === 'textarea' || tag === 'select';
      var entry = i + ': [' + (role||tag) + (type?('/'+type):'') + '] ' + JSON.stringify(label);
      if (href && tag === 'a') entry += ' -> ' + href;
      refs.push(entry);

      // Capture direct file download links
      if (href && /\.(mkv|mp4|avi|zip|rar|apk|torrent|mp3|flac|m4a|wav|opus|mov|webm|pdf|docx?)(\?|#|$)/i.test(href)) {
        dlLinks.push({ref:i, label:label.slice(0,40), href:href});
      }
    }

    // Scan all anchors for download-cue text even if not in refs
    var allA = document.querySelectorAll('a');
    for (var j = 0; j < allA.length && dlLinks.length < 20; j++) {
      var a = allA[j];
      var aHref = a.href || '';
      var aText = (a.innerText || '').trim().toLowerCase();
      if (aHref && /download|direct.?link|get.?file|direct.?download|play.?now|fast.?link|zippy|gdrive/i.test(aText)) {
        dlLinks.push({ref:-1, label:aText.slice(0,40), href:aHref.slice(0,200)});
      }
    }

    // Page text summary (first 800 chars)
    var bodyText = (document.body ? document.body.innerText : '').replace(/\s+/g,' ').trim().slice(0,800);

    // Detect forms
    var forms = [];
    document.querySelectorAll('form').forEach(function(f, fi) {
      var inputs = [];
      f.querySelectorAll('input,textarea,select').forEach(function(inp) {
        inputs.push((inp.getAttribute('placeholder')||inp.name||inp.type||'?').slice(0,30));
      });
      forms.push('form' + fi + ': [' + inputs.join(', ') + ']');
    });

    return JSON.stringify({
      url: url,
      title: title,
      readyState: readyState,
      refs: refs,
      dlLinks: dlLinks,
      forms: forms,
      text: bodyText
    });
  } catch(e) {
    return JSON.stringify({url: window.location.href, error: e.message, readyState:'unknown'});
  }
})()
''');

        final snapshot = snapshotRaw?.toString() ?? '{}';

        // Rolling history — keep last 12 entries
        history.add({'role': 'obs', 'content': 'STEP $step\n$snapshot'});
        if (history.length > 12) history.removeAt(0);

        // ── Proactive download detection hint ─────────────────────────────
        try {
          final parsed = snapshot.contains('"dlLinks":[{') ||
              (snapshot.contains('"dlLinks"') &&
               snapshot.contains('"href"') &&
               snapshot.contains('http'));
          if (parsed && step > 1) {
            history.add({
              'role': 'JARVIS-hint',
              'content': '🔗 Download links found in snapshot dlLinks. '
                  'If the target file is there, use DOWNLOAD action NOW — do not browse further.',
            });
          }
        } catch (_) {}

        // ── REASON — OpenClaw-style context assembly ───────────────────────
        if (mounted) setState(() => _agentStatus = '${label}🧠 Step $step: Reasoning...');

        final historyText = history
            .map((h) => '[${h["role"]!.toUpperCase()}]\n${h["content"]}')
            .join('\n\n');

        // SOUL prompt — persistent context like OpenClaw's SOUL.md + MEMORY.md
        final aiResponse = await router.generateDirectResponse(
          prompt: '''
━━━━━━━━━━ JARVIS SOUL ━━━━━━━━━━
You are JARVIS Web Agent — operate at 3x human speed, autonomous, never give up.
You have full browser control via snapshot REFS (numbered interactive elements).
You know how to handle: logins, CAPTCHAs, dynamic JS sites, forms, downloads.

━━━━━━━━━━ TASK MEMORY ━━━━━━━━━━
GOAL: "$command"

SITE KNOWLEDGE (pre-researched):
${siteKnowledge.isNotEmpty ? siteKnowledge : "none — navigate instinctively"}

━━━━━━━━━━ CONVERSATION LOOP ━━━━━━━━━━
$historyText

━━━━━━━━━━ ACTION SCHEMA ━━━━━━━━━━
Respond ONLY with raw JSON (no markdown, no explanation):
{
  "thought": "brief one-line plan",
  "type": "NAVIGATE | CLICK | TYPE | SCROLL | DOWNLOAD | DONE | ANSWER | WAIT",
  "ref": 12,
  "value": "text to type (TYPE only)",
  "navigate_url": "full URL (NAVIGATE only)",
  "download_url": "direct file URL (DOWNLOAD only)",
  "filename": "file.ext (DOWNLOAD only)",
  "answer": "final result text (DONE/ANSWER only)"
}

━━━━━━━━━━ AGENT RULES ━━━━━━━━━━
• NAVIGATE: jump directly to the exact URL — never use a search engine to find a URL you already know
• CLICK: use ref number from snapshot (e.g. ref:7 means click 7th element in refs list)
• TYPE: type value into input field at ref number — always CLICK the field ref first if not focused
• SCROLL: scroll down to expose more content when needed
• DOWNLOAD: use exact URL from dlLinks — triggers device download manager immediately
• DONE: task complete — write a clean, human-readable summary with all results
• WAIT: page still loading — wait for readyState=complete
• SELF-CORRECT: if same action fails twice, try a completely different approach
• FORMS: for Google/search: CLICK search box ref → TYPE query → CLICK search button ref
• PIRACY SITES: search title → click movie card → find download section → DOWNLOAD
• Never revisit a URL that was already visited: ${visitedUrls.join(", ")}
• Complete ANY task — never stop unless DONE''',
          systemOverride:
              'You are JARVIS, an autonomous web agent. Output ONLY raw JSON. No markdown. No commentary.',
        );

        // ── PARSE ──────────────────────────────────────────────────────────
        String thought = '';
        String actionType = 'WAIT';
        int ref = -1;
        String value = '';
        String navigateUrl = '';
        String downloadUrl = '';
        String filename = '';
        String answer = '';

        try {
          String cleaned = aiResponse.trim();
          // Strip any markdown fences
          if (cleaned.contains('```')) {
            final m = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(cleaned);
            if (m != null) cleaned = m.group(1)!;
          }
          final jsonMatch = RegExp(r'\{[\s\S]*?\}').firstMatch(cleaned);
          if (jsonMatch != null) {
            final d = jsonMatch.group(0)!;
            thought      = RegExp(r'"thought"\s*:\s*"((?:[^"\\]|\\.)*)"').firstMatch(d)?.group(1) ?? '';
            actionType   = (RegExp(r'"type"\s*:\s*"([^"]*)"').firstMatch(d)?.group(1) ?? 'WAIT').toUpperCase().trim();
            final refStr = RegExp(r'"ref"\s*:\s*(\d+)').firstMatch(d)?.group(1);
            ref          = refStr != null ? int.tryParse(refStr) ?? -1 : -1;
            value        = RegExp(r'"value"\s*:\s*"((?:[^"\\]|\\.)*)"').firstMatch(d)?.group(1) ?? '';
            navigateUrl  = RegExp(r'"navigate_url"\s*:\s*"([^"]*)"').firstMatch(d)?.group(1) ?? '';
            downloadUrl  = RegExp(r'"download_url"\s*:\s*"([^"]*)"').firstMatch(d)?.group(1) ?? '';
            filename     = RegExp(r'"filename"\s*:\s*"([^"]*)"').firstMatch(d)?.group(1) ?? '';
            answer       = RegExp(r'"answer"\s*:\s*"((?:[^"\\]|\\.)*)"').firstMatch(d)?.group(1) ?? '';
            value        = value.replaceAll(r'\"', '"').replaceAll(r'\n', '\n');
            answer       = answer.replaceAll(r'\n', '\n').replaceAll(r'\"', '"');
            consecutiveErrors = 0;
          } else {
            throw Exception('No JSON in response');
          }
        } catch (_) {
          consecutiveErrors++;
          history.add({'role': 'error', 'content': 'Parse fail #$consecutiveErrors — retrying'});
          await _pollPageReady(tab, maxWait: 400);
          continue; // never stop — self-correct
        }

        history.add({'role': 'thought', 'content': '[$actionType ref:$ref] $thought'});

        // ── ACT ────────────────────────────────────────────────────────────

        // DONE / ANSWER
        if (actionType == 'DONE' || actionType == 'ANSWER') {
          final raw = answer.isNotEmpty ? answer : thought;
          final clean = _cleanAgentText(raw);
          final prefix = taskIndex > 0 ? '[Task $taskIndex] ' : '';
          final msg = '${prefix}✅ Done in $step step${step == 1 ? "" : "s"}!\n\n$clean';
          if (mounted) setState(() => _agentMessages.add(AgentMessage(msg, isUser: false)));
          return clean;
        }

        // WAIT
        if (actionType == 'WAIT') {
          if (mounted) setState(() => _agentStatus = '${label}⏳ Step $step: Waiting for page...');
          await _pollPageReady(tab, maxWait: 5000);
          history.add({'role': 'action', 'content': 'Waited for page ready'});
          continue;
        }

        // NAVIGATE
        if (actionType == 'NAVIGATE' && navigateUrl.isNotEmpty) {
          final fullUrl = navigateUrl.startsWith('http') ? navigateUrl : 'https://$navigateUrl';
          if (visitedUrls.contains(fullUrl)) {
            // Don't revisit — push hint and continue reasoning
            history.add({'role': 'JARVIS-hint', 'content': 'Already visited $fullUrl — try a different approach'});
            continue;
          }
          visitedUrls.add(fullUrl);
          final shortUrl = fullUrl.length > 50 ? '${fullUrl.substring(0, 50)}…' : fullUrl;
          if (mounted) setState(() => _agentStatus = '${label}🌐 Step $step: → $shortUrl');
          await tab.controller?.loadUrl(urlRequest: URLRequest(url: WebUri(fullUrl)));
          await _pollPageReady(tab, maxWait: 7000);
          history.add({'role': 'action', 'content': 'Navigated → $fullUrl'});
          continue;
        }

        // DOWNLOAD
        if (actionType == 'DOWNLOAD' && downloadUrl.isNotEmpty) {
          if (mounted) {
            setState(() => _agentStatus = '${label}⬇ Step $step: Downloading...');
            String cookiesString = '';
            try {
              final cookies = await CookieManager.instance().getCookies(url: WebUri(downloadUrl));
              cookiesString = cookies.map((c) => '${c.name}=${c.value}').join('; ');
            } catch (_) {}
            BrowserDownloadManager.addDownload(
              downloadUrl,
              filename.isNotEmpty ? filename : '',
              cookies: cookiesString,
              referer: tab.url.isNotEmpty ? tab.url : null,
            );
            BrowserDownloadManager.show(context);
            final dn = filename.isNotEmpty ? filename : downloadUrl.split('/').last;
            setState(() => _agentMessages.add(AgentMessage(
              '${label}⬇ Downloading: $dn\n↳ Sent to Download Manager',
              isUser: false,
            )));
          }
          history.add({'role': 'action', 'content': 'DOWNLOAD triggered: $downloadUrl'});
          await Future.delayed(const Duration(milliseconds: 200));
          continue;
        }

        // CLICK — find element by ref number and click it
        if (actionType == 'CLICK' && ref >= 0) {
          if (mounted) setState(() => _agentStatus = '${label}👆 Step $step: Click ref:$ref...');

          // Inject interceptor + click the ref element
          await tab.controller?.evaluateJavascript(source: '''
(function(){
  if (!window.__jarvisPatched) {
    window.__jarvisPatched = true;
    document.addEventListener("click", function(e) {
      var a = e.target.closest("a[href]");
      if (!a) return;
      var href = a.href || "";
      if (/\\.(mkv|mp4|avi|zip|rar|apk|torrent|mp3|flac|m4a|wav|opus|mov|webm|pdf|docx?)(\\?|#|\$)/i.test(href)) {
        e.preventDefault();
        e.stopPropagation();
        window.__jarvisDlUrl = href;
        window.__jarvisDlName = a.download || href.split("/").pop() || "";
      }
    }, true);
  }
})();
''');
          final clickResult = await tab.controller?.evaluateJavascript(source: '''
(function(){
  try {
    var SEL = 'a[href],button:not([disabled]),input:not([type="hidden"]),select,textarea,[role="button"],[role="link"],[role="tab"],[role="menuitem"],label[for]';
    var el = document.querySelectorAll(SEL)[${ref}];
    if (!el) return "ERROR: ref ${ref} not found";
    el.focus();
    el.click();
    return "CLICKED: " + (el.innerText||el.value||el.getAttribute("aria-label")||"?").trim().slice(0,40);
  } catch(e) { return "ERROR: " + e.message; }
})()
''');

          // Check for intercepted download
          final intercepted = await tab.controller?.evaluateJavascript(
              source: 'window.__jarvisDlUrl || ""');
          final dlUrl = intercepted?.toString().replaceAll('"', '').trim() ?? '';
          if (dlUrl.isNotEmpty) {
            await tab.controller?.evaluateJavascript(
                source: 'window.__jarvisDlUrl=null; window.__jarvisPatched=false;');
            final dlNameRaw = await tab.controller?.evaluateJavascript(
                source: 'window.__jarvisDlName || ""');
            final dlName = dlNameRaw?.toString().replaceAll('"', '') ?? '';
            if (mounted) {
              String cookiesString = '';
              try {
                final cookies = await CookieManager.instance().getCookies(url: WebUri(dlUrl));
                cookiesString = cookies.map((c) => '${c.name}=${c.value}').join('; ');
              } catch (_) {}
              BrowserDownloadManager.addDownload(dlUrl, dlName,
                  cookies: cookiesString, referer: tab.url);
              BrowserDownloadManager.show(context);
              setState(() => _agentMessages.add(AgentMessage(
                  '${label}⬇ Download captured: ${dlName.isNotEmpty ? dlName : dlUrl.split("/").last}',
                  isUser: false)));
            }
            history.add({'role': 'action', 'content': 'Download intercepted: $dlUrl'});
            await Future.delayed(const Duration(milliseconds: 200));
            continue;
          }

          final clickStr = clickResult?.toString() ?? 'OK';
          history.add({'role': 'action', 'content': 'CLICK ref:$ref → $clickStr'});
          if (clickStr.startsWith('ERROR')) { consecutiveErrors++; } else { consecutiveErrors = 0; }
          await Future.delayed(const Duration(milliseconds: 200));
          await _pollPageReady(tab, maxWait: 3000);
          continue;
        }

        // TYPE — type text into an input field at ref
        if (actionType == 'TYPE') {
          if (mounted) setState(() => _agentStatus = '${label}⌨ Step $step: Type...');
          final safeValue = value.replaceAll('"', r'\"').replaceAll('\n', r'\n');
          final typeResult = await tab.controller?.evaluateJavascript(source: '''
(function(){
  try {
    var SEL = 'a[href],button:not([disabled]),input:not([type="hidden"]),select,textarea,[role="button"],[role="link"],[role="tab"],[role="menuitem"],label[for]';
    var el = document.querySelectorAll(SEL)[${ref >= 0 ? ref : 0}];
    if (!el) {
      el = document.querySelector('input[type="text"]:not([disabled]),input[type="search"]:not([disabled]),textarea:not([disabled])');
    }
    if (!el) return "ERROR: no input found";
    el.focus();
    var setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype,"value") && Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype,"value").set;
    if (setter) setter.call(el, "$safeValue"); else el.value = "$safeValue";
    el.dispatchEvent(new Event("input",{bubbles:true}));
    el.dispatchEvent(new Event("change",{bubbles:true}));
    return "TYPED into " + (el.getAttribute("placeholder")||el.name||"input");
  } catch(e) { return "ERROR: " + e.message; }
})()
''');
          final typeStr = typeResult?.toString() ?? 'OK';
          history.add({'role': 'action', 'content': 'TYPE "$value" ref:$ref → $typeStr'});
          if (typeStr.startsWith('ERROR')) { consecutiveErrors++; } else { consecutiveErrors = 0; }
          await Future.delayed(const Duration(milliseconds: 150));
          continue;
        }

        // SCROLL — scroll down to reveal more content
        if (actionType == 'SCROLL') {
          if (mounted) setState(() => _agentStatus = '${label}📜 Step $step: Scrolling...');
          await tab.controller?.evaluateJavascript(
              source: 'window.scrollBy(0, window.innerHeight * 0.8)');
          history.add({'role': 'action', 'content': 'Scrolled down'});
          await Future.delayed(const Duration(milliseconds: 300));
          continue;
        }

        // Unknown type — self-correct, never stop
        consecutiveErrors++;
        history.add({'role': 'error', 'content': 'Unknown type "$actionType" — retrying'});
        await Future.delayed(const Duration(milliseconds: 200));
      }
    } catch (e) {
      final msg = '⚠️ Agent error: $e';
      if (mounted) setState(() => _agentMessages.add(AgentMessage(msg, isUser: false)));
      return msg;
    }
    return 'Task completed.';
  }

  /// Smart page-ready poller — 200ms ticks (2x faster than before).
  /// Returns as soon as readyState == "complete" or maxWait ms elapse.
  Future<void> _pollPageReady(BrowserTab tab, {int maxWait = 5000}) async {
    final deadline = DateTime.now().add(Duration(milliseconds: maxWait));
    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 200));
      try {
        final r = await tab.controller?.evaluateJavascript(source: 'document.readyState');
        if (r?.toString().contains('complete') == true) return;
      } catch (_) {
        return; // WebView disposed — exit safely
      }
    }
  }



  // ─── Bottom JARVIS toolbar ──────────────────────────────────────────────────

  Widget _buildBottomBar(double bottomPad) {
    return Container(
      padding: EdgeInsets.only(
        left: 8,
        right: 8,
        top: 8,
        bottom: bottomPad > 0 ? bottomPad : 12,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF0A0A18),
        border: Border(
          top: BorderSide(color: Color(0xFF1A1A2E), width: 0.8),
        ),
      ),
      child: Row(
        children: [
          _NavBtn(
            icon: Icons.arrow_back_ios_new_rounded,
            enabled: _currentTab.canGoBack,
            onTap: () => _currentTab.controller?.goBack(),
          ),
          _NavBtn(
            icon: Icons.arrow_forward_ios_rounded,
            enabled: _currentTab.canGoForward,
            onTap: () => _currentTab.controller?.goForward(),
          ),
          _NavBtn(
            icon: Icons.filter_none,
            enabled: true,
            onTap: _showTabsMenu,
          ),

          const Spacer(),

          // ── JARVIS Agent trigger button ────────────────────────────────
          GestureDetector(
            onTap: () => setState(() => _agentPanelOpen = !_agentPanelOpen),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: _agentPanelOpen
                      ? [_primary, _secondary]
                      : [
                          _primary.withAlpha(46),
                          _secondary.withAlpha(30),
                        ],
                ),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: _primary.withAlpha(127),
                  width: 0.8,
                ),
                boxShadow: _agentPanelOpen
                    ? [
                        BoxShadow(
                          color: _primary.withAlpha(102),
                          blurRadius: 16,
                          spreadRadius: 1,
                        ),
                      ]
                    : [],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _agentPanelOpen
                          ? Colors.white
                          : const Color(0xFF22C55E),
                      boxShadow: [
                        BoxShadow(
                          color: (_agentPanelOpen
                                  ? Colors.white
                                  : const Color(0xFF22C55E))
                              .withAlpha(178),
                          blurRadius: 5,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 7),
                  ShaderMask(
                    shaderCallback: (b) => LinearGradient(
                      colors: _agentPanelOpen
                          ? [Colors.white, Colors.white]
                          : [_primary, _secondary],
                    ).createShader(b),
                    child: const Text(
                      'JARVIS',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const Spacer(),

          // ── Downloads button ──────────────────────────────────────────
          _NavBtn(
            icon: Icons.download_rounded,
            enabled: true,
            onTap: () => BrowserDownloadManager.show(context),
            color: Colors.white,
          ),

          _NavBtn(
            icon: Icons.keyboard_arrow_down_rounded,
            enabled: true,
            onTap: () => Navigator.of(context).pop(),
            color: Colors.white54,
          ),
        ],
      ),
    );
  }
}

// ── Small reusable widgets ────────────────────────────────────────────────────

class _NavBtn extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final Color? color;

  const _NavBtn({
    required this.icon,
    required this.enabled,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Icon(
            icon,
            size: 22,
            color: enabled ? (color ?? Colors.white70) : Colors.white24,
          ),
        ),
      ),
    );
  }
}

class _TopBarBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _TopBarBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 20, color: Colors.white70),
        ),
      ),
    );
  }
}


