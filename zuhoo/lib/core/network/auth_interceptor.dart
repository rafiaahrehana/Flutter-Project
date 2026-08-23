// Dart has no private *named* parameters, so the fields below cannot be filled
// by initialising formals however much the lint would like them to be.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:dio/dio.dart';

import '../storage/secure_store.dart';

/// Attaches the bearer token, and transparently refreshes it once when the
/// backend says it has expired.
///
/// Port of the Angular `authInterceptor`, including the part that matters most:
/// **only one refresh is ever in flight**. A dashboard fires six requests at
/// once, so six of them can 401 together; without the shared completer below
/// each would start its own refresh, five of those would present a refresh
/// token that the first call had already rotated away, and the user would be
/// signed out in the middle of a working session.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required SecureStore store,
    required Dio Function() dio,
    required Dio refreshDio,
    required Future<void> Function() onSessionExpired,
    this.onTokensRefreshed,
  })  : _store = store,
        _dio = dio,
        _refreshDio = refreshDio,
        _onSessionExpired = onSessionExpired;

  final SecureStore _store;

  /// Late-bound: the interceptor is constructed *by* the client whose Dio it
  /// then needs in order to replay a request.
  final Dio Function() _dio;

  /// A bare Dio with no interceptors. Refreshing through the main client would
  /// recurse: the refresh call itself would 401 and try to refresh.
  final Dio _refreshDio;

  final Future<void> Function() _onSessionExpired;
  final void Function()? onTokensRefreshed;

  /// Non-null exactly while a refresh is in flight. Everyone who 401s during
  /// that window awaits this instead of starting their own.
  Completer<String>? _inFlight;

  static const _retriedKey = 'zuhoo.retried';

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (!_isAuthEndpoint(options.path)) {
      final token = await _store.readAccessToken();
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    final isRetryable = err.response?.statusCode == 401 &&
        !_isAuthEndpoint(options.path) &&
        options.extra[_retriedKey] != true;

    if (!isRetryable) return handler.next(err);

    // Never refresh a borrowed session. An impersonation token has no
    // refresh token of its own, so the only one findable here would be the
    // admin's — and spending it would mint a token for *them*, silently
    // returning the caller to their real identity while every screen keeps
    // saying they are inside the tenant. Storage already drops the refresh
    // token when a session starts; this is the second lock on the same door,
    // at the exact point where a future convenience would reopen it.
    if (await _store.readImpersonation() != null) {
      await _onSessionExpired();
      return handler.next(err);
    }

    final refreshToken = await _store.readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      await _onSessionExpired();
      return handler.next(err);
    }

    final String accessToken;
    try {
      accessToken = await _refresh(refreshToken);
    } catch (_) {
      // _performRefresh has already decided whether this warranted a logout.
      return handler.next(err);
    }

    try {
      options.extra[_retriedKey] = true;
      options.headers['Authorization'] = 'Bearer $accessToken';
      final response = await _dio().fetch<dynamic>(options);
      return handler.resolve(response);
    } on DioException catch (retryError) {
      return handler.next(retryError);
    }
  }

  Future<String> _refresh(String refreshToken) {
    final existing = _inFlight;
    if (existing != null) return existing.future;

    final completer = Completer<String>();
    _inFlight = completer;

    _performRefresh(refreshToken).then(
      (token) {
        _inFlight = null;
        completer.complete(token);
      },
      onError: (Object error, StackTrace stackTrace) {
        _inFlight = null;
        completer.completeError(error, stackTrace);
      },
    );

    return completer.future;
  }

  Future<String> _performRefresh(String refreshToken) async {
    try {
      final res = await _refreshDio.post<dynamic>(
        '/auth/refresh',
        data: {'refreshToken': refreshToken},
      );
      final data = res.data;
      if (data is! Map || data['accessToken'] is! String) {
        throw DioException(
          requestOptions: res.requestOptions,
          response: res,
          message: 'Refresh returned an unexpected body',
        );
      }
      // /auth/refresh returns tokens only — no user info. The cached user must
      // survive it untouched, which is why nothing here writes to the user key.
      await _store.writeTokens(
        data['accessToken'] as String,
        data['refreshToken'] as String?,
      );
      onTokensRefreshed?.call();
      return data['accessToken'] as String;
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      // A failed refresh can mean the token is genuinely dead — or that the
      // backend was restarting. Only a definitive rejection ends the session;
      // anything else leaves the user signed in to retry.
      if (status == 400 || status == 401 || status == 403) {
        await _onSessionExpired();
      }
      rethrow;
    }
  }

  static bool _isAuthEndpoint(String path) =>
      path.contains('/auth/login') ||
      path.contains('/auth/register') ||
      path.contains('/auth/refresh');
}
