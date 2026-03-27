import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../theme/jarvis_theme.dart';
import '../../core/router/ai_router.dart';
import '../../core/security/secure_storage_service.dart';
import '../../providers/ollama_provider.dart';
import 'package:provider/provider.dart';

class ProviderSettingsTile extends StatefulWidget {
  final AIProvider provider;
  final String label;
  final IconData icon;
  final Color iconColor;
  final SecureStorageService secureStorage;
  final AIRouter router;
  final String? apiKeyHint;
  final String? apiKeyLabel;
  final bool noApiKey;
  final bool showUrlInput;
  final String? urlHint;
  final String? urlLabel;
  final String? storageKey;

  const ProviderSettingsTile({
    super.key,
    required this.provider,
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.secureStorage,
    required this.router,
    this.apiKeyHint,
    this.apiKeyLabel,
    this.noApiKey = false,
    this.showUrlInput = false,
    this.urlHint,
    this.urlLabel,
    this.storageKey,
  });

  @override
  State<ProviderSettingsTile> createState() => _ProviderSettingsTileState();
}

class _ProviderSettingsTileState extends State<ProviderSettingsTile> {
  bool _expanded = false;
  bool _hasKey = false;
  List<String> _models = [];
  bool _loadingModels = false;
  String? _selectedModel;
  final _keyController = TextEditingController();
  final _urlController = TextEditingController();
  bool _obscureKey = true;

  String get _storageId => widget.storageKey ?? widget.provider.name;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!widget.noApiKey) {
      final key = await widget.secureStorage.getApiKey(_storageId);
      if (mounted) {
        setState(() {
          _hasKey = key != null && key.isNotEmpty;
          _keyController.text = key ?? '';
        });
      }
    }
    if (widget.showUrlInput) {
      final url = await widget.secureStorage.getBaseUrl(_storageId);
      if (mounted) {
        setState(() {
          _urlController.text = url ?? '';
        });
      }
    }
    _selectedModel = widget.router.getSelectedModel(widget.provider);
  }

  Future<void> _saveKey() async {
    final key = _keyController.text.trim();
    final url = widget.showUrlInput ? _urlController.text.trim() : null;

    if (!widget.noApiKey && key.isNotEmpty) {
      await widget.secureStorage.saveApiKey(_storageId, key);
      if (!mounted) return;
      setState(() => _hasKey = true);
    }
    if (widget.showUrlInput && url != null && url.isNotEmpty) {
      await widget.secureStorage.saveBaseUrl(_storageId, url);
      if (!mounted) return;
    }

    // SPECIAL HANDLING: If this is an Ollama provider, sync the specialized OllamaProvider
    if (widget.provider == AIProvider.ollamaCloud || widget.provider == AIProvider.ollama) {
      final op = context.read<OllamaProvider>();
      await op.saveSettings(
        apiKey:  (widget.provider == AIProvider.ollamaCloud) ? key : null,
        baseUrl: (widget.provider == AIProvider.ollamaCloud) ? url : null,
        localUrl: (widget.provider == AIProvider.ollama)     ? url : null,
      );
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${widget.label} settings saved securely'),
          backgroundColor: JarvisColors.success.withValues(alpha: 0.8),
        ),
      );
    }
  }

  Future<void> _fetchModels() async {
    setState(() => _loadingModels = true);
    final models = await widget.router.fetchModels(widget.provider);
    if (!mounted) return;
    setState(() {
      _models = models;
      _loadingModels = false;
    });
  }

  @override
  void dispose() {
    _keyController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEnabled = widget.router.isProviderEnabled(widget.provider);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        color: _expanded ? JarvisColors.surfaceHighlight : JarvisColors.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _expanded
              ? widget.iconColor.withValues(alpha: 0.4)
              : JarvisColors.border,
          width: _expanded ? 1.5 : 0.5,
        ),
      ),
      child: Column(
        children: [
          // Header row
          InkWell(
            onTap: () {
              setState(() => _expanded = !_expanded);
              if (_expanded && _models.isEmpty && !widget.noApiKey) {
                _fetchModels();
              }
            },
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.iconColor.withValues(alpha: 0.15),
                    ),
                    child: Icon(widget.icon, color: widget.iconColor, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.label,
                          style: const TextStyle(
                            color: JarvisColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Row(
                          children: [
                            Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isEnabled
                                    ? (widget.noApiKey || _hasKey)
                                        ? JarvisColors.success
                                        : JarvisColors.warning
                                    : JarvisColors.textMuted,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isEnabled
                                  ? (widget.noApiKey || _hasKey)
                                      ? 'Active'
                                      : 'No API Key'
                                  : 'Disabled',
                              style: TextStyle(
                                color: isEnabled
                                    ? (widget.noApiKey || _hasKey)
                                        ? JarvisColors.success
                                        : JarvisColors.warning
                                    : JarvisColors.textMuted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Enable toggle
                  Transform.scale(
                    scale: 0.85,
                    child: Switch(
                      value: isEnabled,
                      onChanged: (v) {
                        widget.router.setProviderEnabled(widget.provider, v);
                      },
                      activeThumbColor: widget.iconColor,
                      inactiveThumbColor: JarvisColors.textMuted,
                      inactiveTrackColor: JarvisColors.surfaceElevated,
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    color: JarvisColors.textMuted,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),

          // Expanded content
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(color: JarvisColors.border, height: 1),
                  // URL input
                  if (widget.showUrlInput) ...[
                    const SizedBox(height: 14),
                    Text(
                      widget.urlLabel ?? 'Endpoint URL',
                      style: const TextStyle(
                        color: JarvisColors.textMuted,
                        fontSize: 11,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _urlController,
                      style: const TextStyle(
                        color: JarvisColors.textPrimary,
                        fontSize: 14,
                        fontFamily: 'monospace',
                      ),
                      decoration: InputDecoration(
                        hintText: widget.urlHint ?? 'http://...',
                        hintStyle: const TextStyle(color: JarvisColors.textMuted, fontSize: 13),
                        filled: true,
                        fillColor: JarvisColors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: JarvisColors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: JarvisColors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: widget.iconColor.withValues(alpha: 0.6)),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    ),
                  ],

                  // API key input
                  if (!widget.noApiKey) ...[
                    const SizedBox(height: 14),
                    Text(
                      widget.apiKeyLabel ?? 'API Key',
                      style: const TextStyle(
                        color: JarvisColors.textMuted,
                        fontSize: 11,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _keyController,
                      obscureText: _obscureKey,
                      style: const TextStyle(
                        color: JarvisColors.textPrimary,
                        fontSize: 14,
                        fontFamily: 'monospace',
                      ),
                      decoration: InputDecoration(
                        hintText: widget.apiKeyHint ?? 'Enter API key...',
                        hintStyle: const TextStyle(color: JarvisColors.textMuted, fontSize: 13),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureKey ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                            color: JarvisColors.textMuted,
                            size: 18,
                          ),
                          onPressed: () => setState(() => _obscureKey = !_obscureKey),
                        ),
                        filled: true,
                        fillColor: JarvisColors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: JarvisColors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: JarvisColors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: widget.iconColor.withValues(alpha: 0.6)),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    ),
                  ],

                  // Ollama Specific Mode Toggle
                  if (widget.provider == AIProvider.ollamaCloud || widget.provider == AIProvider.ollama) ...[
                    const SizedBox(height: 18),
                    const Text(
                      'OLLAMA MODE',
                      style: TextStyle(color: JarvisColors.textMuted, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
                    ),
                    const SizedBox(height: 10),
                    Consumer<OllamaProvider>(
                      builder: (context, op, _) => Row(
                        children: [
                          _ModeChip(
                            label: 'Cloud Mode',
                            selected: op.useCloud,
                            onTap: () => op.saveSettings(useCloud: true),
                          ),
                          const SizedBox(width: 8),
                          _ModeChip(
                            label: 'Local (PC)',
                            selected: !op.useCloud,
                            onTap: () => op.saveSettings(useCloud: false),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Save button for URL/Key
                  if (widget.showUrlInput || !widget.noApiKey) ...[
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _saveKey,
                        icon: const Icon(Icons.save_rounded, size: 18),
                        label: const Text('Save Settings', style: TextStyle(fontWeight: FontWeight.w600)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: widget.iconColor.withValues(alpha: 0.2),
                          foregroundColor: widget.iconColor,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: widget.iconColor.withValues(alpha: 0.4)),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],

                  // Test Connection for Ollama
                  if (widget.provider == AIProvider.ollamaCloud || widget.provider == AIProvider.ollama) ...[
                    const SizedBox(height: 12),
                    Consumer<OllamaProvider>(
                      builder: (context, op, _) => Column(
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: op.testing ? null : op.testConnection,
                              icon: op.testing 
                                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.bolt, size: 16),
                              label: Text(op.testing ? 'Testing...' : 'Test Connection'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: op.testResult?['success'] == true ? Colors.green : widget.iconColor,
                                side: BorderSide(color: op.testResult?['success'] == true ? Colors.green.withValues(alpha: 0.5) : widget.iconColor.withValues(alpha: 0.5)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                          if (op.testResult != null) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: op.testResult!['success'] ? Colors.green.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                op.testResult!['success'] 
                                  ? '✅ ${op.testResult!['latency_ms']}ms' 
                                  : '❌ ${op.testResult!['error']}',
                                style: TextStyle(fontSize: 11, color: op.testResult!['success'] ? Colors.green : Colors.red),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),

                  // Model selection
                  Row(
                    children: [
                      const Text(
                        'MODEL',
                        style: TextStyle(
                          color: JarvisColors.textMuted,
                          fontSize: 11,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const Spacer(),
                      if (!widget.noApiKey)
                        TextButton.icon(
                          onPressed: _fetchModels,
                          icon: _loadingModels
                              ? const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: JarvisColors.accentPrimary),
                                )
                              : const Icon(Icons.refresh_rounded, size: 14, color: JarvisColors.accentPrimary),
                          label: const Text('Fetch', style: TextStyle(color: JarvisColors.accentPrimary, fontSize: 12)),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  if (_models.isNotEmpty)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: JarvisColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: JarvisColors.border, width: 0.5),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          dropdownColor: JarvisColors.surfaceElevated,
                          value: _selectedModel != null && _models.contains(_selectedModel!)
                              ? _selectedModel
                              : _models.first,
                          icon: Icon(Icons.arrow_drop_down_rounded, color: widget.iconColor),
                          selectedItemBuilder: (context) => _models.map((model) {
                            return Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                model,
                                style: TextStyle(
                                  color: widget.iconColor,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            );
                          }).toList(),
                          items: _models.map((model) {
                            return DropdownMenuItem(
                              value: model,
                              child: Text(
                                model,
                                style: const TextStyle(
                                  color: JarvisColors.textPrimary,
                                  fontSize: 14,
                                ),
                              ),
                            );
                          }).toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _selectedModel = value);
                              widget.router.setSelectedModel(widget.provider, value);
                            }
                          },
                        ),
                      ),
                    )
                  else
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        widget.noApiKey
                            ? 'Models auto-detected at runtime'
                            : _hasKey
                                ? 'Tap "Fetch" to load available models'
                                : 'Enter API key to fetch models',
                        style: const TextStyle(
                          color: JarvisColors.textMuted,
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ).animate().fadeIn(duration: 200.ms).slideY(begin: -0.05, end: 0),
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ModeChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? JarvisColors.accentPrimary.withValues(alpha: 0.2) : JarvisColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? JarvisColors.accentPrimary : JarvisColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? JarvisColors.accentPrimary : JarvisColors.textMuted,
            fontSize: 12,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
