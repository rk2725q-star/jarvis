import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/image_models.dart';

class ImageViewport extends StatelessWidget {
  final GeneratedImage image;
  final VoidCallback? onDownload;
  final VoidCallback? onEdit;
  final VoidCallback? onShare;
  final VoidCallback? onCodesign; // Send to CoDesign

  const ImageViewport({
    super.key,
    required this.image,
    this.onDownload,
    this.onEdit,
    this.onShare,
    this.onCodesign,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Image area
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              if (image.imageUrl.startsWith('data:image/'))
                Image.memory(
                  base64Decode(image.imageUrl.split(',').last),
                  fit: BoxFit.contain,
                )
              else
                CachedNetworkImage(
                  imageUrl: image.imageUrl,
                  fit: BoxFit.contain,
                  placeholder: (context, url) => Container(
                    height: 300,
                    color: Colors.grey[200],
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                  errorWidget: (context, url, error) => Container(
                    height: 300,
                    color: Colors.red[50],
                    child: const Center(
                      child: Icon(Icons.broken_image, color: Colors.red),
                    ),
                  ),
                ),
              if (image.status == ImageStatus.generating)
                Positioned.fill(
                  child: Container(
                    color: Colors.black45,
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Colors.white),
                          SizedBox(height: 12),
                          Text(
                            'Imagiya is creating...',
                            style: TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Action toolbar
        if (image.status == ImageStatus.success) ...[
          EditToolbar(
            onDownload: onDownload,
            onEdit: onEdit,
            onShare: onShare,
            onCodesign: onCodesign,
          ),
        ],
      ],
    );
  }
}

class EditToolbar extends StatelessWidget {
  final VoidCallback? onDownload;
  final VoidCallback? onEdit;
  final VoidCallback? onShare;
  final VoidCallback? onCodesign;

  const EditToolbar({
    super.key,
    this.onDownload,
    this.onEdit,
    this.onShare,
    this.onCodesign,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _ToolButton(icon: Icons.edit, label: 'Edit', onTap: onEdit),
        _ToolButton(
          icon: Icons.download,
          label: 'Save HD',
          onTap: onDownload,
          accent: true,
        ),
        _ToolButton(icon: Icons.share, label: 'Share', onTap: onShare),
        _ToolButton(
          icon: Icons.design_services,
          label: 'CoDesign',
          onTap: onCodesign,
          accent: true,
        ),
      ],
    );
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool accent;

  const _ToolButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: accent ? Colors.deepPurple : Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: accent ? Colors.white : Colors.grey[700],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: accent ? Colors.white : Colors.grey[700],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
