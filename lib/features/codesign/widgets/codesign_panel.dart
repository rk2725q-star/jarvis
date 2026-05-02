import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../models/codesign_models.dart';

class CodesignPanel extends StatefulWidget {
  final CodesignArtifact? artifact;
  final void Function(CodesignRequest) onGenerate;
  final void Function(String editInstruction)? onEdit;
  final void Function(CodesignArtifact)? onExport;
  final void Function(Uint8List)? onSaveImage;
  final bool isLoading;

  const CodesignPanel({
    super.key,
    this.artifact,
    required this.onGenerate,
    this.onEdit,
    this.onExport,
    this.onSaveImage,
    this.isLoading = false,
  });

  @override
  State<CodesignPanel> createState() => _CodesignPanelState();
}

class _CodesignPanelState extends State<CodesignPanel> {
  final _promptController = TextEditingController();
  final _editController = TextEditingController();
  InAppWebViewController? _webViewController;
  CodesignArtifactType _type = CodesignArtifactType.landingPage;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(children: [
          const Icon(Icons.design_services, color: Colors.indigo),
          const SizedBox(width: 8),
          Text('CoDesign', style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: Colors.indigo,
          )),
          const Spacer(),
          if (widget.artifact != null)
            Text('${widget.artifact!.history.length + 1} versions',
              style: Theme.of(context).textTheme.labelSmall,
            ),
        ]),
        const SizedBox(height: 16),

        // Prompt input
        TextField(
          controller: _promptController,
          maxLines: 2,
          decoration: InputDecoration(
            hintText: 'e.g. "Student dashboard for ARIA app with dark mode"',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
          ),
        ),
        const SizedBox(height: 8),

        // Type selector
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: CodesignArtifactType.values.map((t) {
              final labels = {
                CodesignArtifactType.landingPage: '🏠 Landing',
                CodesignArtifactType.dashboard: '📊 Dashboard',
                CodesignArtifactType.slidesDeck: '📑 Slides',
                CodesignArtifactType.mobileUI: '📱 Mobile UI',
                CodesignArtifactType.pricingPage: '💰 Pricing',
              };
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(labels[t]!),
                  selected: _type == t,
                  onSelected: (_) => setState(() => _type = t),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 12),

        // Generate button
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            onPressed: widget.isLoading ? null : () => widget.onGenerate(
              CodesignRequest(prompt: _promptController.text.trim(), type: _type),
            ),
            icon: widget.isLoading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_fix_high),
            label: Text(widget.isLoading ? 'Designing...' : 'Generate Design'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),

        // Preview + edit (when artifact exists)
        if (widget.artifact != null) ...[
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),

          // WebView preview of generated HTML
          Container(
            height: 350,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: InAppWebView(
                initialData: InAppWebViewInitialData(
                  data: widget.artifact!.htmlContent,
                ),
                onWebViewCreated: (controller) {
                  _webViewController = controller;
                },
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Edit instruction
          Row(children: [
            Expanded(
              child: TextField(
                controller: _editController,
                decoration: InputDecoration(
                  hintText: 'Edit instruction: "Make it darker" / "Add Tamil text"',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: () {
                if (_editController.text.trim().isNotEmpty) {
                  widget.onEdit?.call(_editController.text.trim());
                  _editController.clear();
                }
              },
              icon: const Icon(Icons.send),
              style: IconButton.styleFrom(backgroundColor: Colors.indigo),
            ),
          ]),
          const SizedBox(height: 12),

          // Export button
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => widget.onExport?.call(widget.artifact!),
                  icon: const Icon(Icons.code),
                  label: const Text('Export HTML'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 44),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    if (_webViewController != null) {
                      final screenshot = await _webViewController!.takeScreenshot();
                      if (screenshot != null) {
                        widget.onSaveImage?.call(screenshot);
                      }
                    }
                  },
                  icon: const Icon(Icons.image),
                  label: const Text('Save UI Image'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 44),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
