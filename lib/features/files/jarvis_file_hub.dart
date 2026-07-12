// ignore_for_file: deprecated_member_use
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:convert';
import 'package:jarvis_ai/theme/jarvis_theme.dart';
import 'package:open_filex/open_filex.dart';
import 'jarvis_file_viewer.dart';

// ─── Data model ──────────────────────────────────────────────────────────────
class _RecentFile {
  final String path;
  String name;
  String notes;
  final DateTime openedAt;
  final int sizeBytes;
  List<int> pageOrder; // for page sorting

  _RecentFile({
    required this.path,
    required this.name,
    this.notes = '',
    required this.openedAt,
    required this.sizeBytes,
    List<int>? pageOrder,
  }) : pageOrder = pageOrder ?? [];

  Map<String, dynamic> toJson() => {
    'path': path,
    'name': name,
    'notes': notes,
    'openedAt': openedAt.toIso8601String(),
    'sizeBytes': sizeBytes,
    'pageOrder': pageOrder,
  };

  factory _RecentFile.fromJson(Map<String, dynamic> j) => _RecentFile(
    path: j['path'],
    name: j['name'] ?? '',
    notes: j['notes'] ?? '',
    openedAt: DateTime.parse(j['openedAt']),
    sizeBytes: j['sizeBytes'] ?? 0,
    pageOrder: (j['pageOrder'] as List?)?.cast<int>() ?? [],
  );
}

// ─── File type helpers ────────────────────────────────────────────────────────
String _fileCategory(String name) {
  final ext = name.split('.').last.toLowerCase();
  if (['pdf'].contains(ext)) return 'PDF';
  if (['doc', 'docx', 'txt', 'md'].contains(ext)) return 'Docs';
  if (['xls', 'xlsx', 'csv'].contains(ext)) return 'Sheets';
  if (['ppt', 'pptx'].contains(ext)) return 'Slides';
  if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic'].contains(ext)) {
    return 'Images';
  }
  if ([
    'dart',
    'py',
    'js',
    'ts',
    'kt',
    'java',
    'swift',
    'go',
    'rs',
    'cpp',
    'c',
    'html',
    'css',
  ].contains(ext)) {
    return 'Code';
  }
  if (['json', 'xml', 'yaml', 'yml'].contains(ext)) return 'Data';
  return 'All';
}

Color _fileColor(String name) {
  switch (_fileCategory(name)) {
    case 'PDF':
      return const Color(0xFFFC5555);
    case 'Docs':
      return const Color(0xFF4285F4);
    case 'Sheets':
      return const Color(0xFF34A853);
    case 'Slides':
      return const Color(0xFFFBBC05);
    case 'Images':
      return const Color(0xFF8B5CF6);
    case 'Code':
      return const Color(0xFF00D4FF);
    case 'Data':
      return const Color(0xFFF59E0B);
    default:
      return JarvisColors.textMuted;
  }
}

IconData _fileIcon(String name) {
  switch (_fileCategory(name)) {
    case 'PDF':
      return Icons.picture_as_pdf_rounded;
    case 'Docs':
      return Icons.description_rounded;
    case 'Sheets':
      return Icons.table_chart_rounded;
    case 'Slides':
      return Icons.slideshow_rounded;
    case 'Images':
      return Icons.image_rounded;
    case 'Code':
      return Icons.code_rounded;
    case 'Data':
      return Icons.data_object_rounded;
    default:
      return Icons.insert_drive_file_rounded;
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

bool _canSortPages(String name) {
  final ext = name.split('.').last.toLowerCase();
  return ['pdf', 'docx', 'doc'].contains(ext);
}

// ─── Main Screen ─────────────────────────────────────────────────────────────
class JarvisFileHub extends StatefulWidget {
  const JarvisFileHub({super.key});

  @override
  State<JarvisFileHub> createState() => _JarvisFileHubState();
}

class _JarvisFileHubState extends State<JarvisFileHub>
    with TickerProviderStateMixin {
  List<_RecentFile> _recent = [];
  String _selectedCategory = 'All';
  bool _isListView = false;
  late AnimationController _fabAnim;

  static const _categories = [
    'All',
    'PDF',
    'Docs',
    'Sheets',
    'Slides',
    'Images',
    'Code',
    'Data',
  ];
  static const _prefsKey = 'jarvis_recent_files_v2';

  @override
  void initState() {
    super.initState();
    _fabAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _loadRecent();
  }

  @override
  void dispose() {
    _fabAnim.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey) ?? [];
    setState(() {
      _recent =
          raw
              .map((s) {
                try {
                  return _RecentFile.fromJson(json.decode(s));
                } catch (_) {
                  return null;
                }
              })
              .whereType<_RecentFile>()
              .where((f) => File(f.path).existsSync())
              .toList()
            ..sort((a, b) => b.openedAt.compareTo(a.openedAt));
    });
  }

  Future<void> _saveRecent() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _prefsKey,
      _recent.map((f) => json.encode(f.toJson())).toList(),
    );
  }

  Future<void> _addRecent(String path) async {
    final file = File(path);
    if (!file.existsSync()) return;
    final stat = file.statSync();
    final name = path.split(Platform.pathSeparator).last;
    // Check if already exists — update timestamp
    final existIdx = _recent.indexWhere((f) => f.path == path);
    if (existIdx >= 0) {
      final existing = _recent.removeAt(existIdx);
      _recent.insert(
        0,
        _RecentFile(
          path: path,
          name: existing.name,
          notes: existing.notes,
          openedAt: DateTime.now(),
          sizeBytes: stat.size,
          pageOrder: existing.pageOrder,
        ),
      );
    } else {
      _recent.insert(
        0,
        _RecentFile(
          path: path,
          name: name,
          openedAt: DateTime.now(),
          sizeBytes: stat.size,
        ),
      );
      if (_recent.length > 50) _recent = _recent.sublist(0, 50);
    }
    await _saveRecent();
    setState(() {});
  }

  Future<void> _removeRecent(String path) async {
    _recent.removeWhere((f) => f.path == path);
    await _saveRecent();
    setState(() {});
  }

  Future<void> _updateNote(String path, String note) async {
    final idx = _recent.indexWhere((f) => f.path == path);
    if (idx < 0) return;
    final old = _recent[idx];
    _recent[idx] = _RecentFile(
      path: old.path,
      name: old.name,
      notes: note,
      openedAt: old.openedAt,
      sizeBytes: old.sizeBytes,
      pageOrder: old.pageOrder,
    );
    await _saveRecent();
  }

  Future<void> _updateName(String path, String newName) async {
    final idx = _recent.indexWhere((f) => f.path == path);
    if (idx < 0) return;
    final old = _recent[idx];
    _recent[idx] = _RecentFile(
      path: old.path,
      name: newName.isEmpty ? old.name : newName,
      notes: old.notes,
      openedAt: old.openedAt,
      sizeBytes: old.sizeBytes,
      pageOrder: old.pageOrder,
    );
    await _saveRecent();
    setState(() {});
  }

  void _openFile(String path) async {
    await _addRecent(path);
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => JarvisFileViewer(filePath: path)),
    );
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.any,
    );
    if (result != null) {
      for (final path in result.paths.whereType<String>()) {
        await _addRecent(path);
      }
    }
  }

  Future<void> _pickImages() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.image,
    );
    if (result != null) {
      for (final path in result.paths.whereType<String>()) {
        await _addRecent(path);
      }
    }
  }

  Future<void> _shareFile(String path) async {
    final file = File(path);
    if (!file.existsSync()) return;
    await Share.shareXFiles(
      [XFile(path)],
      text: 'Shared from JARVIS AI',
      subject: path.split(Platform.pathSeparator).last,
    );
  }

  List<_RecentFile> get _filtered {
    if (_selectedCategory == 'All') return _recent;
    return _recent
        .where((f) => _fileCategory(f.name) == _selectedCategory)
        .toList();
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
              icon: const Icon(
                Icons.arrow_back_rounded,
                color: JarvisColors.textPrimary,
              ),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              IconButton(
                icon: Icon(
                  _isListView
                      ? Icons.grid_view_rounded
                      : Icons.view_list_rounded,
                  color: JarvisColors.textSecondary,
                ),
                tooltip: 'Toggle View',
                onPressed: () => setState(() => _isListView = !_isListView),
              ),
              IconButton(
                icon: const Icon(
                  Icons.add_rounded,
                  color: JarvisColors.accentPrimary,
                ),
                tooltip: 'Import Files',
                onPressed: _pickFiles,
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              title: ShaderMask(
                shaderCallback: (b) =>
                    JarvisColors.primaryGradient.createShader(b),
                child: const Text(
                  'File Hub',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                  ),
                ),
              ),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0D0D1A), Color(0xFF12122A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
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
                _buildQuickActions(),
                if (_recent.isNotEmpty) _buildJarvisSuggestion(),
                _buildCategoryTabs(),
                const SizedBox(height: 4),
              ],
            ),
          ),

          // ── File List / Grid ─────────────────────────────────
          _filtered.isEmpty
              ? SliverToBoxAdapter(child: _buildEmptyState())
              : _isListView
              ? _buildListView()
              : _buildGridView(),
        ],
      ),
      // ── FAB: upload ──
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _pickFiles,
        backgroundColor: JarvisColors.accentPrimary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.upload_file_rounded),
        label: const Text(
          'Import',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildGridView() {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.0,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, i) => _FileCard(
            file: _filtered[i],
            index: i,
            onTap: () => _openFile(_filtered[i].path),
            onDelete: () => _removeRecent(_filtered[i].path),
            onShare: () => _shareFile(_filtered[i].path),
            onEdit: () => _showInlineEditor(context, _filtered[i]),
            onSort: _canSortPages(_filtered[i].name)
                ? () => _showPageSorter(context, _filtered[i])
                : null,
          ),
          childCount: _filtered.length,
        ),
      ),
    );
  }

  Widget _buildListView() {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, i) => _FileListTile(
            file: _filtered[i],
            onTap: () => _openFile(_filtered[i].path),
            onDelete: () => _removeRecent(_filtered[i].path),
            onShare: () => _shareFile(_filtered[i].path),
            onEdit: () => _showInlineEditor(context, _filtered[i]),
            onSort: _canSortPages(_filtered[i].name)
                ? () => _showPageSorter(context, _filtered[i])
                : null,
          ),
          childCount: _filtered.length,
        ),
      ),
    );
  }

  // ── Inline Live Editor (no popup — opens a bottom sheet with live text fields)
  void _showInlineEditor(BuildContext context, _RecentFile file) {
    final nameCtrl = TextEditingController(text: file.name);
    final notesCtrl = TextEditingController(text: file.notes);
    bool saved = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: JarvisColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: JarvisColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Header
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _fileColor(file.name).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _fileIcon(file.name),
                      color: _fileColor(file.name),
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Live Edit',
                    style: TextStyle(
                      color: JarvisColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () async {
                      await _updateName(file.path, nameCtrl.text.trim());
                      await _updateNote(file.path, notesCtrl.text.trim());
                      saved = true;
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    style: TextButton.styleFrom(
                      backgroundColor: JarvisColors.accentPrimary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Save',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── File Display Name ───────────────────────
              const Text(
                'Display Name',
                style: TextStyle(
                  color: JarvisColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: nameCtrl,
                style: const TextStyle(
                  color: JarvisColors.textPrimary,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: JarvisColors.surfaceElevated,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: JarvisColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: JarvisColors.accentPrimary,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  hintText: 'Enter display name...',
                  hintStyle: const TextStyle(color: JarvisColors.textMuted),
                  suffixIcon: IconButton(
                    icon: const Icon(
                      Icons.clear_rounded,
                      color: JarvisColors.textMuted,
                      size: 18,
                    ),
                    onPressed: () => nameCtrl.clear(),
                  ),
                ),
                onChanged: (_) => setSheet(() {}),
              ),
              const SizedBox(height: 16),

              // ── Notes ────────────────────────────────────
              const Text(
                'Notes',
                style: TextStyle(
                  color: JarvisColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: notesCtrl,
                style: const TextStyle(
                  color: JarvisColors.textPrimary,
                  fontSize: 14,
                ),
                maxLines: 4,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: JarvisColors.surfaceElevated,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: JarvisColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: JarvisColors.accentPrimary,
                    ),
                  ),
                  contentPadding: const EdgeInsets.all(14),
                  hintText: 'Add notes about this file...',
                  hintStyle: const TextStyle(color: JarvisColors.textMuted),
                ),
              ),
              const SizedBox(height: 16),

              // ── Quick Actions ─────────────────────────────
              Row(
                children: [
                  if (_canSortPages(file.name))
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showPageSorter(context, file);
                        },
                        icon: const Icon(Icons.sort_rounded, size: 16),
                        label: const Text('Sort Pages'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: JarvisColors.accentPrimary,
                          side: const BorderSide(
                            color: JarvisColors.accentPrimary,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                  if (_canSortPages(file.name)) const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _shareFile(file.path);
                      },
                      icon: const Icon(Icons.share_rounded, size: 16),
                      label: const Text('Share'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: JarvisColors.textSecondary,
                        side: BorderSide(color: JarvisColors.border),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ).then((_) {
      if (!saved) {
        // Auto-save on dismiss too
        _updateName(file.path, nameCtrl.text.trim());
        _updateNote(file.path, notesCtrl.text.trim());
      }
    });
  }

  // ── Page Sorter — drag to reorder pages ──────────────────────────────────
  void _showPageSorter(BuildContext context, _RecentFile file) {
    // Generate a page list (up to 50 pages shown)
    final pageCount = file.pageOrder.isNotEmpty ? file.pageOrder.length : 20;
    final pages = file.pageOrder.isNotEmpty
        ? List<int>.from(file.pageOrder)
        : List<int>.generate(pageCount, (i) => i + 1);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: JarvisColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: JarvisColors.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    const Icon(
                      Icons.sort_rounded,
                      color: JarvisColors.accentPrimary,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Page Sorter',
                            style: TextStyle(
                              color: JarvisColors.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            'Drag to reorder • ${pages.length} pages',
                            style: const TextStyle(
                              color: JarvisColors.textMuted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Upload more pages
                    IconButton(
                      icon: const Icon(
                        Icons.add_photo_alternate_rounded,
                        color: JarvisColors.accentPrimary,
                      ),
                      tooltip: 'Add files/images',
                      onPressed: () async {
                        final result = await FilePicker.platform.pickFiles(
                          allowMultiple: true,
                          type: FileType.any,
                        );
                        if (result != null && mounted) {
                          for (final p in result.paths.whereType<String>()) {
                            await _addRecent(p);
                          }
                          if (ctx.mounted) Navigator.pop(ctx);
                        }
                      },
                    ),
                    TextButton(
                      onPressed: () async {
                        final idx = _recent.indexWhere(
                          (f) => f.path == file.path,
                        );
                        if (idx >= 0) {
                          final old = _recent[idx];
                          _recent[idx] = _RecentFile(
                            path: old.path,
                            name: old.name,
                            notes: old.notes,
                            openedAt: old.openedAt,
                            sizeBytes: old.sizeBytes,
                            pageOrder: List.from(pages),
                          );
                          await _saveRecent();
                          setState(() {});
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                      style: TextButton.styleFrom(
                        backgroundColor: JarvisColors.accentPrimary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Apply',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: JarvisColors.border, height: 16),

              // ── Reorderable page list ──────────────────────
              Expanded(
                child: ReorderableListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: pages.length,
                  onReorder: (oldIdx, newIdx) {
                    if (newIdx > oldIdx) newIdx--;
                    setSheet(() {
                      final item = pages.removeAt(oldIdx);
                      pages.insert(newIdx, item);
                    });
                    HapticFeedback.lightImpact();
                  },
                  itemBuilder: (ctx, i) {
                    final pageNum = pages[i];
                    return Container(
                      key: ValueKey(pageNum),
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: JarvisColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: JarvisColors.border,
                          width: 0.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: JarvisColors.accentPrimary.withValues(
                                alpha: 0.12,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Text(
                                '$pageNum',
                                style: const TextStyle(
                                  color: JarvisColors.accentPrimary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Page $pageNum',
                              style: const TextStyle(
                                color: JarvisColors.textPrimary,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          Text(
                            'Position ${i + 1}',
                            style: const TextStyle(
                              color: JarvisColors.textMuted,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.drag_handle_rounded,
                            color: JarvisColors.textMuted,
                            size: 20,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

              // ── Download / Share sorted ──
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _shareFile(file.path),
                        icon: const Icon(Icons.share_rounded, size: 18),
                        label: const Text('Share File'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: JarvisColors.textSecondary,
                          side: BorderSide(color: JarvisColors.border),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => OpenFilex.open(file.path),
                        icon: const Icon(Icons.download_rounded, size: 18),
                        label: const Text('Open/Download'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: JarvisColors.accentPrimary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
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

  Widget _buildQuickActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          _QuickBtn(
            icon: Icons.upload_file_rounded,
            label: 'Import File',
            color: JarvisColors.accentPrimary,
            onTap: _pickFiles,
          ),
          const SizedBox(width: 8),
          _QuickBtn(
            icon: Icons.add_photo_alternate_rounded,
            label: 'Add Photo',
            color: const Color(0xFF8B5CF6),
            onTap: _pickImages,
          ),
          const SizedBox(width: 8),
          _QuickBtn(
            icon: Icons.auto_awesome_rounded,
            label: 'Ask JARVIS',
            color: JarvisColors.accentSecondary,
            onTap: () => Navigator.pop(context),
          ),
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
          colors: [
            JarvisColors.accentPrimary.withValues(alpha: 0.12),
            JarvisColors.accentSecondary.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: JarvisColors.accentPrimary.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          ShaderMask(
            shaderCallback: (b) => JarvisColors.primaryGradient.createShader(b),
            child: const Icon(
              Icons.auto_awesome_rounded,
              size: 18,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'JARVIS SUGGESTS',
                  style: TextStyle(
                    color: JarvisColors.accentPrimary,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'You opened "${f.name}" recently',
                  style: const TextStyle(
                    color: JarvisColors.textSecondary,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _openFile(f.path),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'Open',
              style: TextStyle(
                color: JarvisColors.accentPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
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
                color: selected
                    ? JarvisColors.accentPrimary
                    : JarvisColors.surfaceElevated,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected
                      ? JarvisColors.accentPrimary
                      : JarvisColors.border,
                ),
              ),
              child: Text(
                cat,
                style: TextStyle(
                  color: selected ? Colors.white : JarvisColors.textSecondary,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
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
            child: const Icon(
              Icons.folder_open_rounded,
              size: 64,
              color: Colors.white,
            ),
          ).animate().scale(
            begin: const Offset(0.5, 0.5),
            duration: 500.ms,
            curve: Curves.elasticOut,
          ),
          const SizedBox(height: 16),
          const Text(
            'No Files Yet',
            style: TextStyle(
              color: JarvisColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Import files or photos to view and edit them here.',
            style: TextStyle(color: JarvisColors.textMuted, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _pickFiles,
            icon: const Icon(Icons.upload_file_rounded, size: 18),
            label: const Text('Import File'),
            style: ElevatedButton.styleFrom(
              backgroundColor: JarvisColors.accentPrimary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Quick Action Button ─────────────────────────────────────────────────────
class _QuickBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _QuickBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ─── File Grid Card ───────────────────────────────────────────────────────────
class _FileCard extends StatelessWidget {
  final _RecentFile file;
  final int index;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onShare;
  final VoidCallback onEdit;
  final VoidCallback? onSort;

  const _FileCard({
    required this.file,
    required this.index,
    required this.onTap,
    required this.onDelete,
    required this.onShare,
    required this.onEdit,
    this.onSort,
  });

  @override
  Widget build(BuildContext context) {
    final color = _fileColor(file.name);
    final icon = _fileIcon(file.name);

    return GestureDetector(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              color: JarvisColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: JarvisColors.border, width: 0.5),
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: 0.06), blurRadius: 12),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Icon + actions
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(icon, color: color, size: 20),
                      ),
                      // Context menu
                      GestureDetector(
                        onTap: () => _showMenu(context),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: JarvisColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.more_horiz_rounded,
                            color: JarvisColors.textMuted,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  // File name — tappable to edit inline
                  GestureDetector(
                    onTap: onEdit,
                    child: Text(
                      file.name,
                      style: const TextStyle(
                        color: JarvisColors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (file.notes.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      file.notes,
                      style: const TextStyle(
                        color: JarvisColors.textMuted,
                        fontSize: 10,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatSize(file.sizeBytes),
                        style: const TextStyle(
                          color: JarvisColors.textMuted,
                          fontSize: 9,
                        ),
                      ),
                      Text(
                        _timeAgo(file.openedAt),
                        style: const TextStyle(
                          color: JarvisColors.textMuted,
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        )
        .animate(delay: Duration(milliseconds: 40 * index))
        .fadeIn(duration: 300.ms)
        .slideY(begin: 0.08, end: 0);
  }

  void _showMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: JarvisColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: JarvisColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              file.name,
              style: const TextStyle(
                color: JarvisColors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            ListTile(
              leading: const Icon(
                Icons.edit_rounded,
                color: JarvisColors.accentPrimary,
              ),
              title: const Text(
                'Edit Name & Notes',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                onEdit();
              },
            ),
            if (onSort != null)
              ListTile(
                leading: const Icon(
                  Icons.sort_rounded,
                  color: Color(0xFF8B5CF6),
                ),
                title: const Text(
                  'Sort Pages',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(context);
                  onSort!();
                },
              ),
            ListTile(
              leading: const Icon(
                Icons.share_rounded,
                color: JarvisColors.accentSecondary,
              ),
              title: const Text(
                'Share File',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                onShare();
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.open_in_new_rounded,
                color: JarvisColors.textSecondary,
              ),
              title: const Text(
                'Open Externally',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                OpenFilex.open(file.path);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline_rounded,
                color: JarvisColors.error,
              ),
              title: const Text(
                'Remove',
                style: TextStyle(color: JarvisColors.error),
              ),
              onTap: () {
                Navigator.pop(context);
                onDelete();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ─── File List Tile (list view) ────────────────────────────────────────────────
class _FileListTile extends StatelessWidget {
  final _RecentFile file;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onShare;
  final VoidCallback onEdit;
  final VoidCallback? onSort;

  const _FileListTile({
    required this.file,
    required this.onTap,
    required this.onDelete,
    required this.onShare,
    required this.onEdit,
    this.onSort,
  });

  @override
  Widget build(BuildContext context) {
    final color = _fileColor(file.name);
    return Dismissible(
      key: Key(file.path),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: JarvisColors.error.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(
          Icons.delete_outline_rounded,
          color: JarvisColors.error,
        ),
      ),
      onDismissed: (_) => onDelete(),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: JarvisColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: JarvisColors.border, width: 0.5),
        ),
        child: ListTile(
          onTap: onTap,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 4,
          ),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(_fileIcon(file.name), color: color, size: 22),
          ),
          title: GestureDetector(
            onTap: onEdit,
            child: Text(
              file.name,
              style: const TextStyle(
                color: JarvisColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (file.notes.isNotEmpty)
                Text(
                  file.notes,
                  style: const TextStyle(
                    color: JarvisColors.textMuted,
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              Text(
                '${_formatSize(file.sizeBytes)} • ${_timeAgo(file.openedAt)}',
                style: const TextStyle(
                  color: JarvisColors.textMuted,
                  fontSize: 10,
                ),
              ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onSort != null)
                IconButton(
                  icon: const Icon(Icons.sort_rounded, size: 18),
                  color: const Color(0xFF8B5CF6),
                  onPressed: onSort,
                  tooltip: 'Sort Pages',
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  padding: EdgeInsets.zero,
                ),
              IconButton(
                icon: const Icon(Icons.share_rounded, size: 18),
                color: JarvisColors.textMuted,
                onPressed: onShare,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
              ),
              IconButton(
                icon: const Icon(Icons.edit_rounded, size: 18),
                color: JarvisColors.accentPrimary,
                onPressed: onEdit,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
