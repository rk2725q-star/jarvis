import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/category_constants.dart';
import '../providers/search_provider.dart';
import '../widgets/result_card_widget.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage>
    with TickerProviderStateMixin {
  final _searchController = TextEditingController();
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: AriaCategory.values.length,
      vsync: this,
    );
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(searchProvider);
    final selectedCategory = ref.watch(selectedCategoryProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        title: const Text(
          'ARIA — Real-Time Aggregator',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: AriaCategory.values
              .map((c) => Tab(text: CategoryConstants.labels[c] ?? c.name))
              .toList(),
          onTap: (i) => ref.read(selectedCategoryProvider.notifier).state =
              AriaCategory.values[i],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search real-time news...',
                filled: true,
                fillColor: const Color(0xFF21262D),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
              ),
              onSubmitted: (val) =>
                  ref.read(searchProvider.notifier).search(val),
            ),
          ),
          Expanded(child: _buildBody(selectedCategory, searchState)),
        ],
      ),
    );
  }

  Widget _buildBody(AriaCategory category, SearchState searchState) {
    if (searchState.isLoading)
      return const Center(child: CircularProgressIndicator());
    if (searchState.query.isNotEmpty) {
      return ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: searchState.results.length,
        itemBuilder: (ctx, i) =>
            ResultCardWidget(result: searchState.results[i]),
      );
    }

    final stream = ref.watch(categoryStreamProvider(category));
    return stream.when(
      data: (results) => ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: results.length,
        itemBuilder: (ctx, i) => ResultCardWidget(result: results[i]),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text('Error: $e', style: const TextStyle(color: Colors.red)),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }
}
