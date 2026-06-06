import 'dart:async';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../../core/api/api_client.dart';
import 'package:provider/provider.dart';
import '../../../core/router/ai_router.dart';
import '../../codesign/models/codesign_models.dart';
import '../../codesign/services/codesign_service.dart';
import '../../codesign/widgets/codesign_panel.dart';
import '../../download/download_service.dart';
import '../models/image_models.dart';
import '../services/imagiya_service.dart';
import '../widgets/image_viewport.dart';
import '../widgets/prompt_composer.dart';
import 'image_editor_screen.dart';
import 'ebook_generator_screen.dart';
import 'video_gen_screen.dart';

class ImagiyaScreen extends StatefulWidget {
  final int initialTabIndex;
  
  const ImagiyaScreen({super.key, this.initialTabIndex = 0});

  @override
  State<ImagiyaScreen> createState() => _ImagiyaScreenState();
}

class _ImagiyaScreenState extends State<ImagiyaScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late final ImagiyaService _imagiyaService;
  late final CodesignService _codesignService;
  final _downloadService = DownloadService();

  GeneratedImage? _currentImage;
  CodesignArtifact? _currentArtifact;
  bool _isGenerating = false;
  bool _isDesigning = false;
  StreamSubscription? _genSub;

  @override
  void initState() {
    super.initState();
    _imagiyaService = ImagiyaService(router: context.read<AIRouter>());
    _codesignService = CodesignService(router: context.read<AIRouter>());
    _tabs = TabController(length: 4, vsync: this, initialIndex: widget.initialTabIndex);
  }

  @override
  void dispose() {
    _genSub?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _generateImage(ImagiyaPrompt prompt) async {
    _genSub?.cancel();
    setState(() => _isGenerating = true);

    _genSub = _imagiyaService.generate(prompt).listen(
      (image) => setState(() {
        _currentImage = image;
        if (image.status != ImageStatus.generating) _isGenerating = false;
      }),
      onError: (_) => setState(() => _isGenerating = false),
    );
  }

  Future<void> _downloadImage() async {
    if (_currentImage == null) return;
    final bytes = await ApiClient.instance.fetchImageBytes(_currentImage!.imageUrl);
    final result = await _downloadService.saveToGallery(
      bytes, 'imagiya_${DateTime.now().millisecondsSinceEpoch}',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(result.success ? '✅ Saved to gallery!' : '❌ ${result.error}'),
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _generateCodesign(CodesignRequest request) async {
    setState(() => _isDesigning = true);
    try {
      final artifact = await _codesignService.generate(request);
      setState(() => _currentArtifact = artifact);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('CoDesign error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _isDesigning = false);
    }
  }

  Future<void> _editArtifact(String instruction) async {
    if (_currentArtifact == null) return;
    setState(() => _isDesigning = true);
    try {
      final updated = await _codesignService.edit(_currentArtifact!, instruction);
      setState(() => _currentArtifact = updated);
    } finally {
      setState(() => _isDesigning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F16), // Dark mode base
      appBar: AppBar(
        backgroundColor: const Color(0xFF141420),
        title: const Row(children: [
          Icon(Icons.auto_awesome, color: Colors.deepPurpleAccent),
          SizedBox(width: 8),
          Text('JARVIS Creative', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
        ]),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(icon: Icon(Icons.image), text: 'Imagiya'),
            Tab(icon: Icon(Icons.design_services), text: 'CoDesign'),
            Tab(icon: Icon(Icons.auto_stories), text: 'eBook'),
            Tab(icon: Icon(Icons.videocam_rounded), text: 'Video Gen'),
          ],
          indicatorColor: Colors.deepPurpleAccent,
          labelColor: Colors.deepPurpleAccent,
          unselectedLabelColor: Colors.white70,
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          // ── Imagiya Tab ──
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                PromptComposer(
                  onGenerate: _generateImage,
                  isLoading: _isGenerating,
                ),
                if (_currentImage != null) ...[
                  const SizedBox(height: 20),
                  ImageViewport(
                    image: _currentImage!,
                    onDownload: _downloadImage,
                    onEdit: () async {
                      try {
                        setState(() => _isGenerating = true);
                        final bytes = await ApiClient.instance.fetchImageBytes(_currentImage!.imageUrl);
                        final codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
                        final frame = await codec.getNextFrame();
                        final uiImage = frame.image;
                        
                        setState(() => _isGenerating = false);
                        
                        if (!context.mounted) return;
                        
                        final editedBytes = await Navigator.push<Uint8List>(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ImageEditorScreen(image: uiImage),
                          ),
                        );
                        
                        if (editedBytes != null && context.mounted) {
                          await _downloadService.saveToGallery(editedBytes, 'edited_${DateTime.now().millisecondsSinceEpoch}');
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Edited image saved to gallery!', style: TextStyle(color: Colors.white)), backgroundColor: Colors.deepPurpleAccent),
                          );
                        }
                      } catch (e) {
                        setState(() => _isGenerating = false);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed to open editor: $e')),
                        );
                      }
                    },
                    onShare: () async {
                      final bytes = await ApiClient.instance.fetchImageBytes(_currentImage!.imageUrl);
                      _downloadService.shareImage(bytes, _currentImage!.sourcePrompt.text);
                    },
                    onCodesign: () {
                      _tabs.animateTo(1); // Switch to CoDesign tab
                    },
                  ),
                ],
              ],
            ),
          ),

          // ── CoDesign Tab ──
          Padding(
            padding: const EdgeInsets.all(16),
            child: CodesignPanel(
              artifact: _currentArtifact,
              onGenerate: _generateCodesign,
              onEdit: _editArtifact,
              onRestore: (restored) {
                setState(() {
                  _currentArtifact = restored;
                });
              },
              onSaveImage: (bytes) async {
                final result = await _downloadService.saveToGallery(
                  bytes.toList(),
                  'codesign_${DateTime.now().millisecondsSinceEpoch}',
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(result.success ? '✅ Image saved!' : '❌ ${result.error}')),
                  );
                }
              },
              onExport: (artifact) async {
                final result = await _downloadService.saveHtmlArtifact(
                  artifact.htmlContent,
                  'codesign_${artifact.id}',
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(result.success ? '✅ HTML saved!' : '❌ ${result.error}')),
                  );
                }
              },
              isLoading: _isDesigning,
            ),
          ),

          // ── eBook Tab ──
          const EBookGeneratorScreen(),

          // ── Video Gen Tab ──
          const VideoGenScreen(),
        ],
      ),
    );
  }
}
