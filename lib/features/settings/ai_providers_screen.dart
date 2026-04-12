import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:jarvis_ai/theme/jarvis_theme.dart';

class _ProviderInfo {
  final String id;
  final String name;
  final String tagline;
  final String description;
  final String website;
  final String apiUrl;
  final String apiDocsUrl;
  final IconData icon;
  final Color color;
  final List<String> models;
  final String pricing;
  final bool hasFree;

  const _ProviderInfo({
    required this.id,
    required this.name,
    required this.tagline,
    required this.description,
    required this.website,
    required this.apiUrl,
    required this.apiDocsUrl,
    required this.icon,
    required this.color,
    required this.models,
    required this.pricing,
    required this.hasFree,
  });
}

const List<_ProviderInfo> _providers = [
  _ProviderInfo(
    id: 'gemini',
    name: 'Google Gemini',
    tagline: 'Google\'s Most Capable Multimodal AI',
    description: 'Gemini 2.0 Flash, Pro and Ultra models. Deep integration with Google Workspace. '
        'Best for vision tasks, coding, and research. Generous free tier.',
    website: 'https://gemini.google.com',
    apiUrl: 'https://aistudio.google.com/app/apikey',
    apiDocsUrl: 'https://ai.google.dev/gemini-api/docs',
    icon: Icons.auto_awesome_rounded,
    color: Color(0xFF4285F4),
    models: ['gemini-2.0-flash', 'gemini-2.0-pro', 'gemini-1.5-pro', 'gemini-1.5-flash'],
    pricing: 'Free tier + Pay-as-you-go',
    hasFree: true,
  ),
  _ProviderInfo(
    id: 'nvidia',
    name: 'NVIDIA NIM',
    tagline: 'Enterprise-Grade GPU-Accelerated Inference',
    description: 'Access the world\'s largest collection of optimized AI models via NVIDIA\'s cloud. '
        'Includes Llama 3.3, Mistral Large, DeepSeek V3, Qwen, and 100+ models via NIM microservices.',
    website: 'https://build.nvidia.com',
    apiUrl: 'https://build.nvidia.com/explore/discover',
    apiDocsUrl: 'https://docs.nvidia.com/nim/',
    icon: Icons.memory_rounded,
    color: Color(0xFF76B900),
    models: ['meta/llama-3.3-70b-instruct', 'deepseek-ai/deepseek-v3', 'mistralai/mistral-large-2-instruct', 'qwen/qwen2.5-72b-instruct'],
    pricing: 'Free trial credits + Enterprise plans',
    hasFree: true,
  ),
  _ProviderInfo(
    id: 'anthropic',
    name: 'Anthropic Claude',
    tagline: 'Most Intelligent for Long Context & Coding',
    description: 'Claude 3.5 Sonnet and Claude 3 Opus — the gold standard for coding, analysis, '
        'and structured reasoning. Massive 200K context window. Safest and most reliable.',
    website: 'https://claude.ai',
    apiUrl: 'https://console.anthropic.com/settings/keys',
    apiDocsUrl: 'https://docs.anthropic.com',
    icon: Icons.auto_stories_rounded,
    color: Color(0xFFD97757),
    models: ['claude-3-5-sonnet-20241022', 'claude-3-5-haiku-20241022', 'claude-3-opus-20240229'],
    pricing: 'Pay-per-token (no free tier)',
    hasFree: false,
  ),
  _ProviderInfo(
    id: 'openrouter',
    name: 'OpenRouter Cloud',
    tagline: 'Access 200+ Models via Single API Key',
    description: 'One API key, all frontier models. DeepSeek V3, Kimi K2, GPT-4o, Claude, Llama, '
        'Qwen, Gemma and 200+ more. Automatic fallback and cost optimization.',
    website: 'https://openrouter.ai',
    apiUrl: 'https://openrouter.ai/keys',
    apiDocsUrl: 'https://openrouter.ai/docs',
    icon: Icons.public_rounded,
    color: Color(0xFFA855F7),
    models: ['deepseek/deepseek-chat-v3-0324', 'moonshotai/kimi-k2', 'openai/gpt-4o', 'google/gemini-2.0-flash-exp'],
    pricing: 'Pay-per-token, many free models',
    hasFree: true,
  ),
  _ProviderInfo(
    id: 'ollama_local',
    name: 'Ollama (Local)',
    tagline: 'Run AI Completely Offline on Your Device',
    description: 'Download and run open-source models directly on your machine. '
        'Complete privacy — no data leaves your device. Supports Llama 3, Mistral, Gemma, Phi, DeepSeek.',
    website: 'https://ollama.com',
    apiUrl: 'https://ollama.com/download',
    apiDocsUrl: 'https://github.com/ollama/ollama',
    icon: Icons.computer_rounded,
    color: Color(0xFF38A169),
    models: ['llama3.3:70b', 'mistral:7b', 'gemma3:27b', 'deepseek-r1:14b', 'phi4:14b'],
    pricing: '100% Free — runs locally',
    hasFree: true,
  ),
  _ProviderInfo(
    id: 'ollama_cloud',
    name: 'Ollama Cloud',
    tagline: 'Open Models in the Cloud — No Setup',
    description: 'Access Ollama-compatible open models via cloud API. No local GPU needed. '
        'Great for using Llama, Mistral and other open models without local hardware.',
    website: 'https://ollama.com',
    apiUrl: 'https://ollama.com/cloud',
    apiDocsUrl: 'https://github.com/ollama/ollama/blob/main/docs/api.md',
    icon: Icons.cloud_queue_rounded,
    color: Color(0xFF38A169),
    models: ['llama3.3:70b', 'mistral-nemo', 'gemma3:27b'],
    pricing: 'Free tier available',
    hasFree: true,
  ),
  _ProviderInfo(
    id: 'llamacpp',
    name: 'llama.cpp Server',
    tagline: 'Ultra-Fast Inference with GGUF Models',
    description: 'Self-hosted llama.cpp OpenAI-compatible server. Run any GGUF model '
        'with maximum efficiency. Perfect for power users with local GPU/CPU.',
    website: 'https://github.com/ggml-org/llama.cpp',
    apiUrl: 'https://github.com/ggml-org/llama.cpp/blob/master/examples/server/README.md',
    apiDocsUrl: 'https://github.com/ggml-org/llama.cpp',
    icon: Icons.developer_board_rounded,
    color: Color(0xFFED8936),
    models: ['Any GGUF model', 'Llama 3.3', 'Mistral 7B', 'DeepSeek R1'],
    pricing: '100% Free — self-hosted',
    hasFree: true,
  ),
];

class AIProvidersScreen extends StatefulWidget {
  const AIProvidersScreen({super.key});

  @override
  State<AIProvidersScreen> createState() => _AIProvidersScreenState();
}

class _AIProvidersScreenState extends State<AIProvidersScreen> {
  int _selectedIndex = -1;

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JarvisColors.bg,
      body: CustomScrollView(
        slivers: [
          // ── App Bar ──────────────────────────────────
          SliverAppBar(
            pinned: true,
            expandedHeight: 140,
            backgroundColor: JarvisColors.surface,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: JarvisColors.textPrimary),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              title: ShaderMask(
                shaderCallback: (b) => JarvisColors.primaryGradient.createShader(b),
                child: const Text(
                  'AI Providers',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 20),
                ),
              ),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF0D0D1A), Color(0xFF12122A)],
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 20),
                      ShaderMask(
                        shaderCallback: (b) => JarvisColors.primaryGradient.createShader(b),
                        child: const Icon(Icons.hub_rounded, size: 36, color: Colors.white),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '7 Providers · 200+ Models',
                        style: TextStyle(color: JarvisColors.textMuted, fontSize: 12, letterSpacing: 1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(0.5),
              child: Divider(height: 0.5, color: JarvisColors.border),
            ),
          ),

          // ── Banner ────────────────────────────────────
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    JarvisColors.accentPrimary.withValues(alpha: 0.15),
                    JarvisColors.accentSecondary.withValues(alpha: 0.08),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: JarvisColors.accentPrimary.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.tips_and_updates_rounded, color: JarvisColors.accentSecondary, size: 20),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Tap a provider to get your API key. Add keys in Settings → AI Providers.',
                      style: TextStyle(color: JarvisColors.textSecondary, fontSize: 13, height: 1.4),
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.2, end: 0),
          ),

          // ── Provider Cards ────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final p = _providers[index];
                  final isSelected = _selectedIndex == index;
                  return _ProviderCard(
                    provider: p,
                    isExpanded: isSelected,
                    index: index,
                    onTap: () => setState(() => _selectedIndex = isSelected ? -1 : index),
                    onGetKey: () => _launch(p.apiUrl),
                    onViewDocs: () => _launch(p.apiDocsUrl),
                    onVisitSite: () => _launch(p.website),
                  );
                },
                childCount: _providers.length,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProviderCard extends StatelessWidget {
  final _ProviderInfo provider;
  final bool isExpanded;
  final int index;
  final VoidCallback onTap;
  final VoidCallback onGetKey;
  final VoidCallback onViewDocs;
  final VoidCallback onVisitSite;

  const _ProviderCard({
    required this.provider,
    required this.isExpanded,
    required this.index,
    required this.onTap,
    required this.onGetKey,
    required this.onViewDocs,
    required this.onVisitSite,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isExpanded ? JarvisColors.surfaceElevated : JarvisColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isExpanded
              ? provider.color.withValues(alpha: 0.5)
              : JarvisColors.border,
          width: isExpanded ? 1.5 : 0.5,
        ),
        boxShadow: isExpanded
            ? [BoxShadow(color: provider.color.withValues(alpha: 0.1), blurRadius: 20, spreadRadius: 2)]
            : [],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ────────────────────────────
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: provider.color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: provider.color.withValues(alpha: 0.4), width: 0.5),
                      ),
                      child: Icon(provider.icon, color: provider.color, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                provider.name,
                                style: const TextStyle(
                                  color: JarvisColors.textPrimary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (provider.hasFree) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: JarvisColors.success.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text('FREE',
                                      style: TextStyle(color: JarvisColors.success, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            provider.tagline,
                            style: const TextStyle(color: JarvisColors.textMuted, fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: isExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 300),
                      child: const Icon(Icons.expand_more_rounded, color: JarvisColors.textMuted, size: 20),
                    ),
                  ],
                ),
              ),

              // ── Expanded Details ──────────────────
              if (isExpanded) ...[
                Divider(height: 1, color: provider.color.withValues(alpha: 0.2)),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Description
                      Text(
                        provider.description,
                        style: const TextStyle(color: JarvisColors.textSecondary, fontSize: 13, height: 1.5),
                      ),
                      const SizedBox(height: 16),

                      // Pricing badge
                      Row(
                        children: [
                          const Icon(Icons.monetization_on_rounded, color: JarvisColors.warning, size: 14),
                          const SizedBox(width: 6),
                          Text(provider.pricing,
                              style: const TextStyle(color: JarvisColors.warning, fontSize: 12, fontWeight: FontWeight.w500)),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Models
                      const Text('TOP MODELS', style: TextStyle(color: JarvisColors.textMuted, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: provider.models.map((m) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: provider.color.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: provider.color.withValues(alpha: 0.25), width: 0.5),
                          ),
                          child: Text(m, style: TextStyle(color: provider.color, fontSize: 11, fontWeight: FontWeight.w500)),
                        )).toList(),
                      ),
                      const SizedBox(height: 20),

                      // Action buttons
                      Row(
                        children: [
                          Expanded(
                            child: _ActionBtn(
                              label: 'Get API Key',
                              icon: Icons.vpn_key_rounded,
                              color: provider.color,
                              onTap: onGetKey,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _ActionBtn(
                              label: 'View Docs',
                              icon: Icons.menu_book_rounded,
                              color: JarvisColors.accentSecondary,
                              outline: true,
                              onTap: onViewDocs,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _ActionBtn(
                            label: '',
                            icon: Icons.open_in_new_rounded,
                            color: JarvisColors.textMuted,
                            outline: true,
                            onTap: onVisitSite,
                            compact: true,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ).animate(delay: Duration(milliseconds: 60 * index)).fadeIn(duration: 350.ms).slideY(begin: 0.1, end: 0);
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool outline;
  final bool compact;

  const _ActionBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.outline = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 12),
        decoration: BoxDecoration(
          color: outline ? Colors.transparent : color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: outline ? color.withValues(alpha: 0.4) : color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: outline ? color : color, size: 15),
            if (!compact && label.isNotEmpty) ...[
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: outline ? color : color, fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ],
        ),
      ),
    );
  }
}
