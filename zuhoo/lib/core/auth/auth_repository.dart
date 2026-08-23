import '../network/api_client.dart';
import '../network/api_exception.dart';
import '../storage/secure_store.dart';
import 'auth_models.dart';

/// Every call the app makes against `/api/auth` and `/api/users`.
///
/// Deliberately dumb: it talks to the backend and to storage, and holds no
/// state. Deciding *when* to call these, and what the app should look like
/// afterwards, is [AuthController]'s job.
class AuthRepository {
  AuthRepository(this._api, this._store);

  final ApiClient _api;
  final SecureStore _store;

  Future<LoginResponse> login(LoginRequest request) async {
    try {
      final json =
          await _api.post<Map<String, dynamic>>('/auth/login', request.toJson());
      final res = LoginResponse.fromJson(json);
      await _store.writeTokens(res.accessToken, res.refreshToken);
      return res;
    } on ApiException catch (e) {
      // A 401 means two different things depending on where it happens, and
      // the generic mapper can only guess one of them. Everywhere else in the
      // app it means an expired session, which is what it says; here it means
      // the credentials were refused — and telling someone their session
      // expired when they have just typed a password is a small lie that sends
      // them looking for a problem that does not exist.
      //
      // Only substituted when the backend sent nothing usable of its own: a
      // real message (a locked or unverified account, say) is always better
      // than anything invented here.
      if (e.isUnauthorized && !e.fromServer) {
        throw ApiException(
          'Invalid email or password.',
          statusCode: e.statusCode,
          cause: e.cause,
        );
      }
      rethrow;
    }
  }

  /// Best-effort server-side revoke. The local session is cleared by the
  /// caller first, so a failure here must not block signing out.
  Future<void> logout(String? refreshToken) async {
    if (refreshToken == null || refreshToken.isEmpty) return;
    try {
      await _api.postText('/auth/logout', {'refreshToken': refreshToken});
    } catch (_) {
      // Already signed out locally; a dead network changes nothing.
    }
  }

  // ── Password recovery ───────────────────────────────────────
  // All four return text/plain, and the first two always return 200 whether
  // or not the account exists — the backend refuses to leak which emails are
  // registered, so the UI must not imply an answer either.

  Future<String> forgotPassword(String email) =>
      _api.postText('/auth/forgot-password', ForgotPasswordRequest(email).toJson());

  Future<String> verifyResetCode(String email, String code) => _api.postText(
        '/auth/verify-reset-code',
        VerifyResetCodeRequest(email: email, code: code).toJson(),
      );

  Future<String> resetPassword(ResetPasswordRequest request) =>
      _api.postText('/auth/reset-password', request.toJson());

  /// Succeeds only against the correct current password, and revokes every
  /// refresh token server-side — so the caller must sign the user out and send
  /// them back to login rather than carrying on with a token that will die.
  Future<String> changePassword(ChangePasswordRequest request) =>
      _api.postText('/auth/change-password', request.toJson());

  // ── Identity ────────────────────────────────────────────────

  // ── Impersonation ───────────────────────────────────────────
  // Session transitions, not console CRUD, which is why they live beside
  // login and logout rather than in the platform feature: what they change is
  // who this app is, and that is this file's subject.

  /// Opens a session inside [companyId]. [reason] is mandatory server-side
  /// (`@NotBlank`) — it is written to the impersonation audit log, which is the
  /// record that makes the whole feature accountable, so a blank one is
  /// rejected here rather than sent to be rejected there.
  Future<ImpersonationStart> impersonate(int companyId, String reason) async {
    final trimmed = reason.trim();
    if (trimmed.isEmpty) {
      throw const ApiException('A reason is required to access a company.');
    }
    final json = await _api.post<Map<String, dynamic>>(
      '/platform-admin/companies/$companyId/impersonate',
      {'reason': trimmed},
    );
    return ImpersonationStart.fromJson(json);
  }

  /// Stamps the audit row closed.
  ///
  /// Worth being clear about what this does not do: it does **not** revoke the
  /// token. `ImpersonationServiceImpl.endImpersonation` only sets `endedAt`,
  /// so the tenant token stays valid until it expires on its own. Ending a
  /// session is therefore something the *client* does — by destroying the
  /// token — and this call is the bookkeeping that accompanies it. That is why
  /// the caller discards the token whether or not this succeeds.
  Future<void> endImpersonation(String impersonationSessionId) =>
      _api.post<dynamic>(
        '/platform-admin/impersonate/end',
        {'impersonationSessionId': impersonationSessionId},
      );

  Future<UserProfile> getProfile() async {
    final json = await _api.get<Map<String, dynamic>>('/users/profile');
    return UserProfile.fromJson(json);
  }

  Future<UserProfile> updateProfile(Map<String, dynamic> patch) async {
    final json = await _api.patch<Map<String, dynamic>>('/users/profile', patch);
    return UserProfile.fromJson(json);
  }

  /// The permission codes this user actually holds.
  Future<List<String>> loadPermissions() async {
    final list = await _api.get<List<dynamic>>('/users/permissions');
    return list.whereType<String>().toList(growable: false);
  }

  /// Every permission code that exists. Only needed to answer "does this user
  /// hold all of them", which is how a custom role with every box ticked gets
  /// treated like an owner in the UI.
  Future<List<String>> loadPermissionCatalog() async {
    final list = await _api.get<List<dynamic>>('/permissions');
    return list
        .whereType<Map<String, dynamic>>()
        .map((p) => p['code'])
        .whereType<String>()
        .toList(growable: false);
  }
}
