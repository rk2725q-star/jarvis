import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../vibecode_controller.dart';

class GithubDialog extends StatefulWidget {
  const GithubDialog({super.key});

  @override
  State<GithubDialog> createState() => _GithubDialogState();
}

class _GithubDialogState extends State<GithubDialog> {
  final _tokenController = TextEditingController();
  final _repoNameController = TextEditingController();
  final _descController = TextEditingController();
  bool _isPrivate = false;
  bool _isExporting = false;
  String? _resultMessage;
  bool _resultSuccess = false;

  @override
  void dispose() {
    _tokenController.dispose();
    _repoNameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vc = context.watch<VibeCodeController>();

    return Dialog(
      backgroundColor: const Color(0xFF1E1E2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 480,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Text('🐙', style: TextStyle(fontSize: 24)),
                SizedBox(width: 12),
                Text(
                  'GitHub Export',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (!vc.isGithubConnected) ...[
              const Text(
                'Enter your GitHub Personal Access Token\n(Settings → Developer Settings → Tokens)',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 12),
              _buildTextField(_tokenController, 'GitHub Token', obscure: true),
              const SizedBox(height: 12),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  minimumSize: const Size(double.infinity, 44),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  vc.connectGithub(_tokenController.text.trim());
                },
                child: const Text('Connect GitHub'),
              ),
            ] else ...[
              const Text(
                '✅ GitHub Connected',
                style: TextStyle(color: Colors.greenAccent, fontSize: 13),
              ),
              const SizedBox(height: 16),
              _buildTextField(_repoNameController, 'Repository Name'),
              const SizedBox(height: 12),
              _buildTextField(_descController, 'Description (optional)'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Checkbox(
                    value: _isPrivate,
                    onChanged: (v) => setState(() => _isPrivate = v ?? false),
                    activeColor: const Color(0xFF7C3AED),
                  ),
                  const Text('Private Repository', style: TextStyle(color: Colors.white70)),
                ],
              ),
              const SizedBox(height: 16),
              if (_resultMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _resultSuccess
                        ? Colors.green.withValues(alpha: 0.1)
                        : Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _resultSuccess ? Colors.greenAccent : Colors.red,
                    ),
                  ),
                  child: Text(
                    _resultMessage!,
                    style: TextStyle(
                      color: _resultSuccess ? Colors.greenAccent : Colors.red,
                      fontSize: 12,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF24292E),
                  minimumSize: const Size(double.infinity, 44),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _isExporting ? null : () async {
                  final repoName = _repoNameController.text.trim();
                  if (repoName.isEmpty) return;
                  setState(() => _isExporting = true);
                  final result = await vc.exportToGithub(
                    repoName: repoName,
                    description: _descController.text.trim(),
                    isPrivate: _isPrivate,
                  );
                  setState(() {
                    _isExporting = false;
                    _resultSuccess = result['success'] == true;
                    _resultMessage = _resultSuccess
                        ? '✅ Exported! ${result['url']}'
                        : '❌ ${result['error']}';
                  });
                },
                child: _isExporting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('🐙 Export to GitHub', style: TextStyle(color: Colors.white)),
              ),
            ],
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController ctrl, String label, {bool obscure = false}) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white38),
        filled: true,
        fillColor: const Color(0xFF0A0A0F),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
