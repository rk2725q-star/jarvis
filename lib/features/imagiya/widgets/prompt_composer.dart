import 'package:flutter/material.dart';
import '../models/image_models.dart';
import '../services/imagiya_service.dart';

class PromptComposer extends StatefulWidget {
  final void Function(ImagiyaPrompt) onGenerate;
  final bool isLoading;

  const PromptComposer({
    super.key,
    required this.onGenerate,
    this.isLoading = false,
  });

  @override
  State<PromptComposer> createState() => _PromptComposerState();
}

class _PromptComposerState extends State<PromptComposer> {
  final _controller = TextEditingController();
  ImageResolution _resolution = ImageResolution.hd;
  String _model = 'flux';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Prompt label
          Row(children: [
            const Icon(Icons.auto_awesome, size: 16, color: Colors.deepPurple),
            const SizedBox(width: 6),
            Text('Imagiya', style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Colors.deepPurple,
              fontWeight: FontWeight.w700,
            )),
            const Spacer(),
            Text('Free · Unlimited', style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.green,
            )),
          ]),
          const SizedBox(height: 12),

          // Text input
          TextField(
            controller: _controller,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Describe your image... e.g. "A futuristic Tamil Nadu cityscape at sunset"',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
            ),
          ),
          const SizedBox(height: 12),

          // Options row
          Row(children: [
            // Resolution picker
            Expanded(
              child: DropdownButtonFormField<ImageResolution>(
                initialValue: _resolution,
                decoration: const InputDecoration(
                  labelText: 'Quality',
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: ImageResolution.standard, child: Text('Standard (512)')),
                  DropdownMenuItem(value: ImageResolution.hd, child: Text('HD (1024)')),
                  DropdownMenuItem(value: ImageResolution.fullhd, child: Text('Full HD (1920)')),
                ],
                onChanged: (v) => setState(() => _resolution = v!),
              ),
            ),
            const SizedBox(width: 12),

            // Model picker
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _model,
                decoration: const InputDecoration(
                  labelText: 'Style',
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(),
                ),
                items: ImagiyaService.availableModels
                    .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                    .toList(),
                onChanged: (v) => setState(() => _model = v!),
              ),
            ),
          ]),
          const SizedBox(height: 16),

          // Generate button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: widget.isLoading || _controller.text.trim().isEmpty
                  ? null
                  : () => widget.onGenerate(ImagiyaPrompt(
                        text: _controller.text.trim(),
                        resolution: _resolution,
                        model: _model,
                      )),
              icon: widget.isLoading
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.generating_tokens),
              label: Text(widget.isLoading ? 'Generating...' : 'Generate with Imagiya'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
