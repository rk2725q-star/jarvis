import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/codesign_models.dart';

class CodesignPanel extends StatefulWidget {
  final CodesignArtifact? artifact;
  final void Function(CodesignRequest) onGenerate;
  final void Function(String editInstruction)? onEdit;
  final void Function(CodesignArtifact)? onExport;
  final void Function(Uint8List)? onSaveImage;
  final void Function(CodesignArtifact)? onRestore;
  final bool isLoading;

  const CodesignPanel({
    super.key,
    this.artifact,
    required this.onGenerate,
    this.onEdit,
    this.onExport,
    this.onSaveImage,
    this.onRestore,
    this.isLoading = false,
  });

  @override
  State<CodesignPanel> createState() => _CodesignPanelState();
}

class _CodesignPanelState extends State<CodesignPanel> with SingleTickerProviderStateMixin {
  final _promptController = TextEditingController();
  final _editController = TextEditingController();
  InAppWebViewController? _webViewController;
  CodesignArtifactType _type = CodesignArtifactType.landingPage;

  // Viewport & Workspace settings
  String _viewport = 'desktop'; // desktop, tablet, mobile
  int _activeTab = 0; // 0 = Preview, 1 = Code
  int _historyIndex = -1; // -1 = latest, >=0 = index in history
  Map<String, dynamic> _tweakTokens = {};

  @override
  void initState() {
    super.initState();
    _initTweaks();
  }

  @override
  void didUpdateWidget(CodesignPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.artifact != oldWidget.artifact) {
      _historyIndex = -1;
      _initTweaks();
      // Force webview reload
      if (_webViewController != null && widget.artifact != null) {
        _webViewController!.loadData(data: activeHtml);
      }
    }
  }

  String get activeHtml {
    if (widget.artifact == null) return '';
    if (_historyIndex == -1 || _historyIndex >= widget.artifact!.history.length) {
      return widget.artifact!.htmlContent;
    }
    return widget.artifact!.history[_historyIndex];
  }

  void _initTweaks() {
    if (widget.artifact == null) {
      _tweakTokens = {};
      return;
    }
    _tweakTokens = _parseEditmode(activeHtml);
  }

  Map<String, dynamic> _parseEditmode(String html) {
    try {
      final regex = RegExp(r'/\*EDITMODE-BEGIN\*/([\s\S]*?)/\*EDITMODE-END\*/');
      final match = regex.firstMatch(html);
      if (match != null) {
        final jsonText = match.group(1)!.trim();
        final parsed = jsonDecode(jsonText);
        if (parsed is Map<String, dynamic>) {
          return parsed;
        }
      }
    } catch (e) {
      debugPrint("EDITMODE parse error: $e");
    }
    return const {};
  }

  void _updateTweakValue(String key, dynamic value) {
    setState(() {
      _tweakTokens[key] = value;
    });

    if (_webViewController != null) {
      final jsonStr = jsonEncode(_tweakTokens);
      _webViewController!.evaluateJavascript(source: """
        if (typeof applyTweaks === 'function') {
          applyTweaks($jsonStr);
        } else {
          Object.entries($jsonStr).forEach(([k, val]) => {
            const kebab = k.replace(/([a-z0-9])([A-Z])/g, '\$1-\$2').toLowerCase();
            document.documentElement.style.setProperty('--ocd-tweak-' + kebab, val);
            if (k === 'darkMode') {
              if (val) {
                document.documentElement.classList.add('dark');
              } else {
                document.documentElement.classList.remove('dark');
              }
            }
          });
        }
      """);
    }
  }

  void _changeHistoryIndex(int idx) {
    setState(() {
      _historyIndex = idx;
      _initTweaks();
    });
    _webViewController?.loadData(data: activeHtml);
  }

  @override
  Widget build(BuildContext context) {
    final mediaWidth = MediaQuery.of(context).size.width;
    final isWide = mediaWidth >= 900;

    // Control Sidebar
    final controlSidebar = Container(
      width: isWide ? 360 : double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF141420),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.design_services, color: Colors.tealAccent),
                const SizedBox(width: 8),
                const Text(
                  'CoDesign Studio',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                if (widget.artifact != null && widget.artifact!.history.isNotEmpty)
                  _buildHistoryDropdown(),
              ],
            ),
            if (widget.artifact != null && _historyIndex != -1)
              _buildRestoreButton(),
            const SizedBox(height: 16),

            // Prompt input
            const Text('Prompt / Visual Concept', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            TextField(
              controller: _promptController,
              maxLines: 2,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'e.g. "Creative portfolio with glassmorphism..."',
                hintStyle: const TextStyle(color: Colors.white30),
                fillColor: const Color(0xFF1E1E2E),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white12),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.tealAccent),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Type chips selector
            const Text('Layout Category', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            _buildTypeSelector(),
            const SizedBox(height: 16),

            // Generate button
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton.icon(
                onPressed: widget.isLoading ? null : () => widget.onGenerate(
                  CodesignRequest(prompt: _promptController.text.trim(), type: _type),
                ),
                icon: widget.isLoading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : const Icon(Icons.auto_fix_high, size: 18),
                label: Text(widget.isLoading ? 'Designing...' : 'Generate Design'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.tealAccent,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 5,
                  textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ),

            // Editmode tweak inputs
            _buildTweakControls(),

            // Follow-up chat box
            if (widget.artifact != null) ...[
              const SizedBox(height: 20),
              const Divider(color: Colors.white10),
              const SizedBox(height: 8),
              const Text('Iterate & Refine Layout', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _editController,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'e.g. "Add a neon pink pricing card"',
                        hintStyle: const TextStyle(color: Colors.white30),
                        fillColor: const Color(0xFF1E1E2E),
                        filled: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.white12),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.white12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: () {
                      if (_editController.text.trim().isNotEmpty) {
                        widget.onEdit?.call(_editController.text.trim());
                        _editController.clear();
                      }
                    },
                    icon: const Icon(Icons.send, size: 18),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.tealAccent,
                      foregroundColor: Colors.black,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );

    // Workspace View (Preview vs Code)
    final workspaceView = Expanded(
      child: Column(
        children: [
          // Viewport + Mode Toolbar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF141420),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                // Workspace Tab Switcher
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E2E),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      _buildWorkspaceTab(0, Icons.visibility, 'Preview'),
                      _buildWorkspaceTab(1, Icons.code, 'Source Code'),
                    ],
                  ),
                ),
                const Spacer(),
                // Viewport select toolbar (only for Preview tab)
                if (_activeTab == 0 && widget.artifact != null) ...[
                  _buildViewportButton('desktop', Icons.desktop_windows, 'Desktop'),
                  const SizedBox(width: 6),
                  _buildViewportButton('tablet', Icons.tablet_mac, 'Tablet'),
                  const SizedBox(width: 6),
                  _buildViewportButton('mobile', Icons.phone_android, 'Mobile'),
                ],
              ],
            ),
          ),
          // Tab Content
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              color: const Color(0xFF0F0F16),
              child: _activeTab == 0 ? _buildViewportPreview() : _buildCodeEditor(),
            ),
          ),
          // Export options bar
          if (widget.artifact != null) _buildExportOptionsBar(),
        ],
      ),
    );

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F0F16),
      ),
      child: isWide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                controlSidebar,
                const SizedBox(width: 16),
                workspaceView,
              ],
            )
          : SingleChildScrollView(
              child: Column(
                children: [
                  controlSidebar,
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 600,
                    child: workspaceView,
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildWorkspaceTab(int index, IconData icon, String label) {
    final isSelected = _activeTab == index;
    return GestureDetector(
      onTap: () => setState(() => _activeTab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.tealAccent : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: isSelected ? Colors.black : Colors.white70),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.black : Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildViewportButton(String mode, IconData icon, String tooltip) {
    final isSelected = _viewport == mode;
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, color: isSelected ? Colors.tealAccent : Colors.white60, size: 20),
      style: IconButton.styleFrom(
        backgroundColor: isSelected ? const Color(0xFF1E1E2E) : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: isSelected ? Colors.tealAccent : Colors.transparent),
        ),
      ),
      onPressed: () => setState(() => _viewport = mode),
    );
  }

  Widget _buildHistoryDropdown() {
    final historyLength = widget.artifact!.history.length;
    final items = <DropdownMenuItem<int>>[
      DropdownMenuItem(
        value: -1,
        child: const Text('Latest', style: TextStyle(color: Colors.white, fontSize: 12)),
      ),
    ];
    for (var i = historyLength - 1; i >= 0; i--) {
      items.add(DropdownMenuItem(
        value: i,
        child: Text('Version ${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 12)),
      ));
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      height: 28,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: _historyIndex,
          dropdownColor: const Color(0xFF1E1E2E),
          icon: const Icon(Icons.history, color: Colors.tealAccent, size: 16),
          items: items,
          onChanged: (val) {
            if (val != null) {
              _changeHistoryIndex(val);
            }
          },
        ),
      ),
    );
  }

  Widget _buildRestoreButton() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SizedBox(
        width: double.infinity,
        height: 32,
        child: OutlinedButton.icon(
          onPressed: () {
            final restoredHtml = widget.artifact!.history[_historyIndex];
            final newHistory = <String>[];
            for (var i = 0; i <= _historyIndex; i++) {
              if (i < widget.artifact!.history.length) {
                newHistory.add(widget.artifact!.history[i]);
              }
            }
            final restoredArtifact = CodesignArtifact(
              id: widget.artifact!.id,
              htmlContent: restoredHtml,
              request: widget.artifact!.request,
              createdAt: DateTime.now(),
              history: newHistory,
            );
            widget.onRestore?.call(restoredArtifact);
            setState(() {
              _historyIndex = -1;
            });
          },
          icon: const Icon(Icons.restore, size: 14, color: Colors.tealAccent),
          label: const Text('Restore This Version', style: TextStyle(fontSize: 11, color: Colors.tealAccent)),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Colors.teal),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
    );
  }

  Widget _buildTypeSelector() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: CodesignArtifactType.values.map((t) {
          final labels = {
            CodesignArtifactType.landingPage: '🏠 Landing',
            CodesignArtifactType.dashboard: '📊 Dashboard',
            CodesignArtifactType.slidesDeck: '📑 Slides',
            CodesignArtifactType.mobileUI: '📱 Mobile',
            CodesignArtifactType.pricingPage: '💰 Pricing',
          };
          final isSelected = _type == t;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text(labels[t]!, style: TextStyle(fontSize: 11, color: isSelected ? Colors.black : Colors.white)),
              selected: isSelected,
              selectedColor: Colors.tealAccent,
              backgroundColor: const Color(0xFF1E1E2E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              onSelected: (_) => setState(() => _type = t),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTweakControls() {
    if (_tweakTokens.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tune, color: Colors.tealAccent, size: 16),
              const SizedBox(width: 8),
              const Text(
                'Live Style Tweaker',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ..._tweakTokens.entries.map((entry) {
            final key = entry.key;
            final val = entry.value;
            final humanName = key.replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m.group(1)}').trim();
            final label = humanName.substring(0, 1).toUpperCase() + humanName.substring(1);

            if (val is bool) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    Switch(
                      value: val,
                      activeThumbColor: Colors.tealAccent,
                      onChanged: (newVal) => _updateTweakValue(key, newVal),
                    ),
                  ],
                ),
              );
            } else if (val is num) {
              double doubleVal = val.toDouble();
              double sliderMin = 0.0;
              double sliderMax = 10.0;
              int? divisions = 100;
              if (doubleVal <= 2.0) {
                sliderMax = 2.0;
                divisions = 20;
              } else if (doubleVal <= 24.0) {
                sliderMax = 48.0;
                divisions = 48;
              } else {
                sliderMax = 100.0;
                divisions = 100;
              }
              doubleVal = doubleVal.clamp(sliderMin, sliderMax);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        Text(doubleVal.toStringAsFixed(1), style: const TextStyle(color: Colors.tealAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      ),
                      child: Slider(
                        value: doubleVal,
                        min: sliderMin,
                        max: sliderMax,
                        divisions: divisions,
                        activeColor: Colors.tealAccent,
                        inactiveColor: Colors.white24,
                        onChanged: (newVal) {
                          _updateTweakValue(key, val is int ? newVal.round() : newVal);
                        },
                      ),
                    ),
                  ],
                ),
              );
            } else if (val is String && (val.startsWith('#') || val.startsWith('rgb') || val.startsWith('hsl') || val.startsWith('oklch'))) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    GestureDetector(
                      onTap: () => _showColorPickerDialog(key, val),
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: val.startsWith('#')
                              ? Color(int.parse(val.replaceFirst('#', '0xff')))
                              : Colors.indigoAccent,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white30),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            } else {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    SizedBox(
                      width: 100,
                      height: 28,
                      child: TextField(
                        controller: TextEditingController(text: val.toString()),
                        onSubmitted: (newVal) => _updateTweakValue(key, newVal),
                        style: const TextStyle(color: Colors.white, fontSize: 11),
                        decoration: const InputDecoration(
                          contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          border: OutlineInputBorder(),
                          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }
          }),
        ],
      ),
    );
  }

  void _showColorPickerDialog(String key, String currentColor) {
    final hexController = TextEditingController(text: currentColor);
    final presets = [
      '#6366f1', // Indigo
      '#3b82f6', // Blue
      '#10b981', // Emerald
      '#f59e0b', // Amber
      '#ef4444', // Red
      '#8b5cf6', // Violet
      '#ec4899', // Pink
      '#14b8a6', // Teal
      '#0f172a', // Dark slate
      '#64748b', // Grey
    ];
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E2E),
          title: const Text('Pick Tweak Color', style: TextStyle(color: Colors.white, fontSize: 14)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: presets.map((colorStr) {
                  final color = Color(int.parse(colorStr.replaceFirst('#', '0xff')));
                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      _updateTweakValue(key, colorStr);
                    },
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: currentColor.toLowerCase() == colorStr.toLowerCase()
                              ? Colors.white
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: hexController,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'Custom Hex Color',
                  labelStyle: TextStyle(color: Colors.white70),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.tealAccent)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
            ),
            ElevatedButton(
              onPressed: () {
                final txt = hexController.text.trim();
                if (txt.startsWith('#') && (txt.length == 7 || txt.length == 9 || txt.length == 4)) {
                  Navigator.pop(context);
                  _updateTweakValue(key, txt);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Invalid Hex Color format (e.g. #6366F1)')),
                  );
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.tealAccent, foregroundColor: Colors.black),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildViewportPreview() {
    if (widget.artifact == null) {
      return const Center(
        child: Text(
          'No design generated yet. Use the prompt studio to build one.',
          style: TextStyle(color: Colors.white38, fontSize: 13),
        ),
      );
    }

    final webView = InAppWebView(
      initialData: InAppWebViewInitialData(
        data: activeHtml,
      ),
      onWebViewCreated: (controller) {
        _webViewController = controller;
        controller.loadData(data: activeHtml);
      },
    );

    if (_viewport == 'mobile') {
      return Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: _buildPhoneFrame(webView),
          ),
        ),
      );
    } else if (_viewport == 'tablet') {
      return Center(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Container(
                width: 768,
                height: 900,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    const BoxShadow(color: Color.fromRGBO(0, 0, 0, 0.5), blurRadius: 20, offset: Offset(0, 10))
                  ],
                  border: Border.all(color: Colors.white24, width: 2),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: webView,
                ),
              ),
            ),
          ),
        ),
      );
    } else {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: webView,
        ),
      );
    }
  }

  Widget _buildPhoneFrame(Widget child) {
    return Container(
      width: 320,
      height: 600,
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F16),
        borderRadius: BorderRadius.circular(36),
        border: Border.all(color: const Color(0xFF2C2C3E), width: 8),
        boxShadow: [
          const BoxShadow(color: Color.fromRGBO(0, 0, 0, 0.6), blurRadius: 24, offset: Offset(0, 12)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            child,
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: 120,
                  height: 18,
                  decoration: const BoxDecoration(
                    color: Color(0xFF2C2C3E),
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(12),
                      bottomRight: Radius.circular(12),
                    ),
                  ),
                  child: Center(
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(color: Colors.black, shape: BoxShape.circle),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCodeEditor() {
    if (widget.artifact == null) {
      return const Center(
        child: Text('No code available.', style: TextStyle(color: Colors.white38, fontSize: 13)),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF141420),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: const BoxDecoration(
              color: Color(0xFF1E1E2E),
              borderRadius: BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12)),
            ),
            child: Row(
              children: [
                const Icon(Icons.code, color: Colors.tealAccent, size: 16),
                const SizedBox(width: 8),
                const Text('Source Code', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                const Spacer(),
                IconButton(
                  tooltip: 'Copy Code',
                  icon: const Icon(Icons.copy, color: Colors.white70, size: 16),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: activeHtml));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('✅ Source code copied!')),
                    );
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                activeHtml,
                style: GoogleFonts.sourceCodePro(
                  color: const Color(0xFFD4D4D4),
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExportOptionsBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF141420),
        borderRadius: BorderRadius.only(bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16)),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => widget.onExport?.call(widget.artifact!),
              icon: const Icon(Icons.download, size: 16, color: Colors.tealAccent),
              label: const Text('Export HTML', style: TextStyle(color: Colors.tealAccent, fontSize: 12)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.teal),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () async {
                if (_webViewController != null) {
                  final screenshot = await _webViewController!.takeScreenshot();
                  if (screenshot != null) {
                    widget.onSaveImage?.call(screenshot);
                  }
                }
              },
              icon: const Icon(Icons.camera_alt, size: 16, color: Colors.tealAccent),
              label: const Text('Save Screenshot', style: TextStyle(color: Colors.tealAccent, fontSize: 12)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.teal),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
