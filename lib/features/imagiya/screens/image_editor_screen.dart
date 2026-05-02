import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_painter_v2/flutter_painter.dart';

class ImageEditorScreen extends StatefulWidget {
  final ui.Image image;
  final String title;

  const ImageEditorScreen({
    super.key,
    required this.image,
    this.title = 'Edit Image',
  });

  @override
  State<ImageEditorScreen> createState() => _ImageEditorScreenState();
}

class _ImageEditorScreenState extends State<ImageEditorScreen> {
  late PainterController _controller;

  @override
  void initState() {
    super.initState();
    _controller = PainterController(
      settings: PainterSettings(
        freeStyle: const FreeStyleSettings(
          color: Colors.red,
          strokeWidth: 5,
        ),
        shape: ShapeSettings(
          paint: Paint()..color = Colors.blue..style = PaintingStyle.stroke..strokeWidth = 5,
        ),
      ),
    );
    _controller.background = widget.image.backgroundDrawable;
  }

  Future<void> _save() async {
    final ui.Image renderedImage = await _controller.renderImage(
      Size(widget.image.width.toDouble(), widget.image.height.toDouble()),
    );
    final ByteData? byteData = await renderedImage.toByteData(format: ui.ImageByteFormat.png);
    if (!mounted) return;
    if (byteData != null) {
      Navigator.pop(context, byteData.buffer.asUint8List());
    } else {
      Navigator.pop(context, null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo),
            onPressed: _controller.canUndo ? _controller.undo : null,
          ),
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _save,
          ),
        ],
      ),
      body: Center(
        child: AspectRatio(
          aspectRatio: widget.image.width / widget.image.height,
          child: FlutterPainter(
            controller: _controller,
          ),
        ),
      ),
      bottomNavigationBar: BottomAppBar(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.red),
              onPressed: () {
                _controller.freeStyleColor = Colors.red;
                _controller.freeStyleStrokeWidth = 5;
              },
            ),
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.blue),
              onPressed: () {
                _controller.freeStyleColor = Colors.blue;
                _controller.freeStyleStrokeWidth = 5;
              },
            ),
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.green),
              onPressed: () {
                _controller.freeStyleColor = Colors.green;
                _controller.freeStyleStrokeWidth = 5;
              },
            ),
            IconButton(
              icon: const Icon(Icons.cleaning_services),
              onPressed: () => _controller.clearDrawables(),
            ),
          ],
        ),
      ),
    );
  }
}
