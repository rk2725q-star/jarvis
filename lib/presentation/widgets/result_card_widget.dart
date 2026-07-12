import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/models/search_result_model.dart';

class ResultCardWidget extends StatelessWidget {
  final AriaSearchResult result;

  const ResultCardWidget({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _launch(result.url),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _borderColor(), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_typeIcon(), color: Colors.grey, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    result.provenance.sourceName,
                    style: const TextStyle(color: Colors.grey, fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _ConfidenceBadge(label: result.confidenceLabel),
                const SizedBox(width: 8),
                Text(
                  _freshnessLabel(),
                  style: const TextStyle(color: Colors.grey, fontSize: 10),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              result.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (result.summary != null) ...[
              const SizedBox(height: 6),
              Text(
                result.summary!,
                style: const TextStyle(color: Color(0xFF8B949E), fontSize: 13),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const Divider(color: Color(0xFF21262D), height: 16),
            Row(
              children: [
                const Icon(Icons.link, size: 11, color: Colors.grey),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    result.url,
                    style: const TextStyle(
                      color: Color(0xFF58A6FF),
                      fontSize: 10,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (result.provenance.attribution != null)
                  Text(
                    result.provenance.attribution!,
                    style: const TextStyle(color: Colors.grey, fontSize: 9),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _borderColor() {
    switch (result.confidenceLabel) {
      case ConfidenceLabel.verified:
        return Colors.green.shade700;
      case ConfidenceLabel.high:
        return Colors.blue.shade700;
      case ConfidenceLabel.medium:
        return const Color(0xFF30363D);
      case ConfidenceLabel.low:
        return Colors.red.shade900;
    }
  }

  IconData _typeIcon() {
    switch (result.resultType) {
      case ResultType.news:
        return Icons.newspaper;
      case ResultType.instantAnswer:
        return Icons.auto_awesome;
      default:
        return Icons.article;
    }
  }

  String _freshnessLabel() {
    final diff = DateTime.now().difference(
      result.publishedAt ?? result.fetchedAt,
    );
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Future<void> _launch(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

class _ConfidenceBadge extends StatelessWidget {
  final ConfidenceLabel label;
  const _ConfidenceBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _color().withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _color(), width: 0.5),
      ),
      child: Text(
        label.name.toUpperCase(),
        style: TextStyle(
          color: _color(),
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Color _color() {
    switch (label) {
      case ConfidenceLabel.verified:
        return Colors.green;
      case ConfidenceLabel.high:
        return Colors.blue;
      case ConfidenceLabel.medium:
        return Colors.orange;
      case ConfidenceLabel.low:
        return Colors.red;
    }
  }
}
