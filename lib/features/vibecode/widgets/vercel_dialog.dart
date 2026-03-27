import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../vibecode_controller.dart';

class VercelDialog extends StatefulWidget {
  const VercelDialog({super.key});

  @override
  State<VercelDialog> createState() => _VercelDialogState();
}

class _VercelDialogState extends State<VercelDialog> {
  final _tokenController = TextEditingController();
  final _projectNameController = TextEditingController();
  bool _isDeploying = false;
  String? _resultMessage;
  bool _resultSuccess = false;

  @override
  void dispose() {
    _tokenController.dispose();
    _projectNameController.dispose();
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
                Text('▲', style: TextStyle(fontSize: 24, color: Colors.white)),
                SizedBox(width: 12),
                Text(
                  'Deploy to Vercel',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Deploy your app live in seconds — completely free',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 20),

            if (!vc.isVercelConnected) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0A0F),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '💡 Get your token: vercel.com → Settings → Tokens → Create',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
              const SizedBox(height: 12),
              _buildTextField(_tokenController, 'Vercel Token', obscure: true),
              const SizedBox(height: 12),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  minimumSize: const Size(double.infinity, 44),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => vc.connectVercel(_tokenController.text.trim()),
                child: const Text('▲ Connect Vercel', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ] else ...[
              const Text(
                '✅ Vercel Connected',
                style: TextStyle(color: Colors.greenAccent, fontSize: 13),
              ),
              const SizedBox(height: 16),
              _buildTextField(_projectNameController, 'Project Name (URL-friendly)'),
              const SizedBox(height: 12),

              if (vc.currentProject?.vercelUrl != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.greenAccent),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.open_in_new, color: Colors.greenAccent, size: 14),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          vc.currentProject!.vercelUrl!,
                          style: const TextStyle(color: Colors.greenAccent, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),

              if (_resultMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
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
                      color: _resultSuccess ? Colors.greenAccent : Colors.redAccent,
                      fontSize: 12,
                    ),
                  ),
                ),

              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  minimumSize: const Size(double.infinity, 44),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _isDeploying ? null : () async {
                  final name = _projectNameController.text.trim();
                  if (name.isEmpty) return;
                  setState(() => _isDeploying = true);
                  final result = await vc.deployToVercel(projectName: name);
                  setState(() {
                    _isDeploying = false;
                    _resultSuccess = result['success'] == true;
                    _resultMessage = _resultSuccess
                        ? '🚀 Live at: ${result['url']}'
                        : '❌ ${result['error']}';
                  });
                },
                child: _isDeploying
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('▲ Deploy Now', style: TextStyle(fontWeight: FontWeight.bold)),
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
