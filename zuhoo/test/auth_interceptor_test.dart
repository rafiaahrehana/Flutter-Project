import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuhoo/core/network/auth_interceptor.dart';
import 'package:zuhoo/core/storage/secure_store.dart';

/// The refresh queue is the one piece of this app where a bug is both silent
/// and destructive.
///
/// A dashboard fires several requests at once. When the access token has
/// expired they all 401 together, and if each starts its own refresh, only the
/// first one's rotated token survives — the rest present a refresh token the
/// server has already invalidated, the server rejects them, and the user is
/// signed out mid-session. It looks like a flaky backend, and it reproduces
/// only under concurrency.
void main() {
  group('AuthInterceptor', () {
    late _FakeStore store;
    late _ScriptedAdapter adapter;
    late Dio dio;
    late int sessionExpiredCalls;

    /// Wires a client with the interceptor under test. [refreshStatus] is what
    /// POST /auth/refresh answers with.
    Dio build({int refreshStatus = 200}) {
      store = _FakeStore(accessToken: 'expired', refreshToken: 'r1');
      adapter = _ScriptedAdapter(store: store, refreshStatus: refreshStatus);
      sessionExpiredCalls = 0;

      final client = Dio(BaseOptions(baseUrl: 'http://test.local/api'))
        ..httpClientAdapter = adapter;
      final refreshDio = Dio(BaseOptions(baseUrl: 'http://test.local/api'))
        ..httpClientAdapter = adapter;

      client.interceptors.add(
        AuthInterceptor(
          store: store,
          dio: () => client,
          refreshDio: refreshDio,
          onSessionExpired: () async => sessionExpiredCalls++,
        ),
      );
      return client;
    }

    // The failure this prevents is the nastiest one in the feature: the admin
    // stops being the tenant, but nothing on screen says so, and whatever they
    // do next lands in their own account under their own name.
    test(
      'never spends the admin refresh token while impersonating a tenant',
      () async {
        dio = build();
        store.accessToken = 'expired';
        store.refreshToken = 'admin-refresh';
        store.impersonation = {
          'impersonationSessionId': 'sess-1',
          'companyId': 7,
        };

        await expectLater(
          dio.get<dynamic>('/employees/me'),
          throwsA(isA<DioException>()),
        );

        expect(
          adapter.refreshCount,
          0,
          reason: 'refreshing here would mint a token for the admin, silently '
              'ending the impersonation without ending it on screen',
        );
        expect(
          store.accessToken,
          'expired',
          reason: 'the dead tenant token must not be replaced with an admin one',
        );
        expect(
          sessionExpiredCalls,
          1,
          reason: 'the session is over and the app has to be told',
        );
      },
    );

    test('attaches the bearer token to ordinary requests', () async {
      dio = build();
      store.accessToken = 'good';

      await dio.get<dynamic>('/employees/me');

      expect(adapter.lastAuthHeaderFor('/employees/me'), 'Bearer good');
    });

    test('never attaches a token to the auth endpoints', () async {
      dio = build();
      store.accessToken = 'good';

      await dio.post<dynamic>('/auth/login', data: {});

      // Sending a stale bearer to /auth/login would make the login attempt
      // itself 401 and kick off a pointless refresh.
      expect(adapter.lastAuthHeaderFor('/auth/login'), isNull);
    });

    test('refreshes once and retries when a request 401s', () async {
      dio = build();

      final response = await dio.get<dynamic>('/employees/me');

      expect(response.statusCode, 200);
      expect(adapter.refreshCount, 1);
      expect(store.accessToken, 'fresh-1');
      expect(sessionExpiredCalls, 0);
    });

    test('six concurrent 401s trigger exactly one refresh', () async {
      dio = build();

      final responses = await Future.wait([
        for (var i = 0; i < 6; i++) dio.get<dynamic>('/employees/me'),
      ]);

      expect(responses.every((r) => r.statusCode == 200), isTrue);
      expect(
        adapter.refreshCount,
        1,
        reason: 'the five that lost the race must await the first refresh, '
            'not start their own with a token it already rotated away',
      );
      expect(sessionExpiredCalls, 0);
    });

    test('a rejected refresh ends the session and does not loop', () async {
      dio = build(refreshStatus: 401);

      await expectLater(
        dio.get<dynamic>('/employees/me'),
        throwsA(isA<DioException>()),
      );

      expect(sessionExpiredCalls, 1);
      expect(
        adapter.refreshCount,
        1,
        reason: 'the retried request must not itself trigger another refresh',
      );
    });

    test('a server-side refresh failure does NOT sign the user out', () async {
      // A 500 means the backend is unwell — very often a dev restart. Treating
      // that as a dead session would sign someone out every time the server
      // bounced, losing whatever they were in the middle of.
      dio = build(refreshStatus: 503);

      await expectLater(
        dio.get<dynamic>('/employees/me'),
        throwsA(isA<DioException>()),
      );

      expect(sessionExpiredCalls, 0);
      expect(store.refreshToken, 'r1', reason: 'the token is still worth a retry');
    });
  });
}

/// In-memory [SecureStore]. Every method that touches the platform keystore is
/// overridden, so the real one is constructed but never called.
class _FakeStore extends SecureStore {
  _FakeStore({required this.accessToken, required this.refreshToken})
      : super(const FlutterSecureStorage());

  String? accessToken;
  String? refreshToken;
  Map<String, dynamic>? user;
  Map<String, dynamic>? impersonation;

  @override
  Future<String?> readAccessToken() async => accessToken;

  @override
  Future<String?> readRefreshToken() async => refreshToken;

  @override
  Future<void> writeTokens(String access, String? refresh) async {
    accessToken = access;
    if (refresh != null) refreshToken = refresh;
  }

  @override
  Future<Map<String, dynamic>?> readUser() async => user;

  @override
  Future<Map<String, dynamic>?> readImpersonation() async => impersonation;

  @override
  Future<void> writeUser(Map<String, dynamic> value) async => user = value;

  @override
  Future<void> clear() async {
    accessToken = null;
    refreshToken = null;
    user = null;
  }
}

/// A transport that 401s any protected request carrying a stale token, and
/// hands out a fresh one from /auth/refresh.
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter({required this.store, required this.refreshStatus});

  final _FakeStore store;
  final int refreshStatus;

  int refreshCount = 0;
  final Map<String, String?> _authHeaders = {};

  String? lastAuthHeaderFor(String path) => _authHeaders[path];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    _authHeaders[options.path] = options.headers['Authorization'] as String?;

    if (options.path.contains('/auth/refresh')) {
      refreshCount++;
      if (refreshStatus != 200) {
        return _json({'message': 'refresh rejected'}, refreshStatus);
      }
      // A real rotation: the old refresh token stops working, which is exactly
      // what punishes a second concurrent refresh.
      return _json(
        {'accessToken': 'fresh-$refreshCount', 'refreshToken': 'r-$refreshCount'},
        200,
      );
    }

    if (options.path.contains('/auth/')) return _json({'ok': true}, 200);

    // Exactly one token value is rejected, so a test that wants a working
    // request can simply hand over any other one.
    final token = options.headers['Authorization'] as String?;
    if (token == null || token == 'Bearer expired') {
      return _json({'message': 'expired'}, 401);
    }
    return _json({'id': 1}, 200);
  }

  static ResponseBody _json(Map<String, dynamic> body, int status) =>
      ResponseBody.fromString(
        jsonEncode(body),
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  @override
  void close({bool force = false}) {}
}
