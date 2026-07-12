import 'package:dio/dio.dart';
import 'package:webfeed/webfeed.dart' as wf;
import 'package:crypto/crypto.dart';
import 'dart:convert';
import '../../../core/network/dio_client.dart';
import '../../../core/sources/source_registry.dart';
import '../../models/search_result_model.dart';

class RssSource {
  final Dio _dio = DioClient().dio;

  Future<List<AriaSearchResult>> fetchSource(AriaSource source) async {
    try {
      final response = await _dio.get(source.feedUrl);
      if (response.statusCode != 200) return [];

      final xmlString = response.data.toString();

      if (source.type == SourceType.rss) {
        final feed = wf.RssFeed.parse(xmlString);
        return feed.items?.map((item) => _fromRssItem(item, source)).toList() ??
            [];
      } else if (source.type == SourceType.atom) {
        final feed = wf.AtomFeed.parse(xmlString);
        return feed.items
                ?.map((item) => _fromAtomItem(item, source))
                .toList() ??
            [];
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  AriaSearchResult _fromRssItem(wf.RssItem item, AriaSource source) {
    final title = item.title ?? '';
    final link = item.link ?? '';
    final description = item.description ?? '';
    final pubDate = item.pubDate;
    final now = DateTime.now();

    final normalized =
        '${title.toLowerCase().trim()}${link.toLowerCase().trim()}';
    final hash = sha256.convert(utf8.encode(normalized)).toString();

    return AriaSearchResult(
      id: item.guid ?? hash,
      title: title,
      summary: description,
      url: link,
      category: source.category.name,
      publishedAt: pubDate,
      fetchedAt: now,
      resultType: ResultType.news,
      confidence: 0.85,
      confidenceLabel: ConfidenceLabel.high,
      freshnessScore: 1.0,
      trustScore: source.trustScore,
      contentHash: hash,
      provenance: AriaProvenance(
        sourceId: source.id,
        sourceName: source.name,
        sourceUrl: source.feedUrl,
        fetchTimestamp: now,
        adapterType: 'rss',
        attribution: source.attribution,
      ),
    );
  }

  AriaSearchResult _fromAtomItem(wf.AtomItem item, AriaSource source) {
    final title = item.title ?? '';
    final link = item.links?.first.href ?? '';
    final summary = item.summary ?? item.content ?? '';
    final publishedAt = item.published != null
        ? DateTime.tryParse(item.published!)
        : item.updated;
    final now = DateTime.now();

    final normalized =
        '${title.toLowerCase().trim()}${link.toLowerCase().trim()}';
    final hash = sha256.convert(utf8.encode(normalized)).toString();

    return AriaSearchResult(
      id: item.id ?? hash,
      title: title,
      summary: summary,
      url: link,
      category: source.category.name,
      publishedAt: publishedAt,
      fetchedAt: now,
      resultType: ResultType.news,
      confidence: 0.85,
      confidenceLabel: ConfidenceLabel.high,
      freshnessScore: 1.0,
      trustScore: source.trustScore,
      contentHash: hash,
      provenance: AriaProvenance(
        sourceId: source.id,
        sourceName: source.name,
        sourceUrl: source.feedUrl,
        fetchTimestamp: now,
        adapterType: 'atom',
        attribution: source.attribution,
      ),
    );
  }
}
