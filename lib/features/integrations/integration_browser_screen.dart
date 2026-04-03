import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import '../../core/router/ai_router.dart';
import 'integrations_model.dart';


class IntegrationBrowserScreen extends StatefulWidget {
  final AIIntegration integration;
  const IntegrationBrowserScreen({super.key, required this.integration});

  @override
  State<IntegrationBrowserScreen> createState() =>
      _IntegrationBrowserScreenState();
}

class _IntegrationBrowserScreenState extends State<IntegrationBrowserScreen>
    with SingleTickerProviderStateMixin {
  InAppWebViewController? _webViewController;
  double _progress = 0;
  bool _isLoading = true;
  String _currentUrl = '';
  bool _canGoBack = false;
  bool _canGoForward = false;

  // Agent panel
  bool _agentPanelOpen = false;
  final _agentController = TextEditingController();
  bool _agentRunning = false;
  String _agentStatus = '';
  late AnimationController _agentAnim;

  Color get _primary => Color(widget.integration.gradientColors[0]);
  Color get _secondary => Color(widget.integration.gradientColors[1]);

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.integration.url;
    _agentAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
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
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: const Color(0xFF07070F),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildTopBar(),
            if (_isLoading)
              LinearProgressIndicator(
                value: _progress == 0 ? null : _progress,
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation(_primary),
                minHeight: 2,
              )
            else
              const SizedBox(height: 2),

            // ── WebView ───────────────────────────────────────────────────
            Expanded(
              child: Stack(
                children: [
                  InAppWebView(
                    initialUrlRequest:
                        URLRequest(url: WebUri(widget.integration.url)),
                    initialSettings: InAppWebViewSettings(
                      javaScriptEnabled: true,
                      domStorageEnabled: true,
                      databaseEnabled: true,
                      allowsInlineMediaPlayback: true,
                      mediaPlaybackRequiresUserGesture: false,
                      useWideViewPort: true,
                      // ── sessionStorage / OAuth fix ──────────────────────
                      thirdPartyCookiesEnabled: true,
                      sharedCookiesEnabled: true,
                      javaScriptCanOpenWindowsAutomatically: true,
                      supportMultipleWindows: true,
                      cacheEnabled: true,
                      // Full desktop-grade UA so sites behave correctly
                      userAgent:
                          'Mozilla/5.0 (Linux; Android 14; Pixel 8) '
                          'AppleWebKit/537.36 (KHTML, like Gecko) '
                          'Chrome/124.0.6367.82 Mobile Safari/537.36',
                    ),
                    onWebViewCreated: (c) => _webViewController = c,
                    onLoadStart: (c, url) => setState(() {
                      _isLoading = true;
                      _currentUrl = url?.toString() ?? '';
                    }),
                    onProgressChanged: (c, p) =>
                        setState(() => _progress = p / 100),
                    onLoadStop: (c, url) async {
                      setState(() {
                        _isLoading = false;
                        _currentUrl = url?.toString() ?? '';
                      });
                      _canGoBack = await c.canGoBack();
                      _canGoForward = await c.canGoForward();
                      if (mounted) setState(() {});
                    },
                    // Handle OAuth popup windows inside same view
                    onCreateWindow: (c, req) async {
                      if (req.request.url != null) {
                        await c.loadUrl(
                          urlRequest: URLRequest(url: req.request.url),
                        );
                      }
                      return true;
                    },
                  ),

                  // ── JARVIS Agent panel (slides up) ────────────────────
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
    final displayUrl = _currentUrl.isEmpty
        ? widget.integration.url
        : _currentUrl
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
            _primary.withValues(alpha: 0.06),
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
                _primary.withValues(alpha: 0.15),
                _secondary.withValues(alpha: 0.1),
              ]),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _primary.withValues(alpha: 0.25)),
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

          // URL pill — feels like a real browser address bar
          Expanded(
            child: GestureDetector(
              onTap: _showAddressBarInput,
              child: Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lock_rounded,
                        size: 10, color: _primary.withValues(alpha: 0.7)),
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
                _isLoading ? Icons.close_rounded : Icons.refresh_rounded,
            onTap: () {
              if (_isLoading) {
                _webViewController?.stopLoading();
              } else {
                _webViewController?.reload();
              }
            },
          ),
        ],
      ),
    );
  }

  void _showAddressBarInput() {
    final c = TextEditingController(text: _currentUrl);
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
            fillColor: Colors.white.withValues(alpha: 0.05),
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            hintText: 'https://',
            hintStyle: const TextStyle(color: Colors.white30),
          ),
          onSubmitted: (url) {
            Navigator.of(ctx).pop();
            if (!url.startsWith('http')) url = 'https://$url';
            _webViewController?.loadUrl(
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

  // ─── JARVIS Agentic Control Panel ──────────────────────────────────────────

  Widget _buildAgentPanel() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0D0D22),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(
                color: _primary.withValues(alpha: 0.3), width: 0.8),
            boxShadow: [
              BoxShadow(
                color: _primary.withValues(alpha: 0.15),
                blurRadius: 30,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
                padding:
                    const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    ShaderMask(
                      shaderCallback: (b) =>
                          LinearGradient(colors: [_primary, _secondary])
                              .createShader(b),
                      child: const Text('⚡ JARVIS Agent',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w800)),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () =>
                          setState(() => _agentPanelOpen = false),
                      child: const Icon(Icons.close,
                          color: Colors.white30, size: 18),
                    ),
                  ],
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
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            valueColor:
                                AlwaysStoppedAnimation(_primary),
                          ),
                        ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _agentStatus,
                          style: TextStyle(
                              color: _primary, fontSize: 11),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),

              // Input
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 44,
                        decoration: BoxDecoration(
                          color:
                              Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: _primary.withValues(alpha: 0.4)),
                        ),
                        child: TextField(
                          controller: _agentController,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            hintText:
                                'Tell JARVIS what to do here...',
                            hintStyle: TextStyle(
                                color: Colors.white30, fontSize: 13),
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
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
                          gradient: LinearGradient(
                              colors: [_primary, _secondary]),
                          boxShadow: [
                            BoxShadow(
                                color: _primary.withValues(alpha: 0.4),
                                blurRadius: 12,
                                offset: const Offset(0, 4)),
                          ],
                        ),
                        child: _agentRunning
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation(
                                        Colors.white)),
                              )
                            : const Icon(Icons.bolt_rounded,
                                color: Colors.white, size: 22),
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

  /// Core JARVIS web agent: generate JS → inject → execute → report
  Future<void> _runAgent() async {
    final command = _agentController.text.trim();
    if (command.isEmpty) return;

    setState(() {
      _agentRunning = true;
      _agentStatus = '🤖 JARVIS is thinking...';
    });

    try {
      final router = context.read<AIRouter>();

      // Step 1 — Ask AI to generate JavaScript automation code
      setState(() => _agentStatus = '⚙️ Generating automation script...');

      final jsCodeRaw = await router.generateDirectResponse(
        prompt:
            'You are a web automation expert. The user is on: $_currentUrl\n'
            'Site hint: ${widget.integration.agentJsHint}\n\n'
            'User command: "$command"\n\n'
            'Generate ONLY pure JavaScript code (no explanation, no markdown) that:\n'
            '1. Finds the correct input/button on the page using querySelector\n'
            '2. Fills values by setting .value AND dispatching "input" and "change" events (required for React/Vue frameworks)\n'
            '3. Clicks buttons via .click()\n'
            '4. Returns a status string like "✅ DONE" or "❌ Not found"\n\n'
            'Example for inputs: el.value="xyz"; el.dispatchEvent(new Event("input", {bubbles: true}));\n'
            'CRITICAL: Output ONLY valid JavaScript code. No ```js tags, no markdown formatting at all.',
        systemOverride:
            'You are a JavaScript automation code generator. Output only raw JS code that will be run via evaluateJavascript.',
      );

      // Strip markdown code blocks just in case the model ignored instructions
      String jsCode = jsCodeRaw;
      if (jsCode.contains('```')) {
        final exp = RegExp(r'```(?:javascript|js)?\s*([\s\S]*?)```');
        final match = exp.firstMatch(jsCode);
        if (match != null) jsCode = match.group(1) ?? jsCode;
        jsCode = jsCode.replaceAll('```javascript', '').replaceAll('```js', '').replaceAll('```', '');
      }

      // Step 2 — Inject and execute
      setState(() => _agentStatus = '🚀 Executing on page...');

      final result = await _webViewController?.evaluateJavascript(
        source: '''
(function() {
  try {
    $jsCode
  } catch(e) {
    return "ERROR: " + e.message;
  }
})()
''',
      );

      // Step 3 — Report result
      final resultStr = result?.toString() ?? 'Done';
      setState(() {
        _agentRunning = false;
        _agentStatus =
            '✅ ${resultStr.length > 60 ? '${resultStr.substring(0, 60)}...' : resultStr}';
      });

      _agentController.clear();

      // Wait a moment then take screenshot / scroll to result
      await Future.delayed(const Duration(milliseconds: 800));
      await _webViewController?.scrollTo(x: 0, y: 500);
    } catch (e) {
      setState(() {
        _agentRunning = false;
        _agentStatus = '⚠️ Agent error: $e';
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
            enabled: _canGoBack,
            onTap: () => _webViewController?.goBack(),
          ),
          _NavBtn(
            icon: Icons.arrow_forward_ios_rounded,
            enabled: _canGoForward,
            onTap: () => _webViewController?.goForward(),
          ),
          _NavBtn(
            icon: Icons.home_outlined,
            enabled: true,
            onTap: () => _webViewController?.loadUrl(
              urlRequest: URLRequest(url: WebUri(widget.integration.url)),
            ),
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
                          _primary.withValues(alpha: 0.18),
                          _secondary.withValues(alpha: 0.12),
                        ],
                ),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: _primary.withValues(alpha: 0.5),
                  width: 0.8,
                ),
                boxShadow: _agentPanelOpen
                    ? [
                        BoxShadow(
                          color: _primary.withValues(alpha: 0.4),
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
                              .withValues(alpha: 0.7),
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
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 18, color: Colors.white54),
      ),
    );
  }
}
