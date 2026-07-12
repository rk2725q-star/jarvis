import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/category_constants.dart';
import '../../data/models/search_result_model.dart';
import '../../services/aggregator_service.dart';

final aggregatorProvider = Provider<AggregatorService>((ref) {
  final service = AggregatorService();
  ref.onDispose(service.dispose);
  return service;
});

final aggregatorInitProvider = FutureProvider<void>((ref) async {
  final aggregator = ref.watch(aggregatorProvider);
  await aggregator.initialize();
});

final selectedCategoryProvider = StateProvider<AriaCategory>(
  (ref) => AriaCategory.news,
);

final categoryStreamProvider =
    StreamProvider.family<List<AriaSearchResult>, AriaCategory>((
      ref,
      category,
    ) {
      final aggregator = ref.watch(aggregatorProvider);
      return aggregator.categoryStream(category);
    });

class SearchState {
  final String query;
  final bool isLoading;
  final List<AriaSearchResult> results;
  final String? error;

  const SearchState({
    this.query = '',
    this.isLoading = false,
    this.results = const [],
    this.error,
  });

  SearchState copyWith({
    String? query,
    bool? isLoading,
    List<AriaSearchResult>? results,
    String? error,
  }) => SearchState(
    query: query ?? this.query,
    isLoading: isLoading ?? this.isLoading,
    results: results ?? this.results,
    error: error,
  );
}

class SearchNotifier extends StateNotifier<SearchState> {
  final AggregatorService _aggregator;
  SearchNotifier(this._aggregator) : super(const SearchState());

  Future<void> search(String query) async {
    if (query.trim().isEmpty) return;
    state = state.copyWith(query: query, isLoading: true, error: null);
    try {
      final results = await _aggregator.searchUserQuery(query, limit: 10);
      state = state.copyWith(isLoading: false, results: results);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }
}

final searchProvider = StateNotifierProvider<SearchNotifier, SearchState>((
  ref,
) {
  final aggregator = ref.watch(aggregatorProvider);
  return SearchNotifier(aggregator);
});
