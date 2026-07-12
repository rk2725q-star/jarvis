import 'dart:async';
import 'package:rxdart/rxdart.dart';
import '../core/constants/category_constants.dart';
import '../data/datasources/remote/ddg_instant_answer_source.dart';
import '../data/datasources/remote/ddg_news_search_source.dart';
import '../data/models/search_result_model.dart';
import 'dedup_service.dart';
import 'ranking_service.dart';
import 'package:duckduckgo_search/duckduckgo_search.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// AggregatorService — On-demand, no background scheduler timers.
/// Background timers were the #1 cause of typing freeze and ANR.
/// All fetches are on-demand with strict per-source timeouts.
/// ─────────────────────────────────────────────────────────────────────────────
class AggregatorService {
  final DDGInstantAnswerSource _instantAnswerSource;
  final DDGNewsSearchSource _newsSource;
  final DedupService _dedup;
  final RankingService _ranking;

  /// Per-category BehaviorSubjects for UI streams (populated on first fetch).
  final Map<AriaCategory, BehaviorSubject<List<AriaSearchResult>>>
  _categoryStreams = {};

  AggregatorService({
    DDGInstantAnswerSource? instantAnswerSource,
    DDGNewsSearchSource? newsSource,
    DedupService? dedup,
    RankingService? ranking,
  }) : _instantAnswerSource = instantAnswerSource ?? DDGInstantAnswerSource(),
       _newsSource = newsSource ?? DDGNewsSearchSource(),
       _dedup = dedup ?? DedupService(),
       _ranking = ranking ?? RankingService();

  /// No-op init — no background schedulers, keeps startup instant.
  Future<void> initialize() async {}

  // ─────────────────────────────────────────────────────────────────────────
  // Category Stream — used by Riverpod categoryStreamProvider.
  // Lazily creates the stream and triggers a one-time fetch if empty.
  // ─────────────────────────────────────────────────────────────────────────
  Stream<List<AriaSearchResult>> categoryStream(AriaCategory category) {
    _categoryStreams.putIfAbsent(
      category,
      () => BehaviorSubject<List<AriaSearchResult>>(),
    );
    final subject = _categoryStreams[category]!;
    // Trigger background fetch if stream has no data yet
    if (!subject.hasValue) {
      _refreshCategoryInBackground(category);
    }
    return subject.stream;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Fetch Category — on-demand fetch with strict 10s total timeout.
  // Used by SearchNotifier and AgenticaEngine._ariaSearch.
  // ─────────────────────────────────────────────────────────────────────────
  Future<List<AriaSearchResult>> fetchCategory({
    required AriaCategory category,
    bool forceRefresh = false,
    int limit = 20,
  }) async {
    final results = await _fetchForCategory(
      category,
    ).timeout(const Duration(seconds: 10), onTimeout: () => []);
    // Update the stream so UI widgets reflect fresh data
    _categoryStreams[category]?.add(results);
    return results.take(limit).toList();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Live Query Search — runs text + news in parallel, 5s hard cap.
  // Used by ChatProvider for per-message real-time grounding.
  // ─────────────────────────────────────────────────────────────────────────
  Future<List<AriaSearchResult>> searchUserQuery(
    String query, {
    int limit = 6,
  }) async {
    final results = <AriaSearchResult>[];

    await Future.wait([
      _fetchDDGText(query, results, limit),
      _fetchDDGNews(query, results, limit),
      _fetchInstantAnswer(query, results),
    ], eagerError: false).timeout(
      const Duration(seconds: 5),
      onTimeout: () => [],
    );

    if (results.isEmpty) return [];
    final deduped = _dedup.deduplicate(results);
    return _ranking.rank(deduped).take(limit).toList();
  }

  // ─── Private helpers ──────────────────────────────────────────────────────

  void _refreshCategoryInBackground(AriaCategory category) {
    _fetchForCategory(category)
        .timeout(const Duration(seconds: 12), onTimeout: () => [])
        .then((results) {
          if (results.isNotEmpty) {
            _categoryStreams[category]?.add(results);
          }
        })
        .catchError((_) {});
  }

  Future<List<AriaSearchResult>> _fetchForCategory(
    AriaCategory category,
  ) async {
    final allResults = <AriaSearchResult>[];
    final queries = CategoryConstants.defaultQueries[category] ?? [];

    // Search top 3 queries via DDG text for real-time accuracy (tech/AI/etc)
    for (final q in queries.take(3)) {
      try {
        final search = DuckDuckGoSearch();
        final items = await search
            .text(q, maxResults: 3)
            .timeout(const Duration(seconds: 5));
        for (final item in items) {
          allResults.add(
            AriaSearchResult.fromDDGText(
              raw: item as Map<String, dynamic>,
              category: category.name,
              sourceTrustScore: 0.78,
            ),
          );
        }
      } catch (_) {}
    }

    // Fetch DDG news (timeLimit is handled internally by fetchCategoryNews
    // via CategoryConstants.timeLimit — 'd' for breaking news, 'w' for tech etc.)
    try {
      final newsItems = await _newsSource
          .fetchCategoryNews(category: category, maxPerQuery: 3)
          .timeout(const Duration(seconds: 6));
      allResults.addAll(newsItems);
    } catch (_) {}

    // Instant answer for the top query
    if (queries.isNotEmpty) {
      try {
        final instant = await _instantAnswerSource
            .fetchInstantAnswer(query: queries.first, category: category.name)
            .timeout(const Duration(seconds: 4));
        if (instant != null) allResults.insert(0, instant);
      } catch (_) {}
    }

    final deduped = _dedup.deduplicate(allResults);
    return _ranking.rank(deduped);
  }

  Future<void> _fetchDDGText(
    String query,
    List<AriaSearchResult> out,
    int limit,
  ) async {
    try {
      final search = DuckDuckGoSearch();
      final items = await search
          .text(query, maxResults: limit)
          .timeout(const Duration(seconds: 4));
      for (final item in items) {
        out.add(
          AriaSearchResult.fromDDGText(
            raw: item as Map<String, dynamic>,
            category: 'Search',
            sourceTrustScore: 0.80,
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _fetchDDGNews(
    String query,
    List<AriaSearchResult> out,
    int limit,
  ) async {
    try {
      final search = DuckDuckGoSearch();
      final items = await search
          .news(query, maxResults: limit)
          .timeout(const Duration(seconds: 4));
      for (final item in items) {
        out.add(
          AriaSearchResult.fromDDGNews(
            raw: item as Map<String, dynamic>,
            category: 'Search',
            sourceTrustScore: 0.82,
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _fetchInstantAnswer(
    String query,
    List<AriaSearchResult> out,
  ) async {
    try {
      final result = await _instantAnswerSource
          .fetchInstantAnswer(query: query, category: 'General')
          .timeout(const Duration(seconds: 3));
      if (result != null) out.insert(0, result);
    } catch (_) {}
  }

  void dispose() {
    for (final c in _categoryStreams.values) {
      c.close();
    }
  }
}
