import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiClient {
  static ApiClient? _instance;
  late final Dio _dio;
  final _storage = const FlutterSecureStorage();

  ApiClient._() {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
      sendTimeout: const Duration(seconds: 30),
    ))
      ..interceptors.add(LogInterceptor(responseBody: false))
      ..interceptors.add(_RetryInterceptor(retries: 3));
  }

  static ApiClient get instance => _instance ??= ApiClient._();

  /// GET request with cancellation support
  Future<Response<T>> get<T>(
    String url, {
    Map<String, dynamic>? queryParams,
    CancelToken? cancelToken,
    ResponseType responseType = ResponseType.json,
  }) async {
    try {
      return await _dio.get<T>(
        url,
        queryParameters: queryParams,
        cancelToken: cancelToken,
        options: Options(responseType: responseType),
      );
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  /// Fetch image as bytes
  Future<List<int>> fetchImageBytes(
    String url, {
    CancelToken? cancelToken,
  }) async {
    if (url.startsWith('data:image/')) {
      try {
        final base64String = url.split(',').last;
        return base64Decode(base64String);
      } catch (e) {
        throw ApiException('Failed to parse base64 image: $e');
      }
    }

    final response = await _dio.get<List<int>>(
      url,
      cancelToken: cancelToken,
      options: Options(responseType: ResponseType.bytes),
    );
    if (response.data == null) throw ApiException('Empty image response');
    return response.data!;
  }

  Future<void> storeApiKey(String provider, String key) =>
      _storage.write(key: 'api_key_$provider', value: key);

  Future<String?> getApiKey(String provider) =>
      _storage.read(key: 'api_key_$provider');

  ApiException _mapError(DioException e) => switch (e.type) {
    DioExceptionType.connectionTimeout => ApiException('Connection timeout. Check internet.'),
    DioExceptionType.receiveTimeout    => ApiException('Server took too long. Try again.'),
    DioExceptionType.cancel            => ApiException('Request cancelled.', isCancelled: true),
    _                                  => ApiException(e.message ?? 'Unknown error'),
  };
}

class ApiException implements Exception {
  final String message;
  final bool isCancelled;
  const ApiException(this.message, {this.isCancelled = false});
  @override String toString() => message;
}

class _RetryInterceptor extends Interceptor {
  final int retries;
  _RetryInterceptor({required this.retries});

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final extra = err.requestOptions.extra;
    final retryCount = (extra['retryCount'] as int?) ?? 0;

    if (retryCount < retries && _isRetryable(err)) {
      err.requestOptions.extra['retryCount'] = retryCount + 1;
      await Future.delayed(Duration(seconds: retryCount + 1));
      try {
        final dio = Dio();
        final response = await dio.fetch(err.requestOptions);
        return handler.resolve(response);
      } catch (_) {}
    }
    handler.next(err);
  }

  bool _isRetryable(DioException e) =>
    e.type == DioExceptionType.connectionTimeout ||
    e.type == DioExceptionType.receiveTimeout ||
    (e.response?.statusCode ?? 0) >= 500;
}
