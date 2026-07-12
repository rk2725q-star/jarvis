import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/netless_service.dart';
import '../../theme/jarvis_theme.dart';

/// Full-screen management panel for the Netless (offline) Gemma model.
/// Accessible from Settings → Netless.
class NetlessManagementScreen extends StatefulWidget {
  const NetlessManagementScreen({super.key});

  @override
  State<NetlessManagementScreen> createState() =>
      _NetlessManagementScreenState();
}

class _NetlessManagementScreenState extends State<NetlessManagementScreen>
    with TickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnim = Tween(
      begin: 0.6,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    // Init service
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NetlessService().init();
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A14),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white70,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Netless AI',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: ChangeNotifierProvider.value(
        value: NetlessService(),
        child: Consumer<NetlessService>(
          builder: (context, svc, _) => ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // ── Hero card ────────────────────────────────────────────────
              _HeroCard(svc: svc, pulseAnim: _pulseAnim),
              const SizedBox(height: 20),

              // ── Status card ───────────────────────────────────────────────
              _StatusCard(svc: svc),
              const SizedBox(height: 20),

              // ── Download progress (visible while downloading) ─────────────
              if (svc.isDownloading) ...[
                _DownloadProgressCard(svc: svc),
                const SizedBox(height: 20),
              ],

              // ── Action buttons ────────────────────────────────────────────
              _ActionButtons(svc: svc),
              const SizedBox(height: 24),

              // ── Info cards ────────────────────────────────────────────────
              _InfoSection(svc: svc),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Hero card ──────────────────────────────────────────────────────────────
class _HeroCard extends StatelessWidget {
  final NetlessService svc;
  final Animation<double> pulseAnim;
  const _HeroCard({required this.svc, required this.pulseAnim});

  @override
  Widget build(BuildContext context) {
    final isReady = svc.isAvailable;
    final color = isReady ? const Color(0xFF00E676) : const Color(0xFF7B5FFF);

    return AnimatedBuilder(
      animation: pulseAnim,
      builder: (ctx, child) => Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color.withValues(alpha: 0.18), const Color(0xFF1A1A2E)],
          ),
          border: Border.all(
            color: color.withValues(
              alpha: isReady ? 0.5 * pulseAnim.value : 0.3,
            ),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.12 * pulseAnim.value),
              blurRadius: 32,
              spreadRadius: 4,
            ),
          ],
        ),
        child: Column(
          children: [
            // Icon
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.15),
                border: Border.all(
                  color: color.withValues(alpha: 0.5),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.3 * pulseAnim.value),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Icon(
                isReady
                    ? Icons.hub_rounded
                    : svc.isDownloading
                    ? Icons.download_rounded
                    : Icons.wifi_off_rounded,
                color: color,
                size: 34,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isReady
                  ? 'Netless Active'
                  : svc.isDownloading
                  ? 'Downloading…'
                  : 'Netless Offline AI',
              style: TextStyle(
                color: color,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Gemma 4 E2B-it · Google · On-Device',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: Text(
                isReady ? '🟢 ONLINE & OFFLINE' : '⚫ NOT LOADED',
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Status card ────────────────────────────────────────────────────────────
class _StatusCard extends StatelessWidget {
  final NetlessService svc;
  const _StatusCard({required this.svc});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF12121E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: JarvisColors.accentPrimary,
            size: 18,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              svc.status,
              style: const TextStyle(color: Color(0xFFB0B0C8), fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Download progress card ─────────────────────────────────────────────────
class _DownloadProgressCard extends StatelessWidget {
  final NetlessService svc;
  const _DownloadProgressCard({required this.svc});

  @override
  Widget build(BuildContext context) {
    final pct = (svc.downloadProgress * 100).toInt();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF12121E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: JarvisColors.accentPrimary.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Downloading Gemma 4 E2B-it',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              Text(
                '$pct%',
                style: TextStyle(
                  color: JarvisColors.accentPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: svc.downloadProgress,
              minHeight: 10,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor: AlwaysStoppedAnimation(JarvisColors.accentPrimary),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                Icons.notifications_active_rounded,
                size: 14,
                color: JarvisColors.accentPrimary,
              ),
              const SizedBox(width: 6),
              const Text(
                'Progress also visible in notification bar',
                style: TextStyle(color: Color(0xFF7070A0), fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Action buttons ─────────────────────────────────────────────────────────
class _ActionButtons extends StatelessWidget {
  final NetlessService svc;
  const _ActionButtons({required this.svc});

  @override
  Widget build(BuildContext context) {
    final hasFile = svc.modelPath != null && File(svc.modelPath!).existsSync();

    return Column(
      children: [
        // Download button (shown when no file)
        if (!hasFile && !svc.isDownloading)
          _BigButton(
            icon: Icons.download_rounded,
            label: 'Download Netless (~1.5 GB)',
            subtitle: 'Wi-Fi recommended. Download once, use forever.',
            color: const Color(0xFF00E676),
            onTap: () => svc.downloadAndLoad(),
          ),

        // Cancel / downloading indicator
        if (svc.isDownloading)
          _BigButton(
            icon: Icons.hourglass_top_rounded,
            label: 'Downloading…',
            subtitle: svc.status,
            color: JarvisColors.accentPrimary,
            onTap: null, // can't cancel yet
          ),

        // Load button (file exists, model not loaded)
        if (hasFile && !svc.isLoaded && !svc.isLoading && !svc.isDownloading)
          _BigButton(
            icon: Icons.play_circle_rounded,
            label: 'Load Model',
            subtitle: 'Load Gemma into memory to use offline.',
            color: JarvisColors.accentPrimary,
            onTap: () => svc.loadModel(),
          ),

        // Loading indicator
        if (svc.isLoading)
          _BigButton(
            icon: Icons.memory_rounded,
            label: 'Loading model…',
            subtitle: svc.status,
            color: JarvisColors.accentPrimary,
            onTap: null,
          ),

        // Unload button (model is loaded)
        if (svc.isLoaded) ...[
          _BigButton(
            icon: Icons.stop_circle_rounded,
            label: 'Unload Model',
            subtitle: 'Free RAM. File stays — reload anytime.',
            color: const Color(0xFFFF9800),
            onTap: () => _confirmAction(
              context,
              title: 'Unload Model?',
              body:
                  'This will free up RAM. The model file stays on your device. '
                  'You can reload it anytime.',
              confirmLabel: 'Unload',
              confirmColor: const Color(0xFFFF9800),
              onConfirm: () => svc.unloadModel(),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Delete button (file exists)
        if (hasFile && !svc.isDownloading) ...[
          const SizedBox(height: 12),
          _BigButton(
            icon: Icons.delete_outline_rounded,
            label: 'Delete Model File',
            subtitle: 'Remove from storage (~1.5 GB freed).',
            color: const Color(0xFFFF5252),
            onTap: () => _confirmAction(
              context,
              title: 'Delete Model?',
              body:
                  'This will delete the Gemma 4 E2B-it file (~1.5 GB) from your device. '
                  'You will need to download it again to use Netless.',
              confirmLabel: 'Delete',
              confirmColor: const Color(0xFFFF5252),
              onConfirm: () => svc.deleteModel(),
            ),
          ),
        ],
      ],
    );
  }

  void _confirmAction(
    BuildContext context, {
    required String title,
    required String body,
    required String confirmLabel,
    required Color confirmColor,
    required VoidCallback onConfirm,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          body,
          style: const TextStyle(color: Color(0xFFB0B0C8), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF7070A0)),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: confirmColor,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              onConfirm();
            },
            child: Text(
              confirmLabel,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

class _BigButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;
  const _BigButton({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: onTap != null
              ? color.withValues(alpha: 0.1)
              : Colors.white.withValues(alpha: 0.04),
          border: Border.all(
            color: onTap != null
                ? color.withValues(alpha: 0.4)
                : Colors.white.withValues(alpha: 0.07),
            width: 1.2,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.15),
              ),
              child: onTap == null
                  ? Padding(
                      padding: const EdgeInsets.all(10),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(color),
                      ),
                    )
                  : Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: onTap != null ? Colors.white : Colors.white54,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFF7070A0),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (onTap != null)
              Icon(
                Icons.chevron_right_rounded,
                color: color.withValues(alpha: 0.6),
                size: 22,
              ),
          ],
        ),
      ),
    );
  }
}

// ── Info section ────────────────────────────────────────────────────────────
class _InfoSection extends StatelessWidget {
  final NetlessService svc;
  const _InfoSection({required this.svc});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            'MODEL DETAILS',
            style: TextStyle(
              color: Color(0xFF5050A0),
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.4,
            ),
          ),
        ),
        _infoTile(Icons.science_rounded, 'Model', 'Gemma 4 E2B-it (Google)'),
        _infoTile(Icons.storage_rounded, 'Storage', svc.storageInfo),
        _infoTile(Icons.memory_rounded, 'Format', 'LiteRT Task (on-device)'),
        _infoTile(
          Icons.wifi_off_rounded,
          'Connectivity',
          'Zero internet required after download',
        ),
        _infoTile(
          Icons.security_rounded,
          'Privacy',
          '100% on-device — no data leaves your phone',
        ),
        _infoTile(
          Icons.speed_rounded,
          'Backend',
          'GPU preferred, CPU fallback',
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF00E676).withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFF00E676).withValues(alpha: 0.2),
            ),
          ),
          child: const Row(
            children: [
              Icon(
                Icons.tips_and_updates_rounded,
                color: Color(0xFF00E676),
                size: 20,
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Tip: Download on Wi-Fi. Once done, JARVIS works even in airplane mode!',
                  style: TextStyle(color: Color(0xFFB0B0C8), fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _infoTile(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF12121E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Row(
          children: [
            Icon(icon, color: JarvisColors.accentPrimary, size: 16),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(color: Color(0xFF7070A0), fontSize: 13),
            ),
            const Spacer(),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.end,
            ),
          ],
        ),
      ),
    );
  }
}
