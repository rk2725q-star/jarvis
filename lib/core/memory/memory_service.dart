import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../models/memory_item.dart';

/// Persistent memory system — stores important context from conversations
class MemoryService {
  static const String _boxName = 'memories';
  static const int _maxMemories = 100;
  Box<MemoryItem>? _box;
  final _uuid = const Uuid();

  Future<void> init() async {
    _box = await Hive.openBox<MemoryItem>(_boxName);
  }

  Future<MemoryItem> addMemory({
    required String content,
    double importance = 0.5,
    String category = 'general',
  }) async {
    final item = MemoryItem(
      id: _uuid.v4(),
      content: content,
      createdAt: DateTime.now(),
      importance: importance,
      category: category,
    );

    // Evict lowest importance if at capacity
    if ((_box?.length ?? 0) >= _maxMemories) {
      final entries = _box!.values.toList()
        ..sort((a, b) => a.importance.compareTo(b.importance));
      await entries.first.delete();
    }

    await _box?.put(item.id, item);
    return item;
  }

  List<MemoryItem> getTopMemories({int limit = 10}) {
    final all = _box?.values.toList() ?? [];
    all.sort((a, b) => b.importance.compareTo(a.importance));
    return all.take(limit).toList();
  }

  List<MemoryItem> getAllMemories() {
    return _box?.values.toList() ?? [];
  }

  Future<void> deleteMemory(String id) async {
    await _box?.delete(id);
  }

  Future<void> clearAll() async {
    await _box?.clear();
  }

  /// Build context string injected into prompt
  String buildContextString({int limit = 10}) {
    final all = _box?.values.toList() ?? [];
    if (all.isEmpty) return '';

    // Prioritize language preferences and notification status
    final langMems = all.where((m) => m.category == 'language').toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    
    final notifMems = all.where((m) => m.category == 'notification').toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    
    // Get other important memories
    final otherMems = all.where((m) => m.category != 'language' && m.category != 'notification').toList()
      ..sort((a, b) => b.importance.compareTo(a.importance));

    final Set<MemoryItem> contextItems = {};
    if (langMems.isNotEmpty) contextItems.add(langMems.first); // Take the latest language choice
    
    // Always include the last 3 notification memories to prevent repetitive asking
    for (var m in notifMems.take(3)) {
      contextItems.add(m);
    }
    
    for (var m in otherMems) {
      if (contextItems.length >= limit) break;
      contextItems.add(m);
    }

    final finalItems = contextItems.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt)); // Chronological order for logic

    return '=== Relevant Memory Context ===\n${finalItems.map((m) => '• ${m.content}').join('\n')}\n\n';
  }

  int get count => _box?.length ?? 0;
}
