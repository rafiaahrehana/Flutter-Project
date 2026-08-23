import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuhoo/core/auth/auth_models.dart';
import 'package:zuhoo/core/storage/secure_store.dart';

/// Impersonation lets platform staff act as one of their customers, which
/// makes storage the security boundary: while a session runs the live keys
/// must hold a tenant token and *only* a tenant token, and the way back to the
/// admin's own identity must be either complete or absent — never half-applied.
void main() {
  late _MemSecureStorage backing;
  late SecureStore store;

  setUp(() async {
    backing = _MemSecureStorage();
    store = SecureStore(backing);
    await store.writeTokens('admin-access', 'admin-refresh');
    await store.writeUser({
      'id': 9,
      'email': 'ops@zuhoo.io',
      'roles': ['SUPER_ADMIN'],
    });
    await store.writePermissions(['COMPANY_MANAGE']);
    await store.writePermissionCatalog(['COMPANY_MANAGE', 'USER_MANAGE']);
  });

  Future<void> begin() => store.beginImpersonation(
        accessToken: 'tenant-access',
        session: const {
          'companyId': 4,
          'companyName': 'Acme Ltd',
          'impersonationSessionId': 'sess-1',
          'adminEmail': 'ops@zuhoo.io',
        },
        impersonatedUser: const {
          'id': 9,
          'roles': ['COMPANY_OWNER'],
        },
      );

  group('SecureStore impersonation', () {
    test('installs the tenant token and drops the refresh token', () async {
      await begin();

      expect(await store.readAccessToken(), 'tenant-access');
      expect(
        await store.readRefreshToken(),
        isNull,
        reason: 'an impersonation token has no refresh of its own, so the only '
            'one findable here would be the admin -- and spending it silently '
            'restores them without ending the session on screen',
      );
      expect(await store.readImpersonation(), isNotNull);
    });

    test('parks the admin session outside the live keys', () async {
      await begin();

      expect(backing.raw['admin_access_token'], 'admin-access');
      expect(backing.raw['admin_refresh_token'], 'admin-refresh');
      expect(
        (await store.readUser())?['roles'],
        ['COMPANY_OWNER'],
        reason: 'the app now acts as the tenant',
      );
    });

    test('clears the cached permissions the admin brought with them', () async {
      await begin();

      expect(
        await store.readPermissions(),
        isEmpty,
        reason: 'the admin permission set must not decide what the tenant UI '
            'offers',
      );
      expect(await store.readPermissionCatalog(), isEmpty);
    });

    test('restoreAdmin puts the original session back intact', () async {
      await begin();
      final admin = await store.restoreAdmin();

      expect(admin?['email'], 'ops@zuhoo.io');
      expect(await store.readAccessToken(), 'admin-access');
      expect(await store.readRefreshToken(), 'admin-refresh');
      expect(await store.readPermissions(), ['COMPANY_MANAGE']);
      expect(await store.readPermissionCatalog(), hasLength(2));
      expect(await store.readImpersonation(), isNull);
    });

    test('restoring twice does not resurrect a stale tenant token', () async {
      await begin();
      await store.restoreAdmin();
      final second = await store.restoreAdmin();

      expect(second, isNull);
      expect(await store.readAccessToken(), isNull);
    });

    test('restoreAdmin signs out when nothing was parked', () async {
      // The corrupt case: an impersonation record with no admin session behind
      // it. There is no identity to return to, so the only safe destination is
      // the login screen -- never "carry on holding the tenant token".
      await backing.write(key: 'impersonation_session', value: '{}');

      expect(await store.restoreAdmin(), isNull);
      expect(await store.readAccessToken(), isNull);
      expect(await store.readImpersonation(), isNull);
    });

    test('a real sign-out leaves no parked session behind', () async {
      await begin();
      await store.clear();

      expect(backing.raw, isEmpty, reason: 'including the admin_* keys');
    });
  });

  group('ImpersonationStart', () {
    test('falls back to the backend default when expiry is missing', () {
      final start = ImpersonationStart.fromJson(const {
        'accessToken': 't',
        'companyId': 4,
        'companyName': 'Acme',
        'impersonationSessionId': 's',
      });

      expect(
        start.expiresInSeconds,
        1800,
        reason: 'zero would read as already-expired and kill the session on '
            'the first tick',
      );
    });
  });

  group('ImpersonationSession', () {
    ImpersonationSession at(Duration left) => ImpersonationSession(
          companyId: 1,
          companyName: 'Acme',
          impersonationSessionId: 's',
          expiresAt: DateTime.now().add(left),
          adminEmail: 'ops@zuhoo.io',
        );

    test('counts down in mm:ss', () {
      expect(at(const Duration(minutes: 4, seconds: 5)).remainingLabel, '04:05');
    });

    test('never reports negative time left', () {
      final past = at(const Duration(minutes: -5));

      expect(past.hasExpired, isTrue);
      expect(past.remainingLabel, '00:00');
    });

    test('rejects a stored record it cannot trust', () {
      expect(ImpersonationSession.tryFromJson(null), isNull);
      expect(ImpersonationSession.tryFromJson(const {}), isNull);
      expect(
        ImpersonationSession.tryFromJson(const {
          'impersonationSessionId': 's',
          'expiresAt': 'not-a-date',
        }),
        isNull,
        reason: 'an unparseable expiry has no safe interpretation',
      );
    });

    test('survives a storage round trip', () {
      final session = at(const Duration(minutes: 30));
      final restored = ImpersonationSession.tryFromJson(
        jsonDecode(jsonEncode(session.toJson())) as Map<String, dynamic>,
      );

      expect(restored!.companyName, 'Acme');
      expect(restored.impersonationSessionId, 's');
      expect(restored.adminEmail, 'ops@zuhoo.io');
    });
  });

  group('JwtPayload', () {
    String token(Map<String, dynamic> claims) {
      String seg(Object value) =>
          base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
      return '${seg({'alg': 'HS256'})}.${seg(claims)}.signature';
    }

    int secondsFromNow(Duration offset) =>
        DateTime.now().add(offset).millisecondsSinceEpoch ~/ 1000;

    test('recognises an impersonation token from its own claims', () {
      final payload = JwtPayload.tryParse(
        token({
          'exp': secondsFromNow(const Duration(minutes: 30)),
          'role': 'COMPANY_OWNER',
          'companyId': 4,
          'impersonatedBy': 9,
          'impersonationSessionId': 'sess-1',
        }),
      );

      expect(payload!.isImpersonation, isTrue);
      expect(payload.impersonatedBy, 9);
      expect(payload.companyId, 4);
      expect(payload.impersonationSessionId, 'sess-1');
    });

    test('an ordinary token is not an impersonation', () {
      final payload = JwtPayload.tryParse(
        token({
          'exp': secondsFromNow(const Duration(hours: 1)),
          'role': 'SUPER_ADMIN',
        }),
      );

      expect(payload!.isImpersonation, isFalse);
    });
  });
}

/// In-memory stand-in for the platform keystore, so these tests exercise the
/// real [SecureStore] logic rather than a reimplementation of it.
class _MemSecureStorage extends FlutterSecureStorage {
  final Map<String, String> raw = {};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      raw[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      raw.remove(key);
    } else {
      raw[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    raw.remove(key);
  }
}
