import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../vibecode_controller.dart';
import '../models/generated_file.dart';

class FileExplorerPanel extends StatelessWidget {
  const FileExplorerPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final vc = context.watch<VibeCodeController>();
    final project = vc.currentProject;
    if (project == null) return const SizedBox.shrink();

    return Container(
      color: const Color(0xFF0D0D15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.folder_open, color: Color(0xFF7C3AED), size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    project.name,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Color(0xFF1E1E2E), height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: project.files.length,
              itemBuilder: (ctx, i) {
                final file = project.files[i];
                final isSelected = vc.selectedFilePath == file.path;
                return _FileItem(
                  file: file,
                  isSelected: isSelected,
                  onTap: () => vc.selectFile(file.path),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FileItem extends StatelessWidget {
  final GeneratedFile file;
  final bool isSelected;
  final VoidCallback onTap;

  const _FileItem({
    required this.file,
    required this.isSelected,
    required this.onTap,
  });

  IconData get _fileIcon {
    if (file.name.endsWith('.html')) return Icons.html;
    if (file.name.endsWith('.css')) return Icons.css;
    if (file.name.endsWith('.js')) return Icons.javascript;
    if (file.name.endsWith('.json')) return Icons.data_object;
    if (file.name.endsWith('.md')) return Icons.description;
    return Icons.insert_drive_file;
  }

  Color get _fileColor {
    if (file.name.endsWith('.html')) return const Color(0xFFE44D26);
    if (file.name.endsWith('.css')) return const Color(0xFF264DE4);
    if (file.name.endsWith('.js')) return const Color(0xFFF0DB4F);
    if (file.name.endsWith('.json')) return const Color(0xFF8BC34A);
    return Colors.white54;
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: isSelected ? const Color(0xFF7C3AED).withValues(alpha: 0.2) : Colors.transparent,
        child: Row(
          children: [
            Icon(_fileIcon, size: 14, color: _fileColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                file.name,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white60,
                  fontSize: 11,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Code editor panel (read/edit view)
class CodeEditorPanel extends StatefulWidget {
  const CodeEditorPanel({super.key});

  @override
  State<CodeEditorPanel> createState() => _CodeEditorPanelState();
}

class _CodeEditorPanelState extends State<CodeEditorPanel> {
  final _controller = TextEditingController();
  String? _lastFilePath;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vc = context.watch<VibeCodeController>();
    final file = vc.selectedFile;

    if (file == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.code_off_rounded, size: 48, color: Colors.white10),
            SizedBox(height: 16),
            Text('Select a file to view or edit code', style: TextStyle(color: Colors.white38)),
          ],
        ),
      );
    }

    if (_lastFilePath != file.path) {
      _controller.text = file.content;
      _lastFilePath = file.path;
    }

    return Container(
      color: const Color(0xFF0D0D15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Editor Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: const Color(0xFF1E1E2E),
            child: Row(
              children: [
                const Icon(Icons.code_rounded, size: 14, color: Color(0xFF7C3AED)),
                const SizedBox(width: 8),
                Text(
                  file.path,
                  style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                const Text(
                  'READ-WRITE MODE',
                  style: TextStyle(color: Colors.greenAccent, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 1),
                ),
                const SizedBox(width: 12),
                Text(
                  '${file.content.split('\n').length} lines',
                  style: const TextStyle(color: Colors.white24, fontSize: 10),
                ),
              ],
            ),
          ),
          // Editor Content
          Expanded(
            child: TextField(
              controller: _controller,
              maxLines: null,
              expands: true,
              style: const TextStyle(
                color: Color(0xFFABB2BF),
                fontFamily: 'monospace',
                fontSize: 13,
                height: 1.6,
              ),
              cursorColor: const Color(0xFF7C3AED),
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(20),
                filled: true,
                fillColor: Color(0xFF0A0A0F),
              ),
              onChanged: (newVal) {
                vc.updateFileContent(file.path, newVal);
              },
            ),
          ),
        ],
      ),
    );
  }
}
