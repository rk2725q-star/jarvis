import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/jarvis_skill.dart';

class SkillService extends ChangeNotifier {
  static const String _boxName = 'jarvis_skills';
  Box<String>? _box;
  final _uuid = const Uuid();
  List<JarvisSkill> _skills = [];

  List<JarvisSkill> get skills => _skills;

  Future<void> init() async {
    _box = await Hive.openBox<String>(_boxName);
    if (_box != null && _box!.isEmpty) {
      await _seedAwesomeSkills();
    }
    _loadSkills();
  }

  Future<void> _seedAwesomeSkills() async {
    try {
      final jsonString = await rootBundle.loadString(
        'assets/config/awesome_skills.json',
      );
      final List<dynamic> decoded = jsonDecode(jsonString);
      for (final item in decoded) {
        final skillMap = item as Map<String, dynamic>;
        final id = skillMap['id'] as String;
        await _box?.put(id, jsonEncode(skillMap));
      }
      debugPrint('Successfully seeded ${decoded.length} awesome skills.');
    } catch (e) {
      debugPrint('Error seeding awesome skills: $e');
    }
  }

  void _loadSkills() {
    if (_box == null) return;
    _skills = _box!.values.map((s) {
      final decoded = jsonDecode(s) as Map<String, dynamic>;
      return JarvisSkill.fromJson(decoded);
    }).toList();
    _skills.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    notifyListeners();
  }

  Future<JarvisSkill> createSkill({
    required String name,
    required String description,
    required String systemInstruction,
    required List<String> triggerKeywords,
    List<String>? executableSteps,
  }) async {
    final skill = JarvisSkill(
      id: _uuid.v4(),
      name: name,
      description: description,
      systemInstruction: systemInstruction,
      triggerKeywords: triggerKeywords,
      executableSteps: executableSteps,
      createdAt: DateTime.now(),
    );

    await _box?.put(skill.id, jsonEncode(skill.toJson()));
    _loadSkills();
    return skill;
  }

  Future<void> toggleSkill(String id) async {
    final idx = _skills.indexWhere((s) => s.id == id);
    if (idx != -1) {
      _skills[idx].isActive = !_skills[idx].isActive;
      await _box?.put(id, jsonEncode(_skills[idx].toJson()));
      notifyListeners();
    }
  }

  Future<void> deleteSkill(String id) async {
    await _box?.delete(id);
    _loadSkills();
  }

  Future<void> clearAll() async {
    await _box?.clear();
    _loadSkills();
  }
}
