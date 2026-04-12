import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:jarvis_ai/theme/jarvis_theme.dart';
import 'package:open_filex/open_filex.dart';
import 'jarvis_file_viewer.dart';

// ─── Data model ──────────────────────────────────────────────────────────────
class _RecentFile {
  final String path;
  final String name;
  final DateTime openedAt;
  final int sizeBytes;

  _RecentFile({required this.path, required this.name, required this.openedAt, required this.sizeBytes});

  Map<String, dynamic> toJson() => {
    'path': path, 'name': name,
    'openedAt': openedAt.toIso8601String(), 'sizeBytes': sizeBytes,
  };

  factory _RecentFile.fromJson(Map<String, dynamic> j) => _RecentFile(
    path: j['path'], name: j['name'],
    openedAt: DateTime.parse(j['openedAt']), sizeBytes: j['sizeBytes'] ?? 0,
  );
}

// ─── File type helpers ────────────────────────────────────────────────────────
String _fileCategory(String name) {
  final ext = name.split('.').last.toLowerCase();
  if (['pdf'].contains(ext)) return 'PDF';
  if (['doc', 'docx', 'txt', 'md'].contains(ext)) return 'Docs';
  if (['xls', 'xlsx', 'csv'].contains(ext)) return 'Sheets';
  if (['ppt', 'pptx'].contains(ext)) return 'Slides';
  if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext)) return 'Images';
  if (['dart', 'py', 'js', 'ts', 'kt', 'java', 'swift', 'go', 'rs', 'cpp', 'c', 'html', 'css'].contains(ext)) return 'Code';
  if (['json', 'xml', 'yaml', 'yml'].contains(ext)) return 'Data';
  return 'All';
}

Color _fileColor(String name) {
  final cat = _fileCategory(name);
  switch (cat) {
    case 'PDF': return const Color(0xFFFC5555);
    case 'Docs': return const Color(0xFF4285F4);
    case 'Sheets': return const Color(0xFF34A853);
    case 'Slides': return const Color(0xFFFBBC05);
    case 'Images': return const Color(0xFF8B5CF6);
    case 'Code': return const Color(0xFF00D4FF);
    case 'Data': return const Color(0xFFF59E0B);
    default: return JarvisColors.textMuted;
  }
}

IconData _fileIcon(String name) {
  final cat = _fileCategory(name);
  switch (cat) {
    case 'PDF': return Icons.picture_as_pdf_rounded;
    case 'Docs': return Icons.description_rounded;
    case 'Sheets': return Icons.table_chart_rounded;
    case 'Slides': return Icons.slideshow_rounded;
    case 'Images': return Icons.image_rounded;
    case 'Code': return Icons.code_rounded;
    case 'Data': return Icons.data_object_rounded;
    default: return Icons.insert_drive_file_rounded;
  }
}

String _formatSize(int bytes) {
  if (bytes < 1024) return '${bytes}B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
}

String _timeAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${dt.day}/${dt.month}/${dt.year}';
}

// ─── Main Screen ─────────────────────────────────────────────────────────────
class JarvisFileHub extends StatefulWidget {
  const JarvisFileHub({super.key});

  @override
  State<JarvisFileHub> createState() => _JarvisFileHubState();
}

class _JarvisFileHubState extends State<JarvisFileHub> with SingleTickerProviderStateMixin {
  List<_RecentFile> _recent = [];
  String _selectedCategory = 'All';
  late TabController _tabController;

  static const _categories = ['All', 'PDF', 'Docs', 'Sheets', 'Slides', 'Images', 'Code', 'Data'];
  static const _prefsKey = 'jarvis_recent_files';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _categories.length, vsync: this);
    _loadRecent();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey) ?? [];
    setState(() {
      _recent = raw
          .map((s) {
            try { return _RecentFile.fromJson(json.decode(s)); } catch (_) { return null; }
          })
          .whereType<_RecentFile>()
          .where((f) => File(f.path).existsSync())
          .toList()
        ..sort((a, b) => b.openedAt.compareTo(a.openedAt));
    });
  }

  Future<void> _addRecent(String path) async {
    final file = File(path);
    if (!file.existsSync()) return;
    final stat = file.statSync();
    final name = path.split(Platform.pathSeparator).last;
    final entry = _RecentFile(path: path, name: name, openedAt: DateTime.now(), sizeBytes: stat.size);
    _recent.removeWhere((f) => f.path == path);
    _recent.insert(0, entry);
    if (_recent.length > 30) _recent = _recent.sublist(0, 30);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, _recent.map((f) => json.encode(f.toJson())).toList());
    setState(() {});
  }

  Future<void> _removeRecent(String path) async {
    _recent.removeWhere((f) => f.path == path);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, _recent.map((f) => json.encode(f.toJson())).toList());
    setState(() {});
  }

  void _openFile(String path) async {
    await _addRecent(path);
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => JarvisFileViewer(filePath: path)));
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: false, type: FileType.any);
    if (result != null && result.paths.isNotEmpty) {
      final path = result.paths.first;
      if (path != null) _openFile(path);
    }
  }

  List<_RecentFile> get _filtered {
    if (_selectedCategory == 'All') return _recent;
    return _recent.where((f) => _fileCategory(f.name) == _selectedCategory).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JarvisColors.bg,
      body: CustomScrollView(
        slivers: [
          // ── App Bar ─────────────────────────────────
          SliverAppBar(
            pinned: true,
            expandedHeight: 120,
            backgroundColor: JarvisColors.surface,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: JarvisColors.textPrimary),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.add_rounded, color: JarvisColors.accentPrimary),
                tooltip: 'Import File',
                onPressed: _pickFile,
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              title: ShaderMask(
                shaderCallback: (b) => JarvisColors.primaryGradient.createShader(b),
                child: const Text('File Hub', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 20)),
              ),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0D0D1A), Color(0xFF12122A)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(0.5),
              child: Divider(height: 0.5, color: JarvisColors.border),
            ),
          ),

          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Quick Actions ──────────────────────
                _buildQuickActions(),

                // ── JARVIS Suggestion ──────────────────
                if (_recent.isNotEmpty) _buildJarvisSuggestion(),

                // ── Category Tabs ──────────────────────
                _buildCategoryTabs(),

                const SizedBox(height: 4),
              ],
            ),
          ),

          // ── File Grid ─────────────────────────────
          _filtered.isEmpty
              ? SliverToBoxAdapter(child: _buildEmptyState())
              : SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.1,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => _FileCard(
                        file: _filtered[i],
                        index: i,
                        onTap: () => _openFile(_filtered[i].path),
                        onDelete: () => _removeRecent(_filtered[i].path),
                        onAskJarvis: () {
                          _openFile(_filtered[i].path);
                        },
                      ),
                      childCount: _filtered.length,
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          _QuickActionBtn(icon: Icons.upload_file_rounded, label: 'Import File', color: JarvisColors.accentPrimary, onTap: _pickFile),
          const SizedBox(width: 10),
          _QuickActionBtn(icon: Icons.auto_awesome_rounded, label: 'Ask JARVIS', color: JarvisColors.accentSecondary, onTap: () {
            Navigator.pop(context);
          }),
        ],
      ),
    );
  }

  Widget _buildJarvisSuggestion() {
    final f = _recent.first;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [JarvisColors.accentPrimary.withValues(alpha: 0.12), JarvisColors.accentSecondary.withValues(alpha: 0.05)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: JarvisColors.accentPrimary.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          ShaderMask(
            shaderCallback: (b) => JarvisColors.primaryGradient.createShader(b),
            child: const Icon(Icons.auto_awesome_rounded, size: 18, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('JARVIS SUGGESTS', style: TextStyle(color: JarvisColors.accentPrimary, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1)),
                const SizedBox(height: 2),
                Text(
                  'You opened "${f.name}" recently — want me to analyze it?',
                  style: const TextStyle(color: JarvisColors.textSecondary, fontSize: 12),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _openFile(f.path),
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            child: const Text('Open', style: TextStyle(color: JarvisColors.accentPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.2, end: 0);
  }

  Widget _buildCategoryTabs() {
    return SizedBox(
      height: 36,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _categories.length,
        itemBuilder: (_, i) {
          final cat = _categories[i];
          final selected = cat == _selectedCategory;
          return GestureDetector(
            onTap: () => setState(() => _selectedCategory = cat),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: selected ? JarvisColors.accentPrimary : JarvisColors.surfaceElevated,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: selected ? JarvisColors.accentPrimary : JarvisColors.border),
              ),
              child: Text(
                cat,
                style: TextStyle(
                  color: selected ? Colors.white : JarvisColors.textSecondary,
                  fontSize: 12, fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 32),
      child: Column(
        children: [
          ShaderMask(
            shaderCallback: (b) => JarvisColors.primaryGradient.createShader(b),
            child: const Icon(Icons.folder_open_rounded, size: 64, color: Colors.white),
          ).animate().scale(begin: const Offset(0.5, 0.5), duration: 500.ms, curve: Curves.elasticOut),
          const SizedBox(height: 16),
          const Text('No Files Yet', style: TextStyle(color: JarvisColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text('Import a file to chat with JARVIS about it.', style: TextStyle(color: JarvisColors.textMuted, fontSize: 13), textAlign: TextAlign.center),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _pickFile,
            icon: const Icon(Icons.upload_file_rounded, size: 18),
            label: const Text('Import File'),
            style: ElevatedButton.styleFrom(
              backgroundColor: JarvisColors.accentPrimary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────


class _QuickActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionBtn({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

class _FileCard extends StatelessWidget {
  final _RecentFile file;
  final int index;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onAskJarvis;

  const _FileCard({required this.file, required this.index, required this.onTap, required this.onDelete, required this.onAskJarvis});

  @override
  Widget build(BuildContext context) {
    final color = _fileColor(file.name);
    final icon = _fileIcon(file.name);

    return GestureDetector(
      onTap: onTap,
      onLongPress: () => _showActions(context),
      child: Container(
        decoration: BoxDecoration(
          color: JarvisColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: JarvisColors.border, width: 0.5),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.05), blurRadius: 12)],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Icon + type badge
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(_fileCategory(file.name), style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              // File name
              Text(
                file.name,
                style: const TextStyle(color: JarvisColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                maxLines: 2, overflow: TextOverflow.ellipsis,
              ),
              // Meta info
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_formatSize(file.sizeBytes), style: const TextStyle(color: JarvisColors.textMuted, fontSize: 10)),
                  Text(_timeAgo(file.openedAt), style: const TextStyle(color: JarvisColors.textMuted, fontSize: 10)),
                ],
              ),
            ],
          ),
        ),
      ),
    ).animate(delay: Duration(milliseconds: 50 * index)).fadeIn(duration: 300.ms).slideY(begin: 0.1, end: 0);
  }

  void _showActions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: JarvisColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 36, height: 4, margin: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: JarvisColors.border, borderRadius: BorderRadius.circular(2))),
            Text(file.name, style: const TextStyle(color: JarvisColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.auto_awesome_rounded, color: JarvisColors.accentPrimary),
              title: const Text('Ask JARVIS About This', style: TextStyle(color: Colors.white)),
              onTap: () { Navigator.pop(context); onAskJarvis(); },
            ),
            ListTile(
              leading: const Icon(Icons.open_in_new_rounded, color: JarvisColors.textSecondary),
              title: const Text('Open Externally', style: TextStyle(color: Colors.white)),
              onTap: () { Navigator.pop(context); OpenFilex.open(file.path); },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: JarvisColors.error),
              title: const Text('Remove from History', style: TextStyle(color: JarvisColors.error)),
              onTap: () { Navigator.pop(context); onDelete(); },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
