import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../vibecode_controller.dart';

class SupabaseDialog extends StatefulWidget {
  const SupabaseDialog({super.key});

  @override
  State<SupabaseDialog> createState() => _SupabaseDialogState();
}

class _SupabaseDialogState extends State<SupabaseDialog> {
  final _urlController = TextEditingController();
  final _keyController = TextEditingController();
  bool _isTesting = false;
  String? _testResult;
  bool _testSuccess = false;

  @override
  void dispose() {
    _urlController.dispose();
    _keyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vc = context.watch<VibeCodeController>();

    return Dialog(
      backgroundColor: const Color(0xFF1E1E2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Text('🟢', style: TextStyle(fontSize: 24)),
                SizedBox(width: 12),
                Text(
                  'Supabase Integration',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Connect your Supabase project for Auth, Database & Storage',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 20),

            // Info box
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0A0F),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF3ECF8E).withValues(alpha: 0.3)),
              ),
              child: const Text(
                '💡 Find these in: Supabase Dashboard → Project Settings → API',
                style: TextStyle(color: Color(0xFF3ECF8E), fontSize: 12),
              ),
            ),
            const SizedBox(height: 16),

            _buildTextField(_urlController, 'Project URL (https://xxxx.supabase.co)'),
            const SizedBox(height: 12),
            _buildTextField(_keyController, 'Anon/Public Key', obscure: true),
            const SizedBox(height: 16),

            if (_testResult != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: _testSuccess
                      ? const Color(0xFF3ECF8E).withValues(alpha: 0.1)
                      : Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _testSuccess ? const Color(0xFF3ECF8E) : Colors.red,
                  ),
                ),
                child: Text(
                  _testResult!,
                  style: TextStyle(
                    color: _testSuccess ? const Color(0xFF3ECF8E) : Colors.redAccent,
                    fontSize: 12,
                  ),
                ),
              ),

            Row(
              children: [
                // Test connection
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF3ECF8E)),
                      foregroundColor: const Color(0xFF3ECF8E),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: _isTesting ? null : () async {
                      final url = _urlController.text.trim();
                      final key = _keyController.text.trim();
                      if (url.isEmpty || key.isEmpty) return;

                      // First connect, then test
                      vc.connectSupabase(url: url, anonKey: key);
                      setState(() => _isTesting = true);

                      final result = await vc.testSupabaseConnection();
                      setState(() {
                        _isTesting = false;
                        _testSuccess = result['success'] == true;
                        _testResult = _testSuccess
                            ? '✅ Connection successful! Supabase is ready.'
                            : '❌ Connection failed: ${result['error']}';
                      });
                    },
                    child: _isTesting
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF3ECF8E),
                            ),
                          )
                        : const Text('Test Connection'),
                  ),
                ),
                const SizedBox(width: 12),
                // Connect
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3ECF8E),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () {
                      final url = _urlController.text.trim();
                      final key = _keyController.text.trim();
                      if (url.isEmpty || key.isEmpty) return;
                      vc.connectSupabase(url: url, anonKey: key);
                      Navigator.pop(context);
                    },
                    child: const Text('Connect & Inject'),
                  ),
                ),
              ],
            ),

            if (vc.isSupabaseConnected) ...[
              const SizedBox(height: 16),
              const Text(
                '✅ Supabase client is auto-injected into your HTML preview.\n'
                'Ask Jarvis to add auth, database queries, or real-time subscriptions!',
                style: TextStyle(color: Color(0xFF3ECF8E), fontSize: 12),
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
