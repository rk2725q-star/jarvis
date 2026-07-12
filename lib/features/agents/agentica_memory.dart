// ignore_for_file: avoid_print
/// ════════════════════════════════════════════════════════════════
/// GAP 2: Agentica SQLite Persistent Memory
/// ════════════════════════════════════════════════════════════════
/// Stores every completed task and learns reusable tool sequences.
/// Injected into AgenticaEngine at task start for fewer turns on repeat tasks.
library;

import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'agentica_engine.dart';

class AgenticaMemory {
  static Database? _db;

  static Future<Database> get _database async {
    _db ??= await openDatabase(
      p.join(await getDatabasesPath(), 'agentica_v1.db'),
      version: 1,
      onCreate: (db, version) async {
        // Task history — every completed task with full context
        await db.execute('''
          CREATE TABLE tasks (
            id TEXT PRIMARY KEY,
            prompt TEXT NOT NULL,
            result TEXT,
            status TEXT NOT NULL,
            turns_used INTEGER DEFAULT 0,
            provider_used TEXT,
            created_at INTEGER NOT NULL,
            ended_at INTEGER
          )
        ''');

        // Learned patterns — reusable tool sequences per keyword+app
        await db.execute('''
          CREATE TABLE learned_patterns (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            trigger_keyword TEXT NOT NULL,
            successful_tool_sequence TEXT NOT NULL,
            app_context TEXT,
            success_count INTEGER DEFAULT 1,
            last_used INTEGER NOT NULL
          )
        ''');

        // Scheduled tasks table
        await db.execute('''
          CREATE TABLE scheduled_tasks (
            id TEXT PRIMARY KEY,
            prompt TEXT NOT NULL,
            scheduled_time INTEGER NOT NULL,
            status TEXT NOT NULL
          )
        ''');

        await db.execute(
          'CREATE INDEX idx_tasks_status ON tasks (status, created_at DESC)',
        );
        await db.execute(
          'CREATE INDEX idx_patterns_kw ON learned_patterns (trigger_keyword)',
        );
        await db.execute(
          'CREATE INDEX idx_scheduled_time ON scheduled_tasks (status, scheduled_time)',
        );
      },
    );
    return _db!;
  }

  // ─── SAVE completed task ──────────────────────────────────────────────────
  static Future<void> saveTask(
    AgenticaTask task, {
    String? providerUsed,
  }) async {
    final db = await _database;
    await db.insert('tasks', {
      'id': task.id,
      'prompt': task.prompt,
      'result': task.result ?? '',
      'status': task.status.name,
      'turns_used': task.turnsUsed,
      'provider_used': providerUsed ?? '',
      'created_at': task.createdAt.millisecondsSinceEpoch,
      'ended_at': task.endedAt?.millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    print('[AgenticaMemory] Saved task: ${task.id} status=${task.status.name}');
  }

  // ─── GET similar past tasks — keyword match across prompt ─────────────────
  static Future<List<Map<String, dynamic>>> getSimilarTasks(
    String prompt, {
    int limit = 3,
  }) async {
    final db = await _database;
    // Extract keywords: words > 3 chars, not common stopwords
    final stopwords = {
      'the',
      'and',
      'for',
      'that',
      'this',
      'with',
      'from',
      'have',
      'into',
    };
    final keywords = prompt
        .toLowerCase()
        .split(RegExp(r'\W+'))
        .where((w) => w.length > 3 && !stopwords.contains(w))
        .take(4)
        .toList();

    if (keywords.isEmpty) return [];

    final where = keywords.map((_) => "prompt LIKE ?").join(' OR ');
    final args = keywords.map((k) => '%$k%').toList();

    return db.query(
      'tasks',
      where: "($where) AND status = 'succeeded'",
      whereArgs: args,
      orderBy: 'created_at DESC',
      limit: limit,
    );
  }

  // ─── Build memory context string for injection into LLM ──────────────────
  static Future<String> buildMemoryContext(
    String prompt, {
    String? currentApp,
  }) async {
    try {
      final pattern = await findPattern(prompt, appContext: currentApp);
      if (pattern == null) return '';

      return '[SYSTEM HINT] You performed a similar task before. The successful tool sequence was:\n$pattern\n\nWARNING: You MUST still execute these tools step-by-step right now. Do NOT skip execution. Do NOT output DONE until you have actually called the tools and verified the result on the current screen.';
    } catch (_) {
      return '';
    }
  }

  // ─── LEARN a successful tool sequence ────────────────────────────────────
  static Future<void> learnPattern({
    required String prompt,
    required List<String> toolSequence,
    String appContext = '',
    int? latencyMs,
  }) async {
    if (toolSequence.isEmpty) return;
    final db = await _database;

    // Use first meaningful word as trigger keyword
    final keyword = prompt
        .toLowerCase()
        .split(RegExp(r'\W+'))
        .firstWhere((w) => w.length > 3, orElse: () => '');
    if (keyword.isEmpty) return;

    // Serialize as JSON list of ToolCall maps for v3 compatibility
    final toolList = toolSequence
        .map((t) => {'name': t, 'params': {}})
        .toList();
    final toolJson = jsonEncode(toolList);
    final now = DateTime.now().millisecondsSinceEpoch;

    final existing = await db.query(
      'learned_patterns',
      where: 'trigger_keyword = ? AND app_context = ?',
      whereArgs: [keyword, appContext],
      limit: 1,
    );

    if (existing.isEmpty) {
      await db.insert('learned_patterns', {
        'trigger_keyword': keyword,
        'successful_tool_sequence': toolJson,
        'app_context': appContext,
        'success_count': 1,
        'last_used': now,
      });
    } else {
      await db.update(
        'learned_patterns',
        {
          'successful_tool_sequence': toolJson,
          'success_count': (existing.first['success_count'] as int) + 1,
          'last_used': now,
        },
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    }
    print('[AgenticaMemory] Learned pattern: "$keyword" → $toolJson');
  }

  // ─── GET all learned patterns for cache warming ──────────────────────────
  static Future<List<Map<String, dynamic>>> getLearnedPatterns({
    int limit = 100,
  }) async {
    try {
      final db = await _database;
      final rows = await db.query(
        'learned_patterns',
        orderBy: 'success_count DESC',
        limit: limit,
      );
      return rows.map((r) {
        final keyword = r['trigger_keyword'] as String;
        final rawSequence = r['successful_tool_sequence'] as String;

        // Backwards compatibility fallback if it was saved in old format (joined by ' → ')
        String jsonSequence = rawSequence;
        if (!rawSequence.startsWith('[')) {
          final parts = rawSequence
              .split(' → ')
              .map((t) => {'name': t, 'params': {}})
              .toList();
          jsonSequence = jsonEncode(parts);
        }

        return {'embedding': keyword, 'sequence': jsonSequence, 'latency': 500};
      }).toList();
    } catch (_) {
      return [];
    }
  }

  // ─── GET learned pattern for a keyword ───────────────────────────────────
  static Future<String?> findPattern(
    String prompt, {
    String? appContext,
  }) async {
    try {
      final db = await _database;
      final keywords = prompt
          .toLowerCase()
          .split(RegExp(r'\W+'))
          .where((w) => w.length > 3)
          .take(3)
          .toList();
      if (keywords.isEmpty) return null;

      // Try with app context first
      for (final kw in keywords) {
        final rows = await db.query(
          'learned_patterns',
          where:
              'trigger_keyword = ?${appContext != null ? ' AND app_context = ?' : ''}',
          whereArgs: appContext != null ? [kw, appContext] : [kw],
          orderBy: 'success_count DESC',
          limit: 1,
        );
        if (rows.isNotEmpty) {
          return rows.first['successful_tool_sequence'] as String?;
        }
      }

      // Fallback: without app context
      for (final kw in keywords) {
        final rows = await db.query(
          'learned_patterns',
          where: 'trigger_keyword = ?',
          whereArgs: [kw],
          orderBy: 'success_count DESC',
          limit: 1,
        );
        if (rows.isNotEmpty) {
          return rows.first['successful_tool_sequence'] as String?;
        }
      }
    } catch (_) {}
    return null;
  }

  // ─── STATS for UI display ─────────────────────────────────────────────────
  static Future<Map<String, int>> getStats() async {
    final db = await _database;
    final total =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM tasks'),
        ) ??
        0;
    final succeeded =
        Sqflite.firstIntValue(
          await db.rawQuery(
            "SELECT COUNT(*) FROM tasks WHERE status = 'succeeded'",
          ),
        ) ??
        0;
    final patterns =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM learned_patterns'),
        ) ??
        0;
    return {'total': total, 'succeeded': succeeded, 'patterns': patterns};
  }

  // ─── SCHEDULE task ────────────────────────────────────────────────────────
  static Future<void> scheduleTask(String prompt, int scheduledTimeMs) async {
    final db = await _database;
    final id = '${DateTime.now().millisecondsSinceEpoch}';
    await db.insert('scheduled_tasks', {
      'id': id,
      'prompt': prompt,
      'scheduled_time': scheduledTimeMs,
      'status': 'pending',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    print(
      '[AgenticaMemory] Scheduled task: $id prompt="$prompt" time=$scheduledTimeMs',
    );
  }

  // ─── GET pending scheduled tasks ──────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getPendingScheduledTasks(
    int nowMs,
  ) async {
    final db = await _database;
    return db.query(
      'scheduled_tasks',
      where: 'status = ? AND scheduled_time <= ?',
      whereArgs: ['pending', nowMs],
      orderBy: 'scheduled_time ASC',
    );
  }

  // ─── MARK scheduled task completed ────────────────────────────────────────
  static Future<void> markScheduledTaskCompleted(String id) async {
    final db = await _database;
    await db.update(
      'scheduled_tasks',
      {'status': 'completed'},
      where: 'id = ?',
      whereArgs: [id],
    );
    print('[AgenticaMemory] Marked scheduled task completed: $id');
  }

  static Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
