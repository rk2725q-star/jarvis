import 'dart:math' as math;
import '../data/models/search_result_model.dart';

class RankingService {
  List<AriaSearchResult> rank(List<AriaSearchResult> results) {
    final scored = results.map((r) {
      final score = _compositeScore(r);
      return _ResultWithScore(result: r, score: score);
    }).toList();

    scored.sort((a, b) => b.score.compareTo(a.score));

    return scored.map((s) => s.result).toList();
  }

  double _compositeScore(AriaSearchResult result) {
    double freshness = result.freshnessScore;
    if (result.publishedAt != null) {
      final hoursOld = DateTime.now()
          .difference(result.publishedAt!)
          .inHours
          .toDouble();
      freshness = math.exp(-0.1 * hoursOld).clamp(0.01, 1.0);
    }

    final typeBonus = result.resultType == ResultType.instantAnswer
        ? 0.10
        : 0.0;
    final verifiedBonus = result.isVerified ? 0.05 : 0.0;
    final biasPenalty = result.biasFlags.length * 0.05;

    final score =
        (result.trustScore * 0.35) +
        (0.60 * 0.30) + // corroboration stub
        (freshness * 0.20) +
        (result.confidence * 0.15) +
        typeBonus +
        verifiedBonus -
        biasPenalty;

    return score.clamp(0.0, 1.0);
  }
}

class _ResultWithScore {
  final AriaSearchResult result;
  final double score;
  _ResultWithScore({required this.result, required this.score});
}
