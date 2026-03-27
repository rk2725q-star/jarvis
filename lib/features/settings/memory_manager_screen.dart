import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/memory/memory_service.dart';
import '../../models/memory_item.dart';
import '../../theme/jarvis_theme.dart';
import 'package:google_fonts/google_fonts.dart';

class MemoryManagerScreen extends StatefulWidget {
  const MemoryManagerScreen({super.key});

  @override
  State<MemoryManagerScreen> createState() => _MemoryManagerScreenState();
}

class _MemoryManagerScreenState extends State<MemoryManagerScreen> {
  String _selectedCategory = 'ALL';

  @override
  Widget build(BuildContext context) {
    final memoryService = context.watch<MemoryService>();
    var memories = memoryService.getAllMemories();
    
    // Sort chronologically (newest first for UI)
    memories.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (_selectedCategory != 'ALL') {
      memories = memories.where((m) => m.category.toUpperCase() == _selectedCategory).toList();
    }

    return Scaffold(
      backgroundColor: JarvisColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'MANAGE MEMORY',
          style: GoogleFonts.outfit(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
        actions: [
          if (memories.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded, color: JarvisColors.error),
              onPressed: () => _confirmClearAll(context, memoryService),
              tooltip: 'Clear All',
            ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterChips(),
          Expanded(
            child: memories.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: memories.length,
              itemBuilder: (context, index) {
                final memory = memories[index];
                return _buildMemoryCard(context, memory, memoryService);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    final categories = ['ALL', 'GENERAL', 'NOTIFICATION', 'LANGUAGE'];
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final cat = categories[index];
          final isSelected = _selectedCategory == cat;
          return FilterChip(
            label: Text(cat, style: TextStyle(fontSize: 11, color: isSelected ? Colors.black : Colors.white70)),
            selected: isSelected,
            onSelected: (val) => setState(() => _selectedCategory = cat),
            backgroundColor: JarvisColors.surfaceElevated,
            selectedColor: JarvisColors.accentPrimary,
            checkmarkColor: Colors.black,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            side: BorderSide(color: isSelected ? JarvisColors.accentPrimary : JarvisColors.border, width: 0.5),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.psychology_alt_rounded, size: 64, color: JarvisColors.textMuted.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text(
            'NO STORED MEMORIES',
            style: GoogleFonts.outfit(
              color: JarvisColors.textMuted,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemoryCard(BuildContext context, MemoryItem item, MemoryService service) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: JarvisColors.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: JarvisColors.border, width: 0.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onLongPress: () => _confirmDelete(context, item, service),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: JarvisColors.accentPrimary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          item.category.toUpperCase(),
                          style: const TextStyle(
                            color: JarvisColors.accentPrimary,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _formatDate(item.createdAt),
                        style: const TextStyle(color: JarvisColors.textMuted, fontSize: 10),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    item.content,
                    style: GoogleFonts.outfit(
                      color: JarvisColors.textPrimary,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.star_rounded, size: 14, color: Colors.orangeAccent),
                      const SizedBox(width: 4),
                      Text(
                        'Importance: ${(item.importance * 100).toInt()}%',
                        style: const TextStyle(color: JarvisColors.textSecondary, fontSize: 11),
                      ),
                      const Spacer(),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.delete_outline_rounded, size: 18, color: JarvisColors.error),
                        onPressed: () => _confirmDelete(context, item, service),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  void _confirmDelete(BuildContext context, MemoryItem item, MemoryService service) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: JarvisColors.surfaceElevated,
        title: const Text('Delete Memory?', style: TextStyle(color: Colors.white)),
        content: const Text('This piece of context will be permanently removed from JARVIS.', style: TextStyle(color: JarvisColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () async {
              await service.deleteMemory(item.id);
              if (context.mounted) {
                Navigator.pop(context);
                setState(() {});
              }
            },
            child: const Text('DELETE', style: TextStyle(color: JarvisColors.error)),
          ),
        ],
      ),
    );
  }

  void _confirmClearAll(BuildContext context, MemoryService service) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: JarvisColors.surfaceElevated,
        title: const Text('Clear All Memories?', style: TextStyle(color: Colors.white)),
        content: const Text('JARVIS will lose all stored contextual learned behavior.', style: TextStyle(color: JarvisColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () async {
              await service.clearAll();
              if (context.mounted) {
                Navigator.pop(context);
                setState(() {});
              }
            },
            child: const Text('CLEAR ALL', style: TextStyle(color: JarvisColors.error)),
          ),
        ],
      ),
    );
  }
}
