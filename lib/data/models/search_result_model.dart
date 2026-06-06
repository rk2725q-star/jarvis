import 'dart:convert';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

// ═══════════════════════════════════════════════════════════
// ARIA SYSTEM — Canonical Item Schema
// Every search result normalised to this shape
// ═══════════════════════════════════════════════════════════

enum ConfidenceLabel { low, medium, high, verified }

enum ResultType { text, news, image, video, instantAnswer }

class AriaSearchResult {
  final String id;
  final String title;
  final String? summary;
  final String url;
  final String? imageUrl;
  final String? author;
  final String category;
  final String? subcategory;
  final String language;
  final DateTime? publishedAt;
  final DateTime fetchedAt;
  final ResultType resultType;

  // ── Quality signals
  final double confidence;       // 0.0 – 1.0
  final ConfidenceLabel confidenceLabel;
  final double freshnessScore;   // e^(-0.1 * hours_old)
  final double trustScore;       // source authority
  final List<String> biasFlags;
  final bool isVerified;

  // ── Dedup identity
  final String contentHash;      // SHA-256 of normalized content
  final String? canonicalGroup;  // links duplicates

  // ── Provenance
  final AriaProvenance provenance;

  // ── Enrichment
  final List<String> tags;
  final Map<String, List<String>> entities; // persons, orgs, places

  const AriaSearchResult({
    required this.id,
    required this.title,
    this.summary,
    required this.url,
    this.imageUrl,
    this.author,
    required this.category,
    this.subcategory,
    this.language = 'en',
    this.publishedAt,
    required this.fetchedAt,
    required this.resultType,
    required this.confidence,
    required this.confidenceLabel,
    required this.freshnessScore,
    required this.trustScore,
    this.biasFlags = const [],
    this.isVerified = false,
    required this.contentHash,
    this.canonicalGroup,
    required this.provenance,
    this.tags = const [],
    this.entities = const {},
  });

  // ── Factory from DDG text search result map
  factory AriaSearchResult.fromDDGText({
    required Map<String, dynamic> raw,
    required String category,
    required double sourceTrustScore,
  }) {
    final title = raw['title']?.toString() ?? '';
    final body  = raw['body']?.toString() ?? '';
    final url   = raw['href']?.toString() ?? '';
    final now   = DateTime.now();

    final normalized = '${title.toLowerCase().trim()}${url.toLowerCase().trim()}';
    final hash = sha256.convert(utf8.encode(normalized)).toString();

    const freshness = 1.0;
    final confidence = _computeConfidence(
      trustScore: sourceTrustScore,
      corroboration: 0.5,
      freshness: freshness,
      contentQuality: _contentQuality(title, body),
    );

    return AriaSearchResult(
      id:               const Uuid().v4(),
      title:            title,
      summary:          body.isNotEmpty ? body : null,
      url:              url,
      category:         category,
      language:         'en',
      publishedAt:      null,
      fetchedAt:        now,
      resultType:       ResultType.text,
      confidence:       confidence,
      confidenceLabel:  _labelFromScore(confidence),
      freshnessScore:   freshness,
      trustScore:       sourceTrustScore,
      contentHash:      hash,
      provenance: AriaProvenance(
        sourceId:       'duckduckgo-text',
        sourceName:     'DuckDuckGo Text Search',
        sourceUrl:      'https://duckduckgo.com',
        fetchTimestamp: now,
        license:        'varies-by-source',
        adapterType:    'ddg_text',
      ),
      tags:             _extractTags(title, body),
    );
  }

  // ── Factory from DDG news search result
  factory AriaSearchResult.fromDDGNews({
    required Map<String, dynamic> raw,
    required String category,
    required double sourceTrustScore,
  }) {
    final title  = raw['title']?.toString() ?? '';
    final body   = raw['body']?.toString() ?? '';
    final url    = raw['url']?.toString() ?? '';
    final source = raw['source']?.toString() ?? 'Unknown';
    final now    = DateTime.now();

    DateTime? publishedAt;
    final dateStr = raw['date']?.toString();
    if (dateStr != null) {
      try {
        publishedAt = DateTime.parse(dateStr);
      } catch (_) {}
    }

    double freshness = 1.0;
    if (publishedAt != null) {
      final hoursOld = now.difference(publishedAt).inHours.toDouble();
      freshness = _freshnessDecay(hoursOld);
    }

    final normalized = '${title.toLowerCase().trim()}${url.toLowerCase().trim()}';
    final hash = sha256.convert(utf8.encode(normalized)).toString();

    final confidence = _computeConfidence(
      trustScore: sourceTrustScore,
      corroboration: 0.6,
      freshness: freshness,
      contentQuality: _contentQuality(title, body),
    );

    return AriaSearchResult(
      id:              const Uuid().v4(),
      title:           title,
      summary:         body.isNotEmpty ? body : null,
      url:             url,
      author:          source,
      category:        category,
      language:        'en',
      publishedAt:     publishedAt,
      fetchedAt:       now,
      resultType:      ResultType.news,
      confidence:      confidence,
      confidenceLabel: _labelFromScore(confidence),
      freshnessScore:  freshness,
      trustScore:      sourceTrustScore,
      contentHash:     hash,
      provenance: AriaProvenance(
        sourceId:       'duckduckgo-news',
        sourceName:     source,
        sourceUrl:      'https://duckduckgo.com/news',
        fetchTimestamp: now,
        license:        'varies-by-source',
        adapterType:    'ddg_news',
      ),
      tags:            _extractTags(title, body),
    );
  }

  // ── Factory from DDG Instant Answer
  factory AriaSearchResult.fromInstantAnswer({
    required Map<String, dynamic> raw,
    required String category,
  }) {
    final abstractText   = raw['AbstractText']?.toString() ?? '';
    final abstractSource = raw['AbstractSource']?.toString() ?? '';
    final abstractUrl    = raw['AbstractURL']?.toString() ?? '';
    final heading        = raw['Heading']?.toString() ?? '';
    final imageUrl       = raw['Image']?.toString();
    final now            = DateTime.now();

    final normalized = '${heading.toLowerCase().trim()}${abstractUrl.toLowerCase().trim()}';
    final hash = sha256.convert(utf8.encode(normalized)).toString();

    return AriaSearchResult(
      id:              const Uuid().v4(),
      title:           heading.isNotEmpty ? heading : 'Instant Answer',
      summary:         abstractText.isNotEmpty ? abstractText : null,
      url:             abstractUrl.isNotEmpty ? abstractUrl : 'https://duckduckgo.com',
      imageUrl:        (imageUrl != null && imageUrl.isNotEmpty) ? imageUrl : null,
      author:          abstractSource.isNotEmpty ? abstractSource : null,
      category:        category,
      language:        'en',
      publishedAt:     null,
      fetchedAt:       now,
      resultType:      ResultType.instantAnswer,
      confidence:      0.90,
      confidenceLabel: ConfidenceLabel.high,
      freshnessScore:  1.0,
      trustScore:      0.90,
      contentHash:     hash,
      isVerified:      true,
      provenance: AriaProvenance(
        sourceId:       'ddg-instant-answer',
        sourceName:     abstractSource.isNotEmpty ? abstractSource : 'DuckDuckGo',
        sourceUrl:      'https://api.duckduckgo.com',
        fetchTimestamp: now,
        license:        'CC-BY',
        adapterType:    'ddg_instant_answer',
      ),
    );
  }

  static double _freshnessDecay(double hoursOld) {
    if (hoursOld <= 0) return 1.0;
    return math.exp(-0.1 * hoursOld).clamp(0.01, 1.0);
  }

  static double _computeConfidence({
    required double trustScore,
    required double corroboration,
    required double freshness,
    required double contentQuality,
  }) {
    final score = (trustScore    * 0.35) +
                  (corroboration * 0.30) +
                  (freshness     * 0.20) +
                  (contentQuality * 0.15);
    return score.clamp(0.0, 1.0);
  }

  static double _contentQuality(String title, String body) {
    double score = 0.0;
    if (title.length > 10) score += 0.4;
    if (body.length > 50)  score += 0.4;
    if (body.length > 200) score += 0.2;
    return score.clamp(0.0, 1.0);
  }

  static ConfidenceLabel _labelFromScore(double score) {
    if (score >= 0.85) return ConfidenceLabel.verified;
    if (score >= 0.65) return ConfidenceLabel.high;
    if (score >= 0.45) return ConfidenceLabel.medium;
    return ConfidenceLabel.low;
  }

  static List<String> _extractTags(String title, String body) {
    final text = '$title $body'.toLowerCase();
    final stopWords = {'the', 'a', 'an', 'is', 'in', 'on', 'at', 'to', 'of', 'and', 'or', 'for'};
    final words = text
        .replaceAll(RegExp(r'[^a-zA-Z0-9\s]'), '')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 4 && !stopWords.contains(w))
        .toSet()
        .take(10)
        .toList();
    return words;
  }

  Map<String, dynamic> toJson() => {
    'id':               id,
    'title':            title,
    'summary':          summary,
    'url':              url,
    'image_url':        imageUrl,
    'author':           author,
    'category':         category,
    'language':         language,
    'published_at':     publishedAt?.toIso8601String(),
    'fetched_at':       fetchedAt.toIso8601String(),
    'result_type':      resultType.name,
    'confidence':       confidence,
    'confidence_label': confidenceLabel.name,
    'freshness_score':  freshnessScore,
    'trust_score':      trustScore,
    'bias_flags':       biasFlags,
    'is_verified':      isVerified,
    'content_hash':     contentHash,
    'tags':             tags,
    'entities':         entities,
    'provenance':       provenance.toJson(),
  };
}

class AriaProvenance {
  final String sourceId;
  final String sourceName;
  final String sourceUrl;
  final DateTime fetchTimestamp;
  final String? license;
  final String adapterType;
  final String? attribution;

  AriaProvenance({
    required this.sourceId,
    required this.sourceName,
    required this.sourceUrl,
    required this.fetchTimestamp,
    this.license,
    required this.adapterType,
    this.attribution,
  });

  Map<String, dynamic> toJson() => {
    'source_id':       sourceId,
    'source_name':     sourceName,
    'source_url':      sourceUrl,
    'fetch_timestamp': fetchTimestamp.toIso8601String(),
    'license':         license,
    'adapter_type':    adapterType,
    'attribution':     attribution,
  };
}
