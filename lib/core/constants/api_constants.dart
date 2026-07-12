// ═══════════════════════════════════════════════════════════
// ARIA SYSTEM — API Constants
// DuckDuckGo Endpoints & Configuration
// ═══════════════════════════════════════════════════════════

class ApiConstants {
  ApiConstants._();

  // ── DuckDuckGo Instant Answer API (FREE, no key needed)
  static const String ddgInstantAnswerBase = 'https://api.duckduckgo.com/';

  // ── DDG Lite HTML endpoint
  static const String ddgLiteBase = 'https://lite.duckduckgo.com/lite/';

  // ── DDG HTML endpoint
  static const String ddgHtmlBase = 'https://html.duckduckgo.com/html/';

  // ── DDG Autocomplete/Suggestions API
  static const String ddgSuggestBase = 'https://ac.duckduckgo.com/ac/';

  // ── User-Agent (ethical bot identification)
  static const String userAgent =
      'JARVIS-ARIA-Aggregator/1.0 (+https://jarvis.ai/bot)';

  // ── Request timeouts
  static const int connectTimeoutMs = 10000;
  static const int receiveTimeoutMs = 15000;

  // ── Rate limits (60% of DDG's allowed rate)
  static const int maxRequestsPerMinute = 20;
  static const int minDelayBetweenRequestsMs = 3000;

  // ── Retry config
  static const int maxRetries = 3;
  static const int baseBackoffMs = 1000;

  // ── Default search params
  static const String defaultRegion = 'wt-wt'; // worldwide
  static const String defaultSafeSearch = 'moderate';
  static const int defaultMaxResults = 20;
}
