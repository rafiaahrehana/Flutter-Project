import 'package:dio/dio.dart';

import '../config/env.dart';
import '../storage/secure_store.dart';
import 'api_exception.dart';
import 'auth_interceptor.dart';
import 'paged_response.dart';

/// The app's single HTTP entry point — the Flutter counterpart of Angular's
/// `ApiService` plus its two interceptors.
///
/// Every method funnels failures through [ApiException.from], so callers deal
/// in one error type and never import Dio.
class ApiClient {
  ApiClient({
    required SecureStore store,
    required Future<void> Function() onSessionExpired,
    void Function()? onTokensRefreshed,
  }) {
    dio = Dio(_baseOptions());

    // No interceptors, deliberately: this is what refreshes the token, so it
    // must not be subject to the refresh-on-401 rule itself.
    final refreshDio = Dio(_baseOptions());

    dio.interceptors.add(
      AuthInterceptor(
        store: store,
        dio: () => dio,
        refreshDio: refreshDio,
        onSessionExpired: onSessionExpired,
        onTokensRefreshed: onTokensRefreshed,
      ),
    );
  }

  late final Dio dio;

  static BaseOptions _baseOptions() => BaseOptions(
        baseUrl: Env.apiUrl,
        connectTimeout: Env.connectTimeout,
        receiveTimeout: Env.receiveTimeout,
        // Let every non-2xx reach the interceptor as a DioException so the
        // 401 path is the only place that decides what a 401 means.
        validateStatus: (status) => status != null && status >= 200 && status < 300,
      );

  // ── JSON ────────────────────────────────────────────────────

  Future<T> get<T>(String path, {Map<String, dynamic>? query}) =>
      _guard(() async {
        final res = await dio.get<T>(path, queryParameters: _clean(query));
        return res.data as T;
      });

  Future<T> post<T>(String path, [Object? body]) => _guard(() async {
        final res = await dio.post<T>(path, data: body ?? const {});
        return res.data as T;
      });

  Future<T> put<T>(String path, [Object? body]) => _guard(() async {
        final res = await dio.put<T>(path, data: body ?? const {});
        return res.data as T;
      });

  Future<T> patch<T>(String path, [Object? body]) => _guard(() async {
        final res = await dio.patch<T>(path, data: body ?? const {});
        return res.data as T;
      });

  Future<T> delete<T>(String path) => _guard(() async {
        final res = await dio.delete<T>(path);
        return res.data as T;
      });

  // ── text/plain ──────────────────────────────────────────────
  // Several endpoints declare ResponseEntity<String>. Asking Dio to decode
  // those as JSON turns a successful 200 into a parse failure.

  Future<String> postText(String path, [Object? body]) => _guard(() async {
        final res = await dio.post<String>(
          path,
          data: body ?? const {},
          options: Options(responseType: ResponseType.plain),
        );
        return res.data ?? '';
      });

  Future<String> patchText(String path, [Object? body]) => _guard(() async {
        final res = await dio.patch<String>(
          path,
          data: body ?? const {},
          options: Options(responseType: ResponseType.plain),
        );
        return res.data ?? '';
      });

  Future<String> deleteText(String path) => _guard(() async {
        final res = await dio.delete<String>(
          path,
          options: Options(responseType: ResponseType.plain),
        );
        return res.data ?? '';
      });

  // ── Binary ──────────────────────────────────────────────────

  /// For generated documents (payslip PDFs, report exports).
  Future<List<int>> getBytes(String path, {Map<String, dynamic>? query}) =>
      _guard(() async {
        final res = await dio.get<List<int>>(
          path,
          queryParameters: _clean(query),
          options: Options(responseType: ResponseType.bytes),
        );
        return res.data ?? const <int>[];
      });

  // ── Paging ──────────────────────────────────────────────────

  Future<PagedResponse<T>> getPaged<T>(
    String path,
    T Function(Map<String, dynamic>) fromItem, {
    int page = 0,
    int size = 20,
    Map<String, dynamic>? query,
  }) =>
      _guard(() async {
        final res = await dio.get<dynamic>(
          path,
          queryParameters: {
            'page': page < 0 ? 0 : page,
            'size': size <= 0 ? 20 : size,
            ...?_clean(query),
          },
        );
        return PagedResponse<T>.fromJson(
          res.data,
          fromItem,
          fallbackPage: page,
          fallbackSize: size,
        );
      });

  // ── Helpers ─────────────────────────────────────────────────

  /// Drops null/empty params so an unset filter doesn't become `?status=null`,
  /// which the backend would try to parse as a real value.
  static Map<String, dynamic>? _clean(Map<String, dynamic>? query) {
    if (query == null) return null;
    final cleaned = <String, dynamic>{};
    query.forEach((key, value) {
      if (value == null) return;
      if (value is String && value.trim().isEmpty) return;
      cleaned[key] = value;
    });
    return cleaned.isEmpty ? null : cleaned;
  }

  static Future<T> _guard<T>(Future<T> Function() request) async {
    try {
      return await request();
    } catch (error, stackTrace) {
      throw ApiException.from(error, stackTrace);
    }
  }
}
