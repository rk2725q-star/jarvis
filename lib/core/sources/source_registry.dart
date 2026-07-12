import '../constants/category_constants.dart';

enum SourceType { rss, atom, restApi, jsonFeed }

enum SourceTier { official, licensed, public }

class AriaSource {
  final String id;
  final String name;
  final String feedUrl;
  final SourceType type;
  final SourceTier tier;
  final AriaCategory category;
  final double trustScore;
  final String? attribution;
  final int pollCadenceSeconds;

  const AriaSource({
    required this.id,
    required this.name,
    required this.feedUrl,
    required this.type,
    required this.tier,
    required this.category,
    required this.trustScore,
    this.attribution,
    required this.pollCadenceSeconds,
  });
}

class SourceRegistry {
  SourceRegistry._();

  static const List<AriaSource> all = [
    ...sports,
    ...technology,
    ...news,
    ...science,
    ...finance,
  ];

  static const List<AriaSource> sports = [
    AriaSource(
      id: 'bbc-sport',
      name: 'BBC Sport',
      feedUrl: 'https://feeds.bbci.co.uk/sport/rss.xml',
      type: SourceType.rss,
      tier: SourceTier.public,
      category: AriaCategory.sports,
      trustScore: 0.92,
      attribution: '© BBC Sport',
      pollCadenceSeconds: 120,
    ),
    AriaSource(
      id: 'espn-rss',
      name: 'ESPN Top News',
      feedUrl: 'https://www.espn.com/espn/rss/news',
      type: SourceType.rss,
      tier: SourceTier.public,
      category: AriaCategory.sports,
      trustScore: 0.87,
      attribution: '© ESPN',
      pollCadenceSeconds: 180,
    ),
  ];

  static const List<AriaSource> technology = [
    AriaSource(
      id: 'verge',
      name: 'The Verge',
      feedUrl: 'https://www.theverge.com/rss/index.xml',
      type: SourceType.atom,
      tier: SourceTier.public,
      category: AriaCategory.technology,
      trustScore: 0.88,
      attribution: '© The Verge',
      pollCadenceSeconds: 600,
    ),
    AriaSource(
      id: 'techcrunch',
      name: 'TechCrunch',
      feedUrl: 'https://techcrunch.com/feed/',
      type: SourceType.rss,
      tier: SourceTier.public,
      category: AriaCategory.technology,
      trustScore: 0.87,
      attribution: '© TechCrunch',
      pollCadenceSeconds: 600,
    ),
  ];

  static const List<AriaSource> news = [
    AriaSource(
      id: 'bbc-news-world',
      name: 'BBC World News',
      feedUrl: 'https://feeds.bbci.co.uk/news/world/rss.xml',
      type: SourceType.rss,
      tier: SourceTier.public,
      category: AriaCategory.news,
      trustScore: 0.93,
      attribution: '© BBC News',
      pollCadenceSeconds: 60,
    ),
    AriaSource(
      id: 'ap-top-news',
      name: 'AP Top News',
      feedUrl: 'https://feeds.apnews.com/rss/apf-topnews',
      type: SourceType.rss,
      tier: SourceTier.public,
      category: AriaCategory.news,
      trustScore: 0.96,
      attribution: '© The Associated Press',
      pollCadenceSeconds: 60,
    ),
  ];

  static const List<AriaSource> science = [
    AriaSource(
      id: 'nasa-breaking',
      name: 'NASA Breaking News',
      feedUrl: 'https://www.nasa.gov/news-release/feed/',
      type: SourceType.rss,
      tier: SourceTier.official,
      category: AriaCategory.science,
      trustScore: 0.98,
      attribution: '© NASA',
      pollCadenceSeconds: 3600,
    ),
  ];

  static const List<AriaSource> finance = [
    AriaSource(
      id: 'marketwatch',
      name: 'MarketWatch',
      feedUrl: 'https://www.marketwatch.com/rss/topstories',
      type: SourceType.rss,
      tier: SourceTier.public,
      category: AriaCategory.finance,
      trustScore: 0.85,
      attribution: '© MarketWatch',
      pollCadenceSeconds: 300,
    ),
  ];
}
