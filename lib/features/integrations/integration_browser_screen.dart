import 'dart:async';
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
  static const _safedomains = [
    'google.com', 'google.co.in', 'google.',
    'gstatic.com', 'googleapis.com', 'youtube.com',
    'youtu.be', 'amazon.com', 'amazon.in',
    'flipkart.com', 'docs.google.com', 'forms.google.com',
    'accounts.google.com', 'cloudflare.com',
    'facebook.com', 'instagram.com', 'twitter.com',
    'whatsapp.com', 'microsoft.com', 'apple.com',
    'github.com', 'stackoverflow.com',
  ];

  bool _isAd(String url) {
    if (!BrowserDownloadManager.globalState.isAdBlockEnabled) return false;
    if (url.isEmpty) return false;
    final lowerUrl = url.toLowerCase();

    // Always allow safe domains
    if (_safedomains.any((d) => lowerUrl.contains(d))) return false;

    // Check explicit ad-block domains list
    if (BrowserAdBlockRules.adBlockDomains.any((d) => lowerUrl.contains(d))) return true;

    // Only block clear betting/scam patterns
    if (lowerUrl.contains('funinr.com') || lowerUrl.contains('casino')) return true;

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

      // ── Long-press: image / link context menu ─────────────────────────────
      onLongPressHitTestResult: (controller, hitTestResult) async {
        final extra = hitTestResult.extra ?? '';
        final type = hitTestResult.type;

        // Image or image-inside-anchor → offer save
        if (type == InAppWebViewHitTestResultType.IMAGE_TYPE ||
            type == InAppWebViewHitTestResultType.SRC_IMAGE_ANCHOR_TYPE) {
          if (!mounted) return;
          final imgUrl = extra;
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
                    leading:
                        const Icon(Icons.download, color: Colors.blueAccent),
                    title: const Text('Save Image',
                        style: TextStyle(color: Colors.white)),
                    subtitle: Text(
                      imgUrl.length > 60
                          ? '...${imgUrl.substring(imgUrl.length - 60)}'
                          : imgUrl,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 11),
                      maxLines: 1,
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      BrowserDownloadManager.addDownload(
                        imgUrl,
                        '',
                        referer: _currentTab.url,
                      );
                      BrowserDownloadManager.show(context);
                    },
                  ),
                  ListTile(
                    leading:
                        const Icon(Icons.open_in_browser, color: Colors.white54),
                    title: const Text('Open in New Tab',
                        style: TextStyle(color: Colors.white)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _addNewTab(imgUrl, imgUrl);
                    },
                  ),
                ],
              ),
            ),
          );
          return;
        }

        // SRC anchor (hyperlink) → offer open / download
        if ((type == InAppWebViewHitTestResultType.SRC_ANCHOR_TYPE ||
                type ==
                    InAppWebViewHitTestResultType.SRC_IMAGE_ANCHOR_TYPE) &&
            extra.isNotEmpty) {
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
                    leading:
                        const Icon(Icons.download, color: Colors.blueAccent),
                    title: const Text('Download Link',
                        style: TextStyle(color: Colors.white)),
                    onTap: () {
                      Navigator.pop(ctx);
                      BrowserDownloadManager.addDownload(
                        extra,
                        '',
                        referer: _currentTab.url,
                      );
                      BrowserDownloadManager.show(context);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.open_in_new,
                        color: Colors.white54),
                    title: const Text('Open in New Tab',
                        style: TextStyle(color: Colors.white)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _addNewTab(extra, extra);
                    },
                  ),
                ],
              ),
            ),
          );
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
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  reverse: false,
                  itemCount: _agentMessages.length,
                  itemBuilder: (ctx, i) {
                    final msg = _agentMessages[i];
                    return Align(
                      alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
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
                        child: SelectableText(
                          msg.text,
                          style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
                        ),
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

  /// Strip markdown/symbols from AI response text for clean display
  String _cleanAgentText(String text) {
    return text
        .replaceAll(RegExp(r'\*\*([^*]+)\*\*'), r'$1')   // bold
        .replaceAll(RegExp(r'\*([^*]+)\*'), r'$1')        // italic
        .replaceAll(RegExp(r'#+\s*'), '')                   // headings
        .replaceAll(RegExp(r'`{1,3}[^`]*`{1,3}'), '')     // code
        .replaceAll(RegExp(r'^[-*]\s+', multiLine: true), '• ')  // bullet
        .replaceAll(RegExp(r'\\n'), '\n')                 // literal \n
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')            // excess newlines
        .trim();
  }

  Future<void> _runAgent() async {
    final command = _agentController.text.trim();
    if (command.isEmpty) return;

    setState(() {
      _agentMessages.add(AgentMessage(command, isUser: true));
      _agentRunning = true;
      _agentStatus = '🤖 JARVIS starting...';
    });
    _agentController.clear();

    final router = context.read<AIRouter>();
    // Keep only last 8 entries in history to avoid context explosion
    final List<Map<String, String>> history = [];
    int step = 0;
    int consecutiveErrors = 0;

    try {
      while (true) {
        if (!mounted) break;
        step++;

        // ── OBSERVE ──────────────────────────────────────────────────────
        setState(() => _agentStatus = '👁 Step $step: Reading page...');
        final pageDataRaw = await _currentTab.controller?.evaluateJavascript(source: r'''
          (function(){
            try {
              const elems = document.querySelectorAll('a,button,input,select,textarea,[role="button"],[role="link"]');
              let elemList = '';
              for(let i=0; i<Math.min(elems.length,80); i++){
                const el = elems[i];
                const txt = (el.innerText||el.placeholder||el.value||el.name||el.getAttribute('aria-label')||el.title||'').trim().slice(0,100);
                const tag = el.tagName + (el.type?'['+el.type+']':'');
                const id = el.id?'#'+el.id:'';
                if(txt||id) elemList += i+': '+tag+id+'="'+txt+'"\n';
              }
              return JSON.stringify({
                url: window.location.href,
                title: document.title,
                text: (document.body?.innerText||'').substring(0,2000),
                elements: elemList,
                readyState: document.readyState
              });
            } catch(e){ return JSON.stringify({url:window.location.href, error: e.message}); }
          })()
        ''');

        final pageData = pageDataRaw?.toString() ?? '{}';
        // Add observation, cap history at 8 entries
        history.add({'role': 'observation', 'content': 'Step $step:\n$pageData'});
        if (history.length > 8) history.removeAt(0);

        // ── REASON ──────────────────────────────────────────────────────
        setState(() => _agentStatus = '🧠 Step $step: Thinking...');

        final historyText = history.map((h) => '[${h['role']!.toUpperCase()}]\n${h['content']}').join('\n\n');

        final aiResponse = await router.generateDirectResponse(
          prompt: '''TASK: "$command"

HISTORY (recent):
$historyText

Decide the NEXT single action. Reply ONLY valid JSON, no markdown:
{
  "thought": "brief observation and plan",
  "type": "ACTION|NAVIGATE|DONE|ANSWER|WAIT",
  "js": "JS code string (only for ACTION)",
  "navigate_url": "full URL (only for NAVIGATE)",
  "answer": "plain text reply (only for DONE/ANSWER)"
}

RULES:
- ACTION: run JavaScript on current page (click, type, scroll, extract)
- NAVIGATE: go to a URL (use this to open new pages, follow links)
- DONE: task fully complete - summarize what was achieved
- ANSWER: user asked a question - answer it directly
- WAIT: page still loading, wait for it
- For form inputs: find the input, set .value="text", dispatch input+change events, then click submit
- For clicks: use element.click() or find by text content
- Keep trying different approaches if something fails
- When you see a CAPTCHA or login wall, describe it in your answer''',
          systemOverride: 'You are JARVIS Web Agent. Output ONLY raw JSON, no markdown, no explanation outside JSON.',
        );

        // ── PARSE ────────────────────────────────────────────────────────
        String thought = '';
        String actionType = 'DONE';
        String jsCode = '';
        String navigateUrl = '';
        String answer = '';

        try {
          String cleaned = aiResponse.trim();
          // Strip markdown fences
          if (cleaned.contains('```')) {
            final m = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(cleaned);
            if (m != null) cleaned = m.group(1)!;
          }
          final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(cleaned);
          if (jsonMatch != null) {
            final d = jsonMatch.group(0)!;
            thought      = RegExp(r'"thought"\s*:\s*"((?:[^"\\]|\\.)*)"').firstMatch(d)?.group(1) ?? '';
            actionType   = (RegExp(r'"type"\s*:\s*"([^"]*)"').firstMatch(d)?.group(1) ?? 'DONE').toUpperCase().trim();
            jsCode       = RegExp(r'"js"\s*:\s*"((?:[^"\\]|\\.)*)"').firstMatch(d)?.group(1) ?? '';
            navigateUrl  = RegExp(r'"navigate_url"\s*:\s*"([^"]*)"').firstMatch(d)?.group(1) ?? '';
            answer       = RegExp(r'"answer"\s*:\s*"((?:[^"\\]|\\.)*)"').firstMatch(d)?.group(1) ?? '';
            // Unescape JS string escapes
            jsCode = jsCode.replaceAll(r'\"', '"').replaceAll(r'\n', '\n').replaceAll(r'\t', '\t').replaceAll(r'\\', '\\');
            answer = answer.replaceAll(r'\n', '\n').replaceAll(r'\"', '"');
          } else {
            throw Exception('No JSON found');
          }
          consecutiveErrors = 0;
        } catch (_) {
          consecutiveErrors++;
          if (consecutiveErrors >= 4) {
            setState(() {
              _agentRunning = false;
              _agentStatus = '';
              _agentMessages.add(AgentMessage(
                '⚠️ Could not parse AI response after $consecutiveErrors attempts. Task stopped.',
                isUser: false,
              ));
            });
            return;
          }
          history.add({'role': 'error', 'content': 'Parse failed, retry $consecutiveErrors'});
          await Future.delayed(const Duration(milliseconds: 800));
          continue;
        }

        history.add({'role': 'thought', 'content': thought});

        // ── ACT ──────────────────────────────────────────────────────────
        if (actionType == 'DONE' || actionType == 'ANSWER') {
          final raw = answer.isNotEmpty ? answer : thought;
          final clean = _cleanAgentText(raw);
          setState(() {
            _agentRunning = false;
            _agentStatus = '';
            _agentMessages.add(AgentMessage(
              '✅ Done in $step step${step == 1 ? '' : 's'}!\n\n$clean',
              isUser: false,
            ));
          });
          return;
        }

        if (actionType == 'WAIT') {
          setState(() => _agentStatus = '⏳ Step $step: Waiting for page...');
          await Future.delayed(const Duration(seconds: 3));
          history.add({'role': 'action', 'content': 'Waited 3 seconds'});
          continue;
        }

        if (actionType == 'NAVIGATE' && navigateUrl.isNotEmpty) {
          setState(() => _agentStatus = '🌐 Step $step: Navigating...');
          final fullUrl = navigateUrl.startsWith('http') ? navigateUrl : 'https://$navigateUrl';
          await _currentTab.controller?.loadUrl(
            urlRequest: URLRequest(url: WebUri(fullUrl)),
          );
          if (mounted) setState(() => _agentStatus = '⏳ Loading...');
          await Future.delayed(const Duration(seconds: 4));
          history.add({'role': 'action', 'content': 'Navigated to $fullUrl'});
          continue;
        }

        if (actionType == 'ACTION' && jsCode.isNotEmpty) {
          setState(() => _agentStatus = '🚀 Step $step: Acting...');
          final resultRaw = await _currentTab.controller?.evaluateJavascript(
            source: '(function(){try{$jsCode;return "OK";}catch(e){return "ERROR: "+e.message;}})()',
          );
          final result = resultRaw?.toString() ?? 'OK';
          history.add({'role': 'action', 'content': 'JS result: $result'});
          if (result.startsWith('ERROR')) {
            consecutiveErrors++;
          } else {
            consecutiveErrors = 0;
          }
          await Future.delayed(const Duration(milliseconds: 1200));
          continue;
        }

        // Unknown type — treat as done
        setState(() {
          _agentRunning = false;
          _agentStatus = '';
          _agentMessages.add(AgentMessage(
            _cleanAgentText(answer.isNotEmpty ? answer : thought),
            isUser: false,
          ));
        });
        return;
      }
    } catch (e) {
      setState(() {
        _agentRunning = false;
        _agentStatus = '';
        _agentMessages.add(AgentMessage('⚠️ Agent error: $e', isUser: false));
      });
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
