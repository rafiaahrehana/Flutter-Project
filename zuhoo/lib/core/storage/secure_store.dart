import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Session storage. Mirrors the keys AuthService/PermissionService keep in
/// `localStorage` on the web, except these live in the platform keystore —
/// a JWT on a phone is worth more than one in a browser tab, because the
/// device is shared far less often and lost far more often.
class SecureStore {
  SecureStore(this._storage);

  final FlutterSecureStorage _storage;

  static const _accessToken = 'access_token';
  static const _refreshToken = 'refresh_token';
  static const _user = 'user';
  static const _permissions = 'permissions';
  static const _permissionCatalog = 'permission_catalog';

  // ── Tokens ──────────────────────────────────────────────────
  Future<String?> readAccessToken() => _storage.read(key: _accessToken);
  Future<String?> readRefreshToken() => _storage.read(key: _refreshToken);

  Future<void> writeTokens(String accessToken, String? refreshToken) async {
    await _storage.write(key: _accessToken, value: accessToken);
    // /auth/refresh always returns both, but the demo session deliberately
    // issues no refresh token — when the access token dies, the demo is over.
    if (refreshToken != null) {
      await _storage.write(key: _refreshToken, value: refreshToken);
    }
  }

  // ── User ────────────────────────────────────────────────────
  Future<Map<String, dynamic>?> readUser() => _readJson(_user);

  Future<void> writeUser(Map<String, dynamic> user) =>
      _storage.write(key: _user, value: jsonEncode(user));

  // ── Permissions ─────────────────────────────────────────────
  Future<List<String>> readPermissions() => _readStringList(_permissions);
  Future<List<String>> readPermissionCatalog() => _readStringList(_permissionCatalog);

  Future<void> writePermissions(List<String> codes) =>
      _storage.write(key: _permissions, value: jsonEncode(codes));

  Future<void> writePermissionCatalog(List<String> codes) =>
      _storage.write(key: _permissionCatalog, value: jsonEncode(codes));

  // ── Impersonation ───────────────────────────────────────────
  // While a platform admin is inside a tenant, their own session is parked
  // under the `admin_*` keys and the live keys hold the impersonation token.
  // Two separate namespaces rather than one mutable session, because the
  // failure that matters is ending up *half* switched — a tenant token paired
  // with the admin's own refresh token, which is a way back into their real
  // identity that nothing in the UI would show.

  static const _adminAccessToken = 'admin_access_token';
  static const _adminRefreshToken = 'admin_refresh_token';
  static const _adminUser = 'admin_user';
  static const _adminPermissions = 'admin_permissions';
  static const _adminPermissionCatalog = 'admin_permission_catalog';
  static const _impersonation = 'impersonation_session';

  Future<Map<String, dynamic>?> readImpersonation() => _readJson(_impersonation);

  /// Parks the admin's session and installs the impersonated one.
  ///
  /// The refresh token is **deleted**, not carried across: impersonation
  /// returns an access token and nothing else, so there is no such thing as
  /// refreshing one. Leaving the admin's refresh token in place would let the
  /// interceptor answer a mid-session 401 by quietly minting a fresh *admin*
  /// token and carrying on — the caller would stop being the tenant without
  /// anything on screen changing. Deleting it makes that impossible instead of
  /// merely discouraged.
  Future<void> beginImpersonation({
    required String accessToken,
    required Map<String, dynamic> session,
    required Map<String, dynamic> impersonatedUser,
  }) async {
    final adminAccess = await readAccessToken();
    final adminRefresh = await readRefreshToken();
    final adminUser = await _storage.read(key: _user);
    final adminPermissions = await _storage.read(key: _permissions);
    final adminCatalog = await _storage.read(key: _permissionCatalog);

    await Future.wait([
      if (adminAccess != null)
        _storage.write(key: _adminAccessToken, value: adminAccess),
      if (adminRefresh != null)
        _storage.write(key: _adminRefreshToken, value: adminRefresh),
      if (adminUser != null) _storage.write(key: _adminUser, value: adminUser),
      if (adminPermissions != null)
        _storage.write(key: _adminPermissions, value: adminPermissions),
      if (adminCatalog != null)
        _storage.write(key: _adminPermissionCatalog, value: adminCatalog),
    ]);

    await Future.wait([
      _storage.write(key: _accessToken, value: accessToken),
      _storage.delete(key: _refreshToken),
      _storage.write(key: _user, value: jsonEncode(impersonatedUser)),
      _storage.write(key: _impersonation, value: jsonEncode(session)),
      // The tenant grants a different permission set; the admin's cached one
      // would otherwise decide what the tenant's UI shows.
      _storage.delete(key: _permissions),
      _storage.delete(key: _permissionCatalog),
    ]);
  }

  /// Puts the admin's own session back and returns their cached user record.
  ///
  /// Returns null when there is nothing parked — which means the app cannot
  /// get back to a real identity and the only safe destination is the login
  /// screen. The impersonation keys are cleared either way, so a failure here
  /// can never leave a tenant token installed.
  Future<Map<String, dynamic>?> restoreAdmin() async {
    final adminAccess = await _storage.read(key: _adminAccessToken);
    final adminRefresh = await _storage.read(key: _adminRefreshToken);
    final adminUserRaw = await _readJson(_adminUser);
    final adminPermissions = await _storage.read(key: _adminPermissions);
    final adminCatalog = await _storage.read(key: _adminPermissionCatalog);

    await clearImpersonation();

    if (adminAccess == null || adminUserRaw == null) {
      await clear();
      return null;
    }

    await Future.wait([
      _storage.write(key: _accessToken, value: adminAccess),
      if (adminRefresh != null)
        _storage.write(key: _refreshToken, value: adminRefresh)
      else
        _storage.delete(key: _refreshToken),
      _storage.write(key: _user, value: jsonEncode(adminUserRaw)),
      if (adminPermissions != null)
        _storage.write(key: _permissions, value: adminPermissions)
      else
        _storage.delete(key: _permissions),
      if (adminCatalog != null)
        _storage.write(key: _permissionCatalog, value: adminCatalog)
      else
        _storage.delete(key: _permissionCatalog),
    ]);

    return adminUserRaw;
  }

  Future<void> clearImpersonation() => Future.wait([
        _storage.delete(key: _impersonation),
        _storage.delete(key: _adminAccessToken),
        _storage.delete(key: _adminRefreshToken),
        _storage.delete(key: _adminUser),
        _storage.delete(key: _adminPermissions),
        _storage.delete(key: _adminPermissionCatalog),
      ]);

  // ── Teardown ────────────────────────────────────────────────
  Future<void> clear() async {
    await Future.wait([
      _storage.delete(key: _accessToken),
      _storage.delete(key: _refreshToken),
      _storage.delete(key: _user),
      _storage.delete(key: _permissions),
      _storage.delete(key: _permissionCatalog),
      // The parked admin session goes too. A real sign-out has to
      // leave nothing behind that could resume as somebody else.
      _storage.delete(key: _adminAccessToken),
      _storage.delete(key: _adminRefreshToken),
      _storage.delete(key: _adminUser),
      _storage.delete(key: _adminPermissions),
      _storage.delete(key: _adminPermissionCatalog),
      _storage.delete(key: _impersonation),
    ]);
  }

  // ── Helpers ─────────────────────────────────────────────────
  Future<Map<String, dynamic>?> _readJson(String key) async {
    final raw = await _storage.read(key: key);
    if (raw == null || raw.isEmpty || raw == 'undefined') return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      // A value written by an older build of the app that no longer parses is
      // not worth crashing over; treat it as absent and let it be rewritten.
      return null;
    }
  }

  Future<List<String>> _readStringList(String key) async {
    final raw = await _storage.read(key: key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded.whereType<String>().toList() : const [];
    } catch (_) {
      return const [];
    }
  }
}
