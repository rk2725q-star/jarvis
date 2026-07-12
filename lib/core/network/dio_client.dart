import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:logger/logger.dart';
import '../constants/api_constants.dart';

// ═══════════════════════════════════════════════════════════
// ARIA SYSTEM — Base Dio HTTP Client
// Handles: timeouts, retries, caching, user-agent, logging
// ═══════════════════════════════════════════════════════════

class DioClient {
  static DioClient? _instance;
  late final Dio _dio;
  late final CacheOptions _cacheOptions;
  final Logger _logger = Logger();

  DioClient._internal() {
    _cacheOptions = CacheOptions(
      store: MemCacheStore(),
      policy: CachePolicy.request,
      hitCacheOnErrorExcept: [401, 403],
      maxStale: const Duration(minutes: 15),
      priority: CachePriority.normal,
      keyBuilder: CacheOptions.defaultCacheKeyBuilder,
      allowPostMethod: false,
    );

    _dio = Dio(
      BaseOptions(
        connectTimeout: Duration(milliseconds: ApiConstants.connectTimeoutMs),
        receiveTimeout: Duration(milliseconds: ApiConstants.receiveTimeoutMs),
        headers: {
          'User-Agent': ApiConstants.userAgent,
          'Accept': 'application/json',
          'Accept-Language': 'en-US,en;q=0.9',
        },
      ),
    );

    _dio.interceptors.addAll([
      DioCacheInterceptor(options: _cacheOptions),
      _RetryInterceptor(dio: _dio, logger: _logger),
      _LoggingInterceptor(logger: _logger),
      _RateLimitInterceptor(),
    ]);
  }

  factory DioClient() {
    _instance ??= DioClient._internal();
    return _instance!;
  }

  Dio get dio => _dio;
}

// ── Retry Interceptor (exponential backoff)
class _RetryInterceptor extends Interceptor {
  final Dio dio;
  final Logger logger;
  int _attempt = 0;

  _RetryInterceptor({required this.dio, required this.logger});

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (_shouldRetry(err) && _attempt < ApiConstants.maxRetries) {
      _attempt++;
      // Exponential backoff: 1s, 2s, 4s... capped at 30s for this mobile context
      final waitMs = (ApiConstants.baseBackoffMs * (1 << (_attempt - 1))).clamp(
        0,
        30000,
      );
      logger.w('Retry attempt $_attempt after ${waitMs}ms');
      await Future.delayed(Duration(milliseconds: waitMs));
      try {
        final response = await dio.fetch(err.requestOptions);
        handler.resolve(response);
        _attempt = 0;
        return;
      } catch (e) {
        // Continue to next retry
      }
    }
    _attempt = 0;
    handler.next(err);
  }

  bool _shouldRetry(DioException err) {
    return err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.connectionError ||
        (err.response?.statusCode == 429) || // Rate limited
        (err.response?.statusCode == 503); // Service unavailable
  }
}

// ── Rate Limit Interceptor (token bucket)
class _RateLimitInterceptor extends Interceptor {
  static DateTime _lastRequest = DateTime.now();

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final now = DateTime.now();
    final elapsed = now.difference(_lastRequest).inMilliseconds;
    if (elapsed < ApiConstants.minDelayBetweenRequestsMs) {
      final delay = ApiConstants.minDelayBetweenRequestsMs - elapsed;
      await Future.delayed(Duration(milliseconds: delay));
    }
    _lastRequest = DateTime.now();
    handler.next(options);
  }
}

// ── Logging Interceptor
class _LoggingInterceptor extends Interceptor {
  final Logger logger;
  _LoggingInterceptor({required this.logger});

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    logger.d('→ ${options.method} ${options.uri}');
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    logger.d('← ${response.statusCode} ${response.requestOptions.uri}');
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    logger.e('✗ ${err.response?.statusCode} ${err.requestOptions.uri}');
    handler.next(err);
  }
}
