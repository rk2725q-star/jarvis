import 'package:hive_flutter/hive_flutter.dart';
import '../core/constants/category_constants.dart';
import '../data/models/search_result_model.dart';

class CacheService {
  final Map<String, _CacheEntry> _hotCache = {};

  static const Map<AriaCategory, Duration> _categoryTTL = {
    AriaCategory.sports: Duration(minutes: 2),
    AriaCategory.news: Duration(minutes: 2),
    AriaCategory.finance: Duration(minutes: 5),
    AriaCategory.technology: Duration(minutes: 15),
    AriaCategory.health: Duration(minutes: 15),
    AriaCategory.environment: Duration(minutes: 30),
    AriaCategory.science: Duration(hours: 1),
    AriaCategory.culture: Duration(hours: 6),
  };

  static const Duration _defaultTTL = Duration(minutes: 15);

  late Box _hiveBox;
  bool _hiveInitialized = false;

  Future<void> init() async {
    await Hive.initFlutter();
    _hiveBox = await Hive.openBox('aria_cache');
    _hiveInitialized = true;
  }

  Future<List<AriaSearchResult>?> getCategory(AriaCategory category) async {
    final key = 'category:${category.name}';
    return _get(key);
  }

  Future<void> setCategory(
    AriaCategory category,
    List<AriaSearchResult> results,
  ) async {
    final key = 'category:${category.name}';
    final ttl = _categoryTTL[category] ?? _defaultTTL;
    await _set(key, results, ttl: ttl);
  }

  Future<List<AriaSearchResult>?> get(String key) async {
    return _get(key);
  }

  Future<void> set(
    String key,
    List<AriaSearchResult> results, {
    Duration ttl = const Duration(minutes: 15),
  }) async {
    await _set(key, results, ttl: ttl);
  }

  Future<List<AriaSearchResult>?> _get(String key) async {
    final hot = _hotCache[key];
    if (hot != null && !hot.isExpired) {
      return hot.results;
    }

    if (_hiveInitialized && _hiveBox.containsKey(key)) {
      try {
        final raw = _hiveBox.get(key) as Map?;
        if (raw != null) {
          final expiry = DateTime.parse(raw['expiry'].toString());
          if (DateTime.now().isBefore(expiry)) {
            final jsonList = raw['results'] as List;
            final results = jsonList
                .map((j) => _fromJson(Map<String, dynamic>.from(j)))
                .toList();
            _hotCache[key] = _CacheEntry(results: results, expiry: expiry);
            return results;
          }
        }
      } catch (_) {}
    }
    return null;
  }

  Future<void> _set(
    String key,
    List<AriaSearchResult> results, {
    required Duration ttl,
  }) async {
    final expiry = DateTime.now().add(ttl);
    _hotCache[key] = _CacheEntry(results: results, expiry: expiry);

    if (_hiveInitialized) {
      try {
        await _hiveBox.put(key, {
          'expiry': expiry.toIso8601String(),
          'results': results.map((r) => r.toJson()).toList(),
        });
      } catch (_) {}
    }
  }

  AriaSearchResult _fromJson(Map<String, dynamic> json) {
    return AriaSearchResult(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      summary: json['summary']?.toString(),
      url: json['url']?.toString() ?? '',
      category: json['category']?.toString() ?? '',
      language: json['language']?.toString() ?? 'en',
      fetchedAt:
          DateTime.tryParse(json['fetched_at']?.toString() ?? '') ??
          DateTime.now(),
      publishedAt: json['published_at'] != null
          ? DateTime.tryParse(json['published_at'])
          : null,
      resultType: ResultType.values.firstWhere(
        (e) => e.name == json['result_type'],
        orElse: () => ResultType.text,
      ),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.5,
      confidenceLabel: ConfidenceLabel.values.firstWhere(
        (e) => e.name == json['confidence_label'],
        orElse: () => ConfidenceLabel.medium,
      ),
      freshnessScore: (json['freshness_score'] as num?)?.toDouble() ?? 1.0,
      trustScore: (json['trust_score'] as num?)?.toDouble() ?? 0.5,
      contentHash: json['content_hash']?.toString() ?? '',
      provenance: AriaProvenance(
        sourceId: 'cache',
        sourceName: 'Cache',
        sourceUrl: '',
        fetchTimestamp: DateTime.now(),
        adapterType: 'cache',
      ),
    );
  }

  void dispose() {
    _hotCache.clear();
  }
}

class _CacheEntry {
  final List<AriaSearchResult> results;
  final DateTime expiry;
  _CacheEntry({required this.results, required this.expiry});
  bool get isExpired => DateTime.now().isAfter(expiry);
}
