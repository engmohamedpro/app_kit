import 'dart:async';

import 'package:dio/dio.dart';

/// Centralized API client.
///
/// - No base URL: every call takes a full URL.
/// - Single shared Dio instance (connection reuse).
/// - Auto access-token header injection.
/// - Single-flight 401 -> refresh-token -> retry-once flow.
/// - Automatic retry with backoff for transient network errors.
/// - Tag-based CancelToken lifecycle for screen/controller cleanup.
/// - No logging (nothing printed, ever).
class AppAPI {
  AppAPI._();

  static const Duration _timeout = Duration(seconds: 20);

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: _timeout,
      receiveTimeout: _timeout,
      sendTimeout: _timeout,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      // 4xx comes back as a normal Response (we branch on status ourselves,
      // e.g. 401 -> refresh flow). Only 5xx/network failures throw.
      validateStatus: (status) => status != null && status < 500,
    ),
  )..interceptors.addAll([
      _AuthHeaderInterceptor(),
      _RetryInterceptor(),
    ]);

  static Dio get client => _dio;

  // ---------------- Auth token ----------------

  static void setAuthToken(String? token) => _AuthStore.token = token;

  /// Call once at app startup (e.g. in main() or after DI setup).
  ///
  /// [onRefreshToken] must call your refresh endpoint, store the new
  /// access token via [setAuthToken], and return true on success.
  /// [onAuthExpired] is invoked when refresh fails (e.g. force logout,
  /// navigate to login screen).
  static void configureAuth({
    required Future<bool> Function() onRefreshToken,
    required void Function() onAuthExpired,
  }) {
    _onRefreshToken = onRefreshToken;
    _onRefreshFailed = onAuthExpired;
  }

  static Future<bool> Function()? _onRefreshToken;
  static void Function()? _onRefreshFailed;

  // Single-flight refresh: concurrent 401s trigger exactly one refresh call.
  static bool _isRefreshing = false;
  static final List<Completer<bool>> _refreshWaiters = [];

  static Future<bool> _refreshAccessToken() async {
    if (_onRefreshToken == null) return false;

    if (_isRefreshing) {
      final completer = Completer<bool>();
      _refreshWaiters.add(completer);
      return completer.future;
    }

    _isRefreshing = true;
    bool success = false;
    try {
      success = await _onRefreshToken!.call();
    } catch (_) {
      success = false;
    } finally {
      _isRefreshing = false;
      for (final waiter in _refreshWaiters) {
        waiter.complete(success);
      }
      _refreshWaiters.clear();
    }
    return success;
  }

  // ---------------- Cancel token lifecycle ----------------

  static final Map<String, CancelToken> _cancelTokens = {};

  /// Get (or lazily create) a CancelToken bound to [tag] — typically a
  /// screen or controller identifier. Pass the same token to every
  /// request that screen makes.
  static CancelToken cancelToken(String tag) {
    final existing = _cancelTokens[tag];
    if (existing != null && !existing.isCancelled) return existing;
    final token = CancelToken();
    _cancelTokens[tag] = token;
    return token;
  }

  /// Cancel every in-flight request registered under [tag].
  /// Call this from the screen/controller's dispose().
  static void cancelByTag(String tag) {
    _cancelTokens.remove(tag)?.cancel('Cancelled: $tag disposed');
  }

  /// Cancel and clear every tracked CancelToken (e.g. on full logout).
  static void cancelAll() {
    for (final token in _cancelTokens.values) {
      if (!token.isCancelled) token.cancel('Cancelled: app-wide cancelAll');
    }
    _cancelTokens.clear();
  }

  // ---------------- Public API ----------------

  static Future<void> get(
    String url, {
    Map<String, dynamic>? query,
    Options? options,
    CancelToken? cancelToken,
    required void Function(dynamic data) onSuccess,
    required void Function(dynamic error, int? statusCode) onError,
  }) {
    return _request(
      () => _dio.get(url,
          queryParameters: query, options: options, cancelToken: cancelToken),
      onSuccess,
      onError,
    );
  }

  static Future<void> post(
    String url, {
    dynamic body,
    Map<String, dynamic>? query,
    Options? options,
    CancelToken? cancelToken,
    required void Function(dynamic data) onSuccess,
    required void Function(dynamic error, int? statusCode) onError,
  }) {
    return _request(
      () => _dio.post(url,
          data: body,
          queryParameters: query,
          options: options,
          cancelToken: cancelToken),
      onSuccess,
      onError,
    );
  }

  static Future<void> put(
    String url, {
    dynamic body,
    Map<String, dynamic>? query,
    Options? options,
    CancelToken? cancelToken,
    required void Function(dynamic data) onSuccess,
    required void Function(dynamic error, int? statusCode) onError,
  }) {
    return _request(
      () => _dio.put(url,
          data: body,
          queryParameters: query,
          options: options,
          cancelToken: cancelToken),
      onSuccess,
      onError,
    );
  }

  static Future<void> patch(
    String url, {
    dynamic body,
    Map<String, dynamic>? query,
    Options? options,
    CancelToken? cancelToken,
    required void Function(dynamic data) onSuccess,
    required void Function(dynamic error, int? statusCode) onError,
  }) {
    return _request(
      () => _dio.patch(url,
          data: body,
          queryParameters: query,
          options: options,
          cancelToken: cancelToken),
      onSuccess,
      onError,
    );
  }

  static Future<void> delete(
    String url, {
    dynamic body,
    Map<String, dynamic>? query,
    Options? options,
    CancelToken? cancelToken,
    required void Function(dynamic data) onSuccess,
    required void Function(dynamic error, int? statusCode) onError,
  }) {
    return _request(
      () => _dio.delete(url,
          data: body,
          queryParameters: query,
          options: options,
          cancelToken: cancelToken),
      onSuccess,
      onError,
    );
  }

  /// Multipart upload with progress reporting.
  static Future<void> upload(
    String url, {
    required FormData formData,
    void Function(int sent, int total)? onSendProgress,
    CancelToken? cancelToken,
    required void Function(dynamic data) onSuccess,
    required void Function(dynamic error, int? statusCode) onError,
  }) {
    return _request(
      () => _dio.post(url,
          data: formData,
          onSendProgress: onSendProgress,
          cancelToken: cancelToken),
      onSuccess,
      onError,
    );
  }

  // ---------------- Core ----------------

  static Future<void> _request(
    Future<Response> Function() call,
    void Function(dynamic data) onSuccess,
    void Function(dynamic error, int? statusCode) onError, {
    bool isRetryAfterRefresh = false,
  }) async {
    try {
      final response = await call();
      final status = response.statusCode ?? 0;

      if (status >= 200 && status < 300) {
        onSuccess(response.data);
        return;
      }

      if (status == 401 && !isRetryAfterRefresh && _onRefreshToken != null) {
        final refreshed = await _refreshAccessToken();
        if (refreshed) {
          // Retry the original request once, now with the new token
          // (picked up automatically by _AuthHeaderInterceptor).
          return _request(call, onSuccess, onError, isRetryAfterRefresh: true);
        }
        _onRefreshFailed?.call();
      }

      onError(_asJson(response.data, fallbackMessage: 'Request failed'), status);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) return;
      onError(_mapDioError(e), e.response?.statusCode);
    } catch (e) {
      onError({'message': 'Unexpected error: $e'}, null);
    }
  }

  /// Normalizes any error payload into a JSON-shaped Map/List so `onError`
  /// always hands back something consistent, even for timeouts / no
  /// connection where the server never responded.
  static dynamic _asJson(dynamic data, {required String fallbackMessage}) {
    if (data is Map || data is List) return data;
    if (data is String && data.isNotEmpty) return {'message': data};
    return {'message': fallbackMessage};
  }

  static dynamic _mapDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return {'message': 'Connection timeout. Please try again.'};
      case DioExceptionType.badResponse:
        return _asJson(
          e.response?.data,
          fallbackMessage: 'Server error (${e.response?.statusCode}).',
        );
      case DioExceptionType.connectionError:
        return {'message': 'No internet connection.'};
      case DioExceptionType.cancel:
        return {'message': 'Request cancelled.'};
      default:
        return {'message': e.message ?? 'Something went wrong.'};
    }
  }
}

class _AuthHeaderInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = _AuthStore.token;
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }
}

class _AuthStore {
  static String? token;
}

/// Retries transient failures (timeouts, no connection, 5xx) with linear
/// backoff. Only retries idempotent-by-default methods (GET, PUT, DELETE,
/// HEAD) to avoid duplicating side effects like double-charging on POST.
/// To allow retrying a POST/PATCH you know is safe (e.g. idempotency-key
/// backed), pass `options: Options(extra: {'idempotent': true})`.
class _RetryInterceptor extends Interceptor {
  static const int maxRetries = 2;
  static const Duration baseDelay = Duration(milliseconds: 500);
  static const _safeMethods = {'GET', 'PUT', 'DELETE', 'HEAD'};

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final options = err.requestOptions;
    final retryCount = (options.extra['retryCount'] as int?) ?? 0;
    final isIdempotent = _safeMethods.contains(options.method.toUpperCase()) ||
        options.extra['idempotent'] == true;

    if (isIdempotent && _isTransient(err) && retryCount < maxRetries) {
      options.extra['retryCount'] = retryCount + 1;
      await Future.delayed(baseDelay * (retryCount + 1));
      try {
        final response = await AppAPI._dio.fetch(options);
        return handler.resolve(response);
      } catch (_) {
        // Fall through: let the (possibly next-level) retry / error path handle it.
      }
    }
    handler.next(err);
  }

  bool _isTransient(DioException err) {
    switch (err.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return true;
      case DioExceptionType.badResponse:
        return (err.response?.statusCode ?? 0) >= 500;
      default:
        return false;
    }
  }
}