import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../theme/jarvis_theme.dart';
import 'assignment_provider.dart';
import 'models/assignment.dart';

class AssignmentScreen extends StatelessWidget {
  const AssignmentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JarvisColors.bg,
      appBar: AppBar(
        title: const Text('ASSIGNMENT HUB', style: TextStyle(letterSpacing: 2, fontSize: 18, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: Consumer<AssignmentProvider>(
        builder: (context, provider, child) {
          if (provider.assignments.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.school_outlined, size: 80, color: Colors.white10),
                  const SizedBox(height: 16),
                  const Text('No assignments yet.', style: TextStyle(color: Colors.white24)),
                  const SizedBox(height: 4),
                  const Text('Ask JARVIS to "Add an assignment"', style: TextStyle(color: Colors.white10, fontSize: 10)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: provider.assignments.length,
            itemBuilder: (context, i) {
              final a = provider.assignments[i];
              return _AssignmentCard(assignment: a).animate().fadeIn(delay: Duration(milliseconds: i * 100)).slideX(begin: 0.1, end: 0);
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog(context),
        backgroundColor: JarvisColors.accentPrimary,
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
    );
  }

  void _showAddDialog(BuildContext context) {
    // Basic dialog for manual entry, but the vision is JARVIS does this via tags
    final tController = TextEditingController();
    final dController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: JarvisColors.surfaceElevated,
        title: const Text('New Assignment', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: tController, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Title')),
            TextField(controller: dController, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Description')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              context.read<AssignmentProvider>().addAssignment(Assignment(
                title: tController.text,
                description: dController.text,
                dueDate: DateTime.now().add(const Duration(days: 7)),
              ));
              Navigator.pop(ctx);
            },
            child: const Text('Build'),
          ),
        ],
      ),
    );
  }
}

class _AssignmentCard extends StatelessWidget {
  final Assignment assignment;
  const _AssignmentCard({required this.assignment});

  @override
  Widget build(BuildContext context) {
    final provider = context.read<AssignmentProvider>();
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: JarvisColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: JarvisColors.border, width: 0.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  assignment.title,
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              Checkbox(
                value: assignment.isCompleted,
                activeColor: JarvisColors.accentPrimary,
                onChanged: (_) => provider.toggleCompleted(assignment.id),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            assignment.description,
            style: const TextStyle(color: Colors.white54, fontSize: 13, height: 1.5),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const Icon(Icons.calendar_today_rounded, size: 12, color: JarvisColors.accentPrimary),
              const SizedBox(width: 8),
              Text(
                'Due in 7 days', // Should be calculated
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
              const Spacer(),
              if (assignment.googleDocId == null)
                TextButton.icon(
                  onPressed: () => provider.exportToGoogleDoc(assignment),
                  icon: const Icon(Icons.cloud_upload_outlined, size: 14),
                  label: const Text('Save to GDocs', style: TextStyle(fontSize: 10)),
                  style: TextButton.styleFrom(foregroundColor: JarvisColors.accentPrimary),
                )
              else
                const Row(
                  children: [
                    Icon(Icons.check_circle_rounded, size: 12, color: Colors.greenAccent),
                    SizedBox(width: 4),
                    Text('Synced', style: TextStyle(color: Colors.greenAccent, fontSize: 10)),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}
