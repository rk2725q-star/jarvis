import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/jarvis_theme.dart';
import '../../models/jarvis_skill.dart';
import '../../services/skill_service.dart';

class SkillsScreen extends StatefulWidget {
  const SkillsScreen({super.key});

  @override
  State<SkillsScreen> createState() => _SkillsScreenState();
}

class _SkillsScreenState extends State<SkillsScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _instructionController = TextEditingController();
  final TextEditingController _keywordsController = TextEditingController();

  final TextEditingController _testQueryController = TextEditingController();
  String _testResult = 'Enter a test message above to run parsing matches.';
  bool _isTestTriggered = false;

  final TextEditingController _searchController = TextEditingController();
  int _displayLimit = 30;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _displayLimit = 30; // Reset pagination limit on new search query
      });
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _instructionController.dispose();
    _keywordsController.dispose();
    _testQueryController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _createCustomSkill(BuildContext context) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final name = _nameController.text.trim();
    final desc = _descController.text.trim();
    final instruction = _instructionController.text.trim();
    final keywordsText = _keywordsController.text.trim();

    if (name.isEmpty || desc.isEmpty || instruction.isEmpty) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('Please fill out Name, Description, and System Instruction.')),
      );
      return;
    }

    final List<String> keywords = keywordsText.isNotEmpty
        ? keywordsText.split(',').map((s) => s.trim().toLowerCase()).toList()
        : name.toLowerCase().split(' ');

    final skillService = context.read<SkillService>();
    await skillService.createSkill(
      name: name,
      description: desc,
      systemInstruction: instruction,
      triggerKeywords: keywords,
    );

    _nameController.clear();
    _descController.clear();
    _instructionController.clear();
    _keywordsController.clear();

    if (mounted) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('Custom skill added successfully!')),
      );
    }
  }

  void _runTriggerTest(List<JarvisSkill> skills) {
    final query = _testQueryController.text.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() {
        _testResult = 'Enter a test message above to run parsing matches.';
        _isTestTriggered = false;
      });
      return;
    }

    final activeSkills = skills.where((s) => s.isActive).toList();
    final matched = <JarvisSkill>[];

    for (final s in activeSkills) {
      for (final kw in s.triggerKeywords) {
        if (query.contains(kw.toLowerCase())) {
          matched.add(s);
          break;
        }
      }
    }

    setState(() {
      if (matched.isEmpty) {
        _testResult = 'No active skills matched. JARVIS will use standard fallback response.';
        _isTestTriggered = false;
      } else {
        final buffer = StringBuffer();
        buffer.writeln('🎯 MATCH FOUND! Active skills triggered:');
        for (final m in matched) {
          buffer.writeln('\n• Skill: ${m.name}');
          buffer.writeln('  Directive: "${m.systemInstruction}"');
        }
        _testResult = buffer.toString();
        _isTestTriggered = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JarvisColors.bg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF07070C), Color(0xFF0C0C17)],
          ),
        ),
        child: SafeArea(
          child: Consumer<SkillService>(
            builder: (context, skillService, _) {
              final skills = skillService.skills;
              return Column(
                children: [
                  _buildHeader(),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _buildSectionHeader('ACTIVE SKILL REGISTRY', Icons.psychology_rounded),
                        const SizedBox(height: 12),
                        _buildSearchBar(),
                        skills.isEmpty
                            ? _buildEmptyState()
                            : _buildSkillsList(skills, skillService),
                        const SizedBox(height: 28),
                        _buildSectionHeader('CREATE CUSTOM SKILL', Icons.add_circle_outline_rounded),
                        const SizedBox(height: 12),
                        _buildSkillBuilderCard(context),
                        const SizedBox(height: 28),
                        _buildSectionHeader('EXECUTION ROUTER TESTER', Icons.science_rounded),
                        const SizedBox(height: 12),
                        _buildTesterCard(skills),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: JarvisColors.textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShaderMask(
                  shaderCallback: (b) => JarvisColors.primaryGradient.createShader(b),
                  child: const Text(
                    'AI SKILL HUB',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 2.0,
                    ),
                  ),
                ),
                const Text(
                  'Dynamic Custom Capabilities',
                  style: TextStyle(
                    fontSize: 11,
                    color: JarvisColors.textMuted,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: JarvisColors.accentSecondary),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: JarvisColors.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: JarvisColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: JarvisColors.border, width: 0.5),
      ),
      alignment: Alignment.center,
      child: const Column(
        children: [
          Icon(Icons.widgets_outlined, size: 36, color: JarvisColors.textMuted),
          SizedBox(height: 12),
          Text(
            'No custom skills created yet.',
            style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 4),
          Text(
            'Type `/skill [description]` in chat to build one instantly!',
            style: TextStyle(color: JarvisColors.textMuted, fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: JarvisColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: JarvisColors.border, width: 0.5),
      ),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: const InputDecoration(
          hintText: 'Search 1,110+ skills by name or description...',
          hintStyle: TextStyle(color: JarvisColors.textMuted, fontSize: 13),
          prefixIcon: Icon(Icons.search_rounded, color: JarvisColors.textMuted, size: 20),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildSkillsList(List<JarvisSkill> skills, SkillService service) {
    final query = _searchController.text.trim().toLowerCase();
    
    final filteredSkills = skills.where((s) {
      if (query.isEmpty) return true;
      return s.name.toLowerCase().contains(query) ||
             s.description.toLowerCase().contains(query);
    }).toList();

    if (filteredSkills.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: JarvisColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: JarvisColors.border, width: 0.5),
        ),
        alignment: Alignment.center,
        child: const Text(
          'No matching skills found.',
          style: TextStyle(color: JarvisColors.textMuted, fontSize: 12),
        ),
      );
    }

    final hasMore = filteredSkills.length > _displayLimit;
    final skillsToDisplay = filteredSkills.take(_displayLimit).toList();

    return Column(
      children: [
        ...skillsToDisplay.map((s) {
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: JarvisColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: s.isActive ? JarvisColors.accentPrimary.withValues(alpha: 0.4) : JarvisColors.border,
                width: 0.5,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  title: Text(
                    s.name,
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      s.description,
                      style: const TextStyle(color: JarvisColors.textSecondary, fontSize: 11),
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: s.isActive,
                        activeTrackColor: JarvisColors.accentPrimary,
                        onChanged: (_) => service.toggleSkill(s.id),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, color: JarvisColors.error, size: 20),
                        onPressed: () => service.deleteSkill(s.id),
                      ),
                    ],
                  ),
                ),
                if (s.triggerKeywords.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    alignment: Alignment.topLeft,
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: s.triggerKeywords.map((kw) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black26,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Text(
                            '#$kw',
                            style: const TextStyle(color: JarvisColors.accentSecondary, fontSize: 9, fontWeight: FontWeight.bold),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
              ],
            ),
          );
        }),
        if (hasMore) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () {
              setState(() {
                _displayLimit += 30;
              });
            },
            icon: const Icon(Icons.expand_more_rounded, color: JarvisColors.accentSecondary),
            label: Text(
              'Show More (${filteredSkills.length - _displayLimit} remaining)',
              style: const TextStyle(color: JarvisColors.accentSecondary, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSkillBuilderCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: JarvisColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: JarvisColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTextField('Skill Name', _nameController, 'E.g., Python Compiler'),
          const SizedBox(height: 12),
          _buildTextField('Description', _descController, 'E.g., Format program requests into executable Python scripts'),
          const SizedBox(height: 12),
          _buildTextField('System Instruction Directive', _instructionController, 'Instructions explaining exactly how the AI should reason...', maxLines: 3),
          const SizedBox(height: 12),
          _buildTextField('Trigger Keywords (comma separated)', _keywordsController, 'E.g., python, code, script, function'),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => _createCustomSkill(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: JarvisColors.accentPrimary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              minimumSize: const Size(double.infinity, 44),
            ),
            child: const Text('Add Custom Skill', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, String hint, {int maxLines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: maxLines,
          style: const TextStyle(color: Colors.white, fontSize: 12),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: JarvisColors.textMuted, fontSize: 12),
            fillColor: JarvisColors.surfaceElevated,
            filled: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
        ),
      ],
    );
  }

  Widget _buildTesterCard(List<JarvisSkill> skills) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: JarvisColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: JarvisColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _testQueryController,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: InputDecoration(
                    hintText: 'Type query (e.g. "I want a python script")...',
                    hintStyle: const TextStyle(color: JarvisColors.textMuted, fontSize: 12),
                    fillColor: JarvisColors.surfaceElevated,
                    filled: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
                  onSubmitted: (_) => _runTriggerTest(skills),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.bolt_rounded, color: JarvisColors.accentSecondary),
                onPressed: () => _runTriggerTest(skills),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF050508),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _isTestTriggered ? JarvisColors.success.withValues(alpha: 0.5) : JarvisColors.border),
            ),
            child: Text(
              _testResult,
              style: TextStyle(
                color: _isTestTriggered ? Colors.greenAccent : Colors.white70,
                fontSize: 11,
                fontFamily: 'SourceCodePro',
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
