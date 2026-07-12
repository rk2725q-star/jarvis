import 'package:duckduckgo_search/duckduckgo_search.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/constants/category_constants.dart';
import '../../models/search_result_model.dart';

class DDGNewsSearchSource {
  final DuckDuckGoSearch _search = DuckDuckGoSearch();

  static const Map<String, double> _outletTrust = {
    'BBC': 0.90,
    'Reuters': 0.92,
    'AP': 0.91,
    'CNN': 0.72,
    'Fox News': 0.60,
    'Guardian': 0.82,
    'NYT': 0.80,
    'Bloomberg': 0.85,
  };

  Future<List<AriaSearchResult>> fetchCategoryNews({
    required AriaCategory category,
    int maxPerQuery = 5,
  }) async {
    final queries = CategoryConstants.defaultQueries[category] ?? [];
    final timeLimit = CategoryConstants.timeLimit[category] ?? 'w';
    final results = <AriaSearchResult>[];
    final seenHashes = <String>{};

    for (final query in queries.take(4)) {
      try {
        final newsItems = await _search.news(
          query,
          timelimit: timeLimit,
          region: ApiConstants.defaultRegion,
          maxResults: maxPerQuery,
        );

        for (final item in newsItems) {
          final itemMap = item as Map<String, dynamic>;
          final sourceName = itemMap['source']?.toString() ?? '';
          final trustScore = _outletTrust[sourceName] ?? 0.55;

          final result = AriaSearchResult.fromDDGNews(
            raw: itemMap,
            category: category.name,
            sourceTrustScore: trustScore,
          );

          if (!seenHashes.contains(result.contentHash)) {
            seenHashes.add(result.contentHash);
            results.add(result);
          }
        }

        await Future.delayed(
          const Duration(milliseconds: ApiConstants.minDelayBetweenRequestsMs),
        );
      } catch (e) {
        continue;
      }
    }

    results.sort((a, b) => b.freshnessScore.compareTo(a.freshnessScore));
    return results;
  }
}
