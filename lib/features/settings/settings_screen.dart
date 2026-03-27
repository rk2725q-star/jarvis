import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/jarvis_theme.dart';
import '../../core/router/ai_router.dart';
import '../../core/security/secure_storage_service.dart';
import '../../core/memory/memory_service.dart';
import '../chat/chat_provider.dart';
import 'memory_manager_screen.dart';
import 'provider_settings_tile.dart';

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
                  // Providers section
                  _SectionHeader(title: 'AI Providers', icon: Icons.hub_rounded),
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
                            urlHint: 'https://api.ollama.com',
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


                  // About
                  _SectionHeader(title: 'About', icon: Icons.info_outline_rounded),
                  const SizedBox(height: 12),
                  _InfoCard(
                    children: [
                      const _SettingsRow(label: 'Version', trailing: Text('1.0.0', style: TextStyle(color: JarvisColors.textMuted))),
                      const Divider(color: JarvisColors.border, height: 1),
                      const _SettingsRow(
                        label: 'Providers',
                        trailing: Text('Gemini · NVIDIA · DeepSeek · Ollama · Local', style: TextStyle(color: JarvisColors.textMuted, fontSize: 12)),
                      ),
                    ],
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
