import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuhoo/core/auth/auth_controller.dart';
import 'package:zuhoo/core/auth/auth_models.dart';
import 'package:zuhoo/core/auth/auth_repository.dart';
import 'package:zuhoo/core/network/api_client.dart';
import 'package:zuhoo/core/network/api_exception.dart';
import 'package:zuhoo/core/providers.dart';
import 'package:zuhoo/core/storage/secure_store.dart';

/// `authControllerProvider`'s loading state carries a specific meaning that the
/// router acts on: "the stored session is still being read, show the splash".
///
/// Reusing it for an in-flight sign-in attempt looks harmless and is not. Every
/// tap of Sign In threw the user onto the splash screen and back, which rebuilt
/// the login route, which discarded the typed credentials *and* the error
/// message that was meant to explain what went wrong — so a wrong password
/// produced a silently blank form. These tests pin the invariant.
void main() {
  late _MemStore store;

  ProviderContainer containerWith(AuthRepository repo) {
    store = _MemStore();
    final container = ProviderContainer(
      overrides: [
        secureStoreProvider.overrideWithValue(store),
        authRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('AuthController', () {
    test('resolves to signed-out when there is no stored session', () async {
      final container = containerWith(_FakeRepo());

      expect(container.read(authControllerProvider).isLoading, isTrue,
          reason: 'restoring the session is the one legitimate loading state');

      await container.read(authControllerProvider.future);
      expect(container.read(authControllerProvider).value, isNull);
      expect(container.read(authControllerProvider).isLoading, isFalse);
    });

    test('a failed sign-in never re-enters the loading state', () async {
      final container = containerWith(
        _FakeRepo(onLogin: () => throw const ApiException(
              'Invalid email or password.',
              statusCode: 401,
            )),
      );
      await container.read(authControllerProvider.future);

      final seen = <String>[];
      container.listen(authControllerProvider, (_, next) {
        seen.add(next.isLoading ? 'loading' : 'settled');
      });

      await expectLater(
        container.read(authControllerProvider.notifier).login('a@b.c', 'nope'),
        throwsA(isA<ApiException>()),
      );

      expect(seen, isNot(contains('loading')),
          reason: 'a loading blip here sends the router to the splash screen '
              'and wipes the login form mid-attempt');
      expect(container.read(authControllerProvider).value, isNull);
      expect(container.read(authControllerProvider).hasError, isFalse,
          reason: 'the login screen reports the failure; the app is not broken');
    });

    test('a failed sign-in leaves nothing behind in storage', () async {
      final container = containerWith(
        _FakeRepo(onLogin: () => throw const ApiException('nope')),
      );
      await container.read(authControllerProvider.future);

      try {
        await container
            .read(authControllerProvider.notifier)
            .login('a@b.c', 'nope');
      } on ApiException {
        // Expected — this test is about what is left behind afterwards.
      }

      expect(store.accessToken, isNull);
      expect(store.user, isNull);
    });

    test('a successful sign-in lands with permissions already cached',
        () async {
      final container = containerWith(_FakeRepo());
      await container.read(authControllerProvider.future);

      final user = await container
          .read(authControllerProvider.notifier)
          .login('demo@example.com', 'right');

      expect(user.email, 'demo@example.com');
      // The route guard reads permissions synchronously, so they must already
      // be here by the time login() returns — not fetched by the first screen.
      expect(container.read(authControllerProvider).value, isNotNull);
      expect(store.user, isNotNull);
    });

    test('signing out clears the session', () async {
      final container = containerWith(_FakeRepo());
      await container.read(authControllerProvider.future);
      await container
          .read(authControllerProvider.notifier)
          .login('demo@example.com', 'right');

      await container.read(authControllerProvider.notifier).logout();

      expect(container.read(authControllerProvider).value, isNull);
      expect(store.accessToken, isNull);
      expect(store.user, isNull);
    });
  });
}


class _FakeRepo extends AuthRepository {
  _FakeRepo({this.onLogin})
      : super(
          ApiClient(
            store: _MemStore(),
            onSessionExpired: () async {},
          ),
          _MemStore(),
        );

  /// Throws to simulate a rejected sign-in; absent means success.
  final Future<LoginResponse> Function()? onLogin;

  @override
  Future<LoginResponse> login(LoginRequest request) async {
    if (onLogin != null) return onLogin!();
    return LoginResponse(
      userId: 7,
      firstName: 'Demo',
      email: request.email,
      role: 'EMPLOYEE',
      companyId: 11,
      accessToken: 'access',
      refreshToken: 'refresh',
    );
  }

  @override
  Future<void> logout(String? refreshToken) async {}

  @override
  Future<List<String>> loadPermissions() async => const ['LEAVE_VIEW'];

  @override
  Future<List<String>> loadPermissionCatalog() async =>
      const ['LEAVE_VIEW', 'PAYROLL_VIEW'];

  @override
  Future<UserProfile> getProfile() async => const UserProfile(
        id: 7,
        firstName: 'Demo',
        lastName: 'User',
        email: 'demo@example.com',
      );
}

class _MemStore extends SecureStore {
  _MemStore() : super(const FlutterSecureStorage());

  String? accessToken;
  String? refreshToken;
  Map<String, dynamic>? user;
  Map<String, dynamic>? impersonation;
  List<String> permissions = const [];
  List<String> catalog = const [];

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
  Future<List<String>> readPermissions() async => permissions;

  @override
  Future<List<String>> readPermissionCatalog() async => catalog;

  @override
  Future<void> writePermissions(List<String> codes) async => permissions = codes;

  @override
  Future<void> writePermissionCatalog(List<String> codes) async =>
      catalog = codes;

  @override
  Future<void> clear() async {
    accessToken = null;
    refreshToken = null;
    user = null;
    permissions = const [];
    catalog = const [];
  }
}
