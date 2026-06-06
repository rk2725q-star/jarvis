import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:jarvis_ai/theme/jarvis_theme.dart';
import 'package:jarvis_ai/core/router/ai_router.dart';
import 'package:jarvis_ai/core/security/secure_storage_service.dart';
import 'package:jarvis_ai/core/api/nvidia_client.dart';
import 'package:jarvis_ai/core/memory/memory_service.dart';
import 'package:jarvis_ai/features/chat/chat_provider.dart';
import 'package:jarvis_ai/services/netless_service.dart';
import 'package:jarvis_ai/features/netless/netless_management_screen.dart';
import 'memory_manager_screen.dart';
import 'provider_settings_tile.dart';
import 'ai_providers_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final secureStorage = context.read<SecureStorageService>();
    return Scaffold(
      backgroundColor: JarvisColors.bg,
      body: CustomScrollView(
        slivers: [
          // App bar
          SliverAppBar(
            pinned: true,
            backgroundColor: JarvisColors.surface,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: JarvisColors.textPrimary),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text('Settings', style: TextStyle(color: JarvisColors.textPrimary)),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(0.5),
              child: Divider(height: 0.5, color: JarvisColors.border),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // AI Providers reference link
                  _SectionHeader(title: 'AI Providers', icon: Icons.hub_rounded),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AIProvidersScreen())),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [JarvisColors.accentPrimary.withValues(alpha: 0.12), JarvisColors.accentSecondary.withValues(alpha: 0.06)],
                          begin: Alignment.topLeft, end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: JarvisColors.accentPrimary.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(
                              color: JarvisColors.accentPrimary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.hub_rounded, color: JarvisColors.accentPrimary, size: 20),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Browse All AI Providers', style: TextStyle(color: JarvisColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
                                SizedBox(height: 2),
                                Text('Get API keys, view docs, compare 7 providers + 200+ models', style: TextStyle(color: JarvisColors.textMuted, fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded, color: JarvisColors.textMuted),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Netless (Offline AI) ────────────────────────────────
                  _SectionHeader(title: 'Netless — Offline AI', icon: Icons.wifi_off_rounded),
                  const SizedBox(height: 12),
                  ChangeNotifierProvider.value(
                    value: NetlessService(),
                    child: Consumer<NetlessService>(
                      builder: (context, svc, _) {
                        final isReady = svc.isAvailable;
                        final hasFile = svc.modelPath != null;
                        final color = isReady ? const Color(0xFF00E676) : const Color(0xFF7B5FFF);
                        return GestureDetector(
                          onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const NetlessManagementScreen())),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [color.withValues(alpha: 0.12), color.withValues(alpha: 0.04)],
                                begin: Alignment.topLeft, end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: color.withValues(alpha: 0.35)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 44, height: 44,
                                  decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                                  child: Icon(
                                    isReady ? Icons.hub_rounded : svc.isDownloading ? Icons.download_rounded : Icons.wifi_off_rounded,
                                    color: color, size: 22,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        isReady ? 'Netless Active' : hasFile ? 'Gemma Downloaded — Tap to Load' : 'Gemma 4 E2B-it (Offline)',
                                        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14),
                                        maxLines: 1, overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        svc.isDownloading ? '${(svc.downloadProgress * 100).toInt()}% — ${svc.status}' : svc.status,
                                        style: const TextStyle(color: JarvisColors.textMuted, fontSize: 11),
                                        maxLines: 1, overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: color.withValues(alpha: 0.3)),
                                  ),
                                  child: Text(
                                    isReady ? 'READY' : 'MANAGE',
                                    style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Provider API key settings
                  _SectionHeader(title: 'API Keys', icon: Icons.vpn_key_rounded),
                  const SizedBox(height: 12),
                  Consumer<AIRouter>(
                    builder: (context, router, _) {
                      return Column(
                        children: [
                          ProviderSettingsTile(
                            provider: AIProvider.gemini,
                            label: 'Google Gemini',
                            icon: Icons.auto_awesome_rounded,
                            iconColor: JarvisColors.geminiColor,
                            secureStorage: secureStorage,
                            router: router,
                            apiKeyHint: 'AIza...',
                            apiKeyLabel: 'Gemini API Key',
                          ),
                          const SizedBox(height: 10),
                          ProviderSettingsTile(
                            provider: AIProvider.nvidia,
                            label: 'NVIDIA NIM',
                            icon: Icons.memory_rounded,
                            iconColor: JarvisColors.nvidiaColor,
                            secureStorage: secureStorage,
                            router: router,
                            apiKeyHint: 'nvapi-...',
                            apiKeyLabel: 'NVIDIA API Key',
                          ),
                          const SizedBox(height: 10),
                          ProviderSettingsTile(
                            provider: AIProvider.anthropic,
                            label: 'Anthropic Claude',
                            icon: Icons.auto_stories_rounded,
                            iconColor: const Color(0xFFD97757), 
                            secureStorage: secureStorage,
                            router: router,
                            apiKeyHint: 'sk-ant-api03-...',
                            apiKeyLabel: 'Anthropic API Key',
                          ),
                          const SizedBox(height: 10),
                          ProviderSettingsTile(
                            provider: AIProvider.openRouter,
                            label: 'OpenRouter Cloud',
                            icon: Icons.public_rounded,
                            iconColor: JarvisColors.openRouterColor,
                            secureStorage: secureStorage,
                            router: router,
                            apiKeyHint: 'sk-or-v1-...',
                            apiKeyLabel: 'OpenRouter API Key',
                          ),
                          const SizedBox(height: 10),
                          ProviderSettingsTile(
                            provider: AIProvider.ollama,
                            label: 'Ollama (Local)',
                            icon: Icons.computer_rounded,
                            iconColor: JarvisColors.ollamaColor,
                            secureStorage: secureStorage,
                            router: router,
                            noApiKey: true,
                            showUrlInput: true,
                            urlHint: 'http://127.0.0.1:11434',
                            urlLabel: 'Ollama Endpoint',
                            storageKey: 'ollamaLocal',
                          ),
                          const SizedBox(height: 10),
                          ProviderSettingsTile(
                            provider: AIProvider.ollamaCloud,
                            label: 'Ollama Cloud',
                            icon: Icons.cloud_queue_rounded,
                            iconColor: JarvisColors.ollamaColor,
                            secureStorage: secureStorage,
                            router: router,
                            apiKeyHint: 'ollama_...',
                            apiKeyLabel: 'Ollama Cloud Key',
                            showUrlInput: true,
                            urlHint: 'https://ollama.com',
                            urlLabel: 'Cloud Endpoint',
                            storageKey: 'ollamaCloud',
                          ),
                          const SizedBox(height: 10),
                          ProviderSettingsTile(
                            provider: AIProvider.llamaCpp,
                            label: 'llama.cpp Server',
                            icon: Icons.developer_board_rounded,
                            iconColor: JarvisColors.localColor,
                            secureStorage: secureStorage,
                            router: router,
                            apiKeyHint: 'sk-... (optional)',
                            apiKeyLabel: 'Server API Key',
                            showUrlInput: true,
                            urlHint: 'http://127.0.0.1:8080',
                            urlLabel: 'Server Endpoint',
                            storageKey: 'llamaCpp',
                          ),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 28),
                  
                  // Voice section
                  _SectionHeader(title: 'Voice & Speech', icon: Icons.record_voice_over_rounded),
                  const SizedBox(height: 12),
                  Consumer<ChatProvider>(
                    builder: (context, chat, _) {
                      return _InfoCard(
                        children: [
                          _SettingsRow(
                            label: 'Enable TTS',
                            trailing: Switch(
                              value: chat.isTTSEnabled,
                              onChanged: chat.setTTS,
                              activeThumbColor: JarvisColors.accentPrimary,
                            ),
                          ),
                          const Divider(color: JarvisColors.border, height: 1),
                          _SettingsRow(
                            label: 'Voice Mode (Auto-Listen)',
                            trailing: Switch(
                              value: chat.isVoiceMode,
                              onChanged: chat.setVoiceMode,
                              activeThumbColor: JarvisColors.accentPrimary,
                            ),
                          ),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 28),

                  // Memory section
                  _SectionHeader(title: 'Memory', icon: Icons.psychology_alt_rounded),
                  const SizedBox(height: 12),
                  Builder(
                    builder: (context) {
                      final memory = context.read<MemoryService>();
                      return _InfoCard(
                        children: [
                          _SettingsRow(
                            label: 'Stored Memories (${memory.count})',
                            trailing: TextButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (context) => const MemoryManagerScreen()),
                                );
                              },
                              child: const Text('MANAGE', style: TextStyle(color: JarvisColors.accentPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
                            ),
                          ),
                          const Divider(color: JarvisColors.border, height: 1),
                          _SettingsRow(
                            label: 'Clear All Memories',
                            trailing: TextButton(
                              onPressed: () async {
                                await memory.clearAll();
                                if (context.mounted) {
                                  setState(() {});
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Memories cleared'),
                                      backgroundColor: JarvisColors.surfaceElevated,
                                    ),
                                  );
                                }
                              },
                              child: const Text('Clear', style: TextStyle(color: JarvisColors.error)),
                            ),
                          ),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 28),


                  const SizedBox(height: 28),

                  // About & Legal section
                  _SectionHeader(title: 'About & Legal', icon: Icons.info_outline_rounded),
                  const SizedBox(height: 12),
                  _InfoCard(
                    children: [
                      _SettingsRow(
                        label: 'Open Source Licenses',
                        trailing: TextButton(
                          onPressed: () {
                            showLicensePage(
                              context: context,
                              applicationName: 'WFY (JARVIS)',
                              applicationLegalese: 'Licensed under the Apache License, Version 2.0',
                            );
                          },
                          child: const Text('VIEW', style: TextStyle(color: JarvisColors.accentPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 28),

                  // Meta Intelligence section
                  _SectionHeader(title: 'Meta Intelligence', icon: Icons.mediation_rounded),
                  const SizedBox(height: 12),
                  Consumer<AIRouter>(
                    builder: (context, router, _) {
                      return _ZeeraSettingsCard(router: router, secureStorage: secureStorage);
                    },
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ZeeraSettingsCard extends StatefulWidget {
  final AIRouter router;
  final SecureStorageService secureStorage;

  const _ZeeraSettingsCard({required this.router, required this.secureStorage});

  @override
  State<_ZeeraSettingsCard> createState() => _ZeeraSettingsCardState();
}

class _ZeeraSettingsCardState extends State<_ZeeraSettingsCard> {
  final _keyController = TextEditingController();
  bool _obscureKey = true;
  List<String> _availableModels = [];
  bool _isLoadingModels = false;

  @override
  void initState() {
    super.initState();
    _loadKey();
  }

  Future<void> _loadKey() async {
    final key = await widget.secureStorage.getApiKey('zeeraSynthesis');
    if (mounted) {
      setState(() {
        _keyController.text = key ?? '';
      });
      if (key != null && key.isNotEmpty) {
        _fetchModels(key);
      }
    }
  }

  Future<void> _saveKey() async {
    final key = _keyController.text.trim();
    if (key.isNotEmpty) {
      await widget.secureStorage.saveApiKey('zeeraSynthesis', key);
      await _fetchModels(key);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Zeera synthesis key saved and models updated')),
        );
      }
    }
  }

  Future<void> _fetchModels(String key) async {
    if (key.isEmpty) return;
    setState(() => _isLoadingModels = true);
    try {
      final client = NvidiaApiClient(apiKey: key, model: '');
      final models = await client.fetchModels();
      if (mounted) {
        setState(() {
          _availableModels = models..sort();
          _isLoadingModels = false;
        });
      }
    } catch (e) {
      debugPrint('[Zeera] Model fetch error: $e');
      if (mounted) setState(() => _isLoadingModels = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: JarvisColors.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: JarvisColors.border, width: 0.5),
      ),
      child: Column(
        children: [
          SwitchListTile(
            value: widget.router.zeeraEnabled,
            onChanged: (val) => widget.router.setZeeraEnabled(val),
            secondary: const Icon(Icons.auto_awesome_rounded, color: Colors.amber),
            title: const Text("ZEERA Mode", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            subtitle: const Text("Enable Dual-Model Collaborative Intelligence", style: TextStyle(color: JarvisColors.textMuted, fontSize: 11)),
            activeThumbColor: Colors.amber,
          ),
          const Divider(height: 1, color: JarvisColors.border),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ZeeraPanel(
                  title: "ZEERA SYNTHESIS (NVIDIA)",
                  icon: Icons.vpn_key_rounded,
                  child: Column(
                    children: [
                      const Text(
                        "Zeera uses Nvidia Cloud for the final high-complexity synthesis pass.",
                        style: TextStyle(color: JarvisColors.textMuted, fontSize: 11),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _keyController,
                        obscureText: _obscureKey,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: "Enter NVIDIA API Key...",
                          hintStyle: const TextStyle(color: Colors.white24),
                          filled: true,
                          fillColor: Colors.black26,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureKey ? Icons.visibility_off : Icons.visibility,
                              color: Colors.white54,
                              size: 18,
                            ),
                            onPressed: () => setState(() => _obscureKey = !_obscureKey),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      if (_isLoadingModels)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: LinearProgressIndicator(backgroundColor: Colors.transparent, color: Colors.amber),
                        )
                      else if (_availableModels.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: DropdownButtonFormField<String>(
                            // ignore: deprecated_member_use
                            value: _availableModels.contains(widget.router.zeeraSynthesisModel) 
                                ? widget.router.zeeraSynthesisModel 
                                : null,
                            dropdownColor: JarvisColors.surfaceElevated,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            decoration: InputDecoration(
                              labelText: "Synthesis Model",
                              labelStyle: const TextStyle(color: Colors.amber, fontSize: 11),
                              filled: true,
                              fillColor: Colors.black26,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            ),
                            items: _availableModels.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                            onChanged: (val) => widget.router.setZeeraSynthesisModel(val),
                          ),
                        ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _saveKey,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amber,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text("Update Synthesis Key", style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _ConfigColumn(
                        label: "ROUNDS",
                        value: "${widget.router.zeeraRounds}",
                        onTap: () {
                          int next = widget.router.zeeraRounds + 1;
                          if (next > 5) next = 1;
                          widget.router.setZeeraRounds(next);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ConfigColumn(
                        label: "MODEL A",
                        value: widget.router.getSelectedModel(widget.router.zeeraProviderA)?.toUpperCase() ?? 
                               widget.router.zeeraProviderA.name.toUpperCase(),
                        onTap: () {
                          final providers = [AIProvider.nvidia, AIProvider.ollamaCloud, AIProvider.anthropic, AIProvider.openRouter, AIProvider.gemini];
                          int currentIdx = providers.indexOf(widget.router.zeeraProviderA);
                          if (currentIdx == -1) currentIdx = 0;
                          int nextIdx = (currentIdx + 1) % providers.length;
                          widget.router.setZeeraProviderA(providers[nextIdx]);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ConfigColumn(
                        label: "MODEL B",
                        value: widget.router.getSelectedModel(widget.router.zeeraProviderB)?.toUpperCase() ?? 
                               widget.router.zeeraProviderB.name.toUpperCase(),
                        onTap: () {
                          final providers = [AIProvider.ollamaCloud, AIProvider.nvidia, AIProvider.anthropic, AIProvider.openRouter, AIProvider.gemini];
                          int currentIdx = providers.indexOf(widget.router.zeeraProviderB);
                          if (currentIdx == -1) currentIdx = 0;
                          int nextIdx = (currentIdx + 1) % providers.length;
                          widget.router.setZeeraProviderB(providers[nextIdx]);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ZeeraPanel extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _ZeeraPanel({required this.title, required this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: JarvisColors.textMuted),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                color: JarvisColors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _ConfigColumn extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _ConfigColumn({required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: Colors.black12,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: JarvisColors.border, width: 0.5),
        ),
        child: Column(
          children: [
            Text(label, style: const TextStyle(color: JarvisColors.textMuted, fontSize: 9, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: JarvisColors.accentPrimary),
        const SizedBox(width: 8),
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            color: JarvisColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  final List<Widget> children;

  const _InfoCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: JarvisColors.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: JarvisColors.border, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final String label;
  final Widget trailing;

  const _SettingsRow({required this.label, required this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: JarvisColors.textSecondary, fontSize: 14)),
          trailing,
        ],
      ),
    );
  }
}
