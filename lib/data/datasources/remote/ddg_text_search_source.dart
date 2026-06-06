import 'package:duckduckgo_search/duckduckgo_search.dart';
import '../../../core/constants/api_constants.dart';
import '../../models/search_result_model.dart';

class DDGTextSearchSource {
  final DuckDuckGoSearch _search = DuckDuckGoSearch();

  Future<List<AriaSearchResult>> search({
    required String query,
    required String category,
    String region   = 'wt-wt',
    String? timelimit,
    int maxResults = 20,
    double sourceTrustScore = 0.60,
  }) async {
    final results = <AriaSearchResult>[];

    try {
      final rawResults = await _search.text(
        query,
        region:      region,
        safesearch:  ApiConstants.defaultSafeSearch,
        timelimit:   timelimit,
        maxResults:  maxResults,
      );

      for (final item in rawResults) {
        final itemMap = item as Map<String, dynamic>;
        results.add(
          AriaSearchResult.fromDDGText(
            raw: itemMap,
            category: category,
            sourceTrustScore: sourceTrustScore,
          ),
        );
      }
    } catch (e) {
      // Empty list on error
    }

    return results;
  }

  Future<List<AriaSearchResult>> multiQuerySearch({
    required List<String> queries,
    required String category,
    int maxPerQuery = 5,
    String? timelimit,
  }) async {
    final allResults = <AriaSearchResult>[];
    final seenHashes = <String>{};

    for (final query in queries) {
      final results = await search(
        query:        query,
        category:     category,
        maxResults:   maxPerQuery,
        timelimit:    timelimit,
      );

      for (final r in results) {
        if (!seenHashes.contains(r.contentHash)) {
          seenHashes.add(r.contentHash);
          allResults.add(r);
        }
      }

      await Future.delayed(
        const Duration(milliseconds: ApiConstants.minDelayBetweenRequestsMs),
      );
    }

    return allResults;
  }
}
