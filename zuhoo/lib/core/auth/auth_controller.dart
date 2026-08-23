import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/env.dart';
import '../network/api_exception.dart';
import '../providers.dart';
import 'auth_models.dart';
import 'impersonation_controller.dart';
import 'permission_controller.dart';

/// Who is signed in, if anyone.
///
/// `AsyncValue` carries the three states the UI actually has to draw: still
/// restoring a session from storage (loading), signed in (data with a user),
/// and signed out (data with null). Sign-in failures are surfaced by the login
/// screen from the thrown exception rather than parked in this state, so a
/// failed attempt never leaves the whole app in an error state.
class AuthController extends AsyncNotifier<AppUser?> {
  @override
  Future<AppUser?> build() => _restoreSession();

  /// Reads back a previous session on cold start.
  ///
  /// An expired access token is not on its own a reason to sign out: the
  /// interceptor will refresh it on the first real request. Only an expired
  /// token with no refresh token left is terminal.
  Future<AppUser?> _restoreSession() async {
    final store = ref.read(secureStoreProvider);

    final userJson = await store.readUser();
    if (userJson == null) return null;

    final accessToken = await store.readAccessToken();
    final refreshToken = await store.readRefreshToken();
    final payload = JwtPayload.tryParse(accessToken);

    // An impersonation session that survived a restart is handled before
    // anything else, because the checks below assume the tokens in storage
    // belong to the person who signed in — and during a session they do not.
    final impersonation =
        ImpersonationSession.tryFromJson(await store.readImpersonation());
    if (impersonation != null) {
      // A borrowed token cannot be refreshed, so a dead one ends the session
      // rather than starting a restore. Reopening the app an hour later must
      // land the admin back in their own account, not inside a tenant the app
      // can no longer talk to.
      if (payload == null || payload.isExpired || impersonation.hasExpired) {
        // No state assignment: this path runs inside build(), where the
        // returned value *is* the state and Riverpod forbids setting it.
        return _restoreAdminSession(assignState: false);
      }
      ref.read(impersonationControllerProvider.notifier).set(impersonation);
      await ref.read(permissionControllerProvider.notifier).hydrateFromCache();
      unawaited(
        ref.read(permissionControllerProvider.notifier).refreshQuietly(),
      );
      return AppUser.fromJson(userJson);
    }

    final unusable = payload == null ||
        (payload.isExpired && (refreshToken == null || refreshToken.isEmpty));
    if (unusable) {
      await store.clear();
      return null;
    }

    // Render immediately from the cached permission set, then let the network
    // correct it. Blocking the splash on a round trip would mean a slow
    // connection shows nothing at all.
    await ref.read(permissionControllerProvider.notifier).hydrateFromCache();
    unawaited(_warmSession());

    return AppUser.fromJson(userJson);
  }

  /// Background revalidation after a restored session: confirm permissions and
  /// pick up a profile picture that may have changed on another device.
  Future<void> _warmSession() async {
    await ref.read(permissionControllerProvider.notifier).refreshQuietly();
    try {
      await _applyProfile();
    } catch (_) {
      // The cached user is still perfectly usable.
    }
  }

  /// Signs in, then loads everything the first screen needs before returning.
  ///
  /// The ordering is deliberate and matches the web app: permissions must be
  /// cached before the caller navigates, because the route guard reads them
  /// synchronously and would otherwise bounce the user off a screen they are
  /// entitled to. The profile call follows so the avatar is present on the
  /// first frame instead of popping in a moment later.
  Future<AppUser> login(String email, String password) async {
    // Deliberately does **not** set `AsyncValue.loading()`.
    //
    // This provider's loading state means one specific thing to the router:
    // "the stored session is still being read, do not route yet" — and the
    // router answers it by showing the splash. Reusing it for an in-flight
    // sign-in attempt made every tap of Sign In throw the user onto the splash
    // screen and back, rebuilding the login route, which wiped both the typed
    // credentials and the error message that was supposed to explain the
    // failure. The login screen tracks its own progress locally instead.
    try {
      final repo = ref.read(authRepositoryProvider);
      final res = await repo.login(
        LoginRequest(email: email.trim(), password: password),
      );

      var user = AppUser.fromLogin(res);
      await ref.read(secureStoreProvider).writeUser(user.toJson());

      await ref.read(permissionControllerProvider.notifier).load();

      try {
        final profile = await repo.getProfile();
        user = user.copyWith(
          fullName: profile.fullName,
          profileImageUrl: profile.imageUrl,
        );
        await ref.read(secureStoreProvider).writeUser(user.toJson());
      } catch (_) {
        // Cosmetic only — the session is valid without it.
      }

      state = AsyncValue.data(user);
      return user;
    } catch (error, stackTrace) {
      // Stays signed-out rather than becoming an error state: the login screen
      // shows the message itself, and leaving the app "errored" would make
      // every consumer of this provider render a failure. The partial tokens a
      // half-finished attempt may have written are cleared so nothing is left
      // holding a credential that was never completed.
      await ref.read(secureStoreProvider).clear();
      ref.read(permissionControllerProvider.notifier).clear();
      if (state.value != null) state = const AsyncValue.data(null);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> logout() async {
    // Signing out from inside a company closes that session first, so the
    // audit row is stamped rather than left hanging — and so the refresh
    // token read below is the admin's own, which is the one worth revoking.
    if (ref.read(impersonationControllerProvider) != null) {
      await endImpersonation();
    }

    final store = ref.read(secureStoreProvider);
    final refreshToken = await store.readRefreshToken();

    // Local first: signing out must feel instant and must succeed even with
    // no connection. The server-side revoke is best-effort behind it.
    await clearSession();
    await ref.read(authRepositoryProvider).logout(refreshToken);
  }

  // ── Impersonation ───────────────────────────────────────────

  /// Opens a session inside a tenant and becomes it.
  ///
  /// The admin's own session is parked in storage first, so that from the
  /// moment the tenant token is installed there is exactly one live identity
  /// and one way back to the other.
  Future<ImpersonationSession> startImpersonation({
    required int companyId,
    required String reason,
  }) async {
    final admin = state.value;
    if (admin == null) {
      throw const ApiException('Sign in before accessing a company.');
    }
    if (ref.read(impersonationControllerProvider) != null) {
      throw const ApiException(
        'You are already inside a company. End that session first.',
      );
    }

    final start =
        await ref.read(authRepositoryProvider).impersonate(companyId, reason);
    if (start.accessToken.isEmpty || start.impersonationSessionId.isEmpty) {
      // Nothing has been swapped yet, so failing here leaves the admin exactly
      // where they were.
      throw const ApiException(
        'The server did not return a usable session for that company.',
      );
    }

    final session = ImpersonationSession.fromStart(
      start,
      adminEmail: admin.email,
      reason: reason.trim(),
    );

    // The identity the app now acts as. The backend mints the token with
    // COMPANY_OWNER, so this mirrors what the token actually grants rather
    // than what the admin's own account says — anything else and the UI would
    // hide screens the session can reach, or offer ones it cannot.
    final tenantUser = AppUser(
      id: admin.id,
      email: admin.email,
      fullName: admin.fullName,
      roles: const ['COMPANY_OWNER'],
      companyId: start.companyId,
    );

    await ref.read(secureStoreProvider).beginImpersonation(
          accessToken: start.accessToken,
          session: session.toJson(),
          impersonatedUser: tenantUser.toJson(),
        );

    ref.read(permissionControllerProvider.notifier).clear();
    ref.read(impersonationControllerProvider.notifier).set(session);
    state = AsyncValue.data(tenantUser);

    try {
      // The tenant's permission set, fetched under the new token. A failure
      // here is not worth unwinding the session for: permissions reload on the
      // next screen, and the admin can see the company either way.
      await ref.read(permissionControllerProvider.notifier).load();
    } catch (_) {}

    return session;
  }

  /// Ends the session and gives the admin their own identity back.
  ///
  /// Order is load-bearing. The local restore happens **first**, for two
  /// reasons: ending must work with no connection, and the end-session
  /// endpoint sits behind the platform-admin role check while the token being
  /// held is COMPANY_OWNER — called before the swap it would 403 and the audit
  /// row would never be stamped closed.
  Future<void> endImpersonation({bool expired = false}) async {
    final session = ref.read(impersonationControllerProvider);
    if (session == null) return;

    ref.read(impersonationControllerProvider.notifier).set(null);
    final admin = await _restoreAdminSession();

    // Best-effort bookkeeping. The token is already gone from this device
    // whatever happens next — the server does not revoke it, so discarding it
    // locally *is* the end of the session, and this call only closes the
    // audit record that says when.
    if (admin != null) {
      try {
        await ref
            .read(authRepositoryProvider)
            .endImpersonation(session.impersonationSessionId);
      } catch (_) {}
    }
  }

  /// Reinstalls the parked admin session. Null when there was nothing to go
  /// back to, in which case the app is signed out — the safe direction.
  Future<AppUser?> _restoreAdminSession({bool assignState = true}) async {
    final adminJson = await ref.read(secureStoreProvider).restoreAdmin();
    ref.read(impersonationControllerProvider.notifier).set(null);
    ref.read(permissionControllerProvider.notifier).clear();

    if (adminJson == null) {
      if (assignState) state = const AsyncValue.data(null);
      return null;
    }

    final admin = AppUser.fromJson(adminJson);
    if (assignState) state = AsyncValue.data(admin);
    await ref.read(permissionControllerProvider.notifier).hydrateFromCache();
    unawaited(ref.read(permissionControllerProvider.notifier).refreshQuietly());
    return admin;
  }

  /// What the HTTP layer calls when a token is definitively dead.
  ///
  /// Falling out of a borrowed session should return the admin to their own,
  /// not to the login screen: their session is still perfectly valid and is
  /// sitting right there in storage.
  Future<void> handleSessionExpired() async {
    if (ref.read(impersonationControllerProvider) != null) {
      await endImpersonation(expired: true);
      return;
    }
    await clearSession();
  }

  /// Wipes the session without navigating or calling the backend. Also invoked
  /// by the HTTP layer when a refresh is definitively rejected.
  Future<void> clearSession() async {
    ref.read(impersonationControllerProvider.notifier).set(null);
    await ref.read(secureStoreProvider).clear();
    ref.read(permissionControllerProvider.notifier).clear();
    state = const AsyncValue.data(null);
  }

  /// Re-reads /users/profile and updates the cached name and avatar.
  Future<void> refreshProfile() async {
    if (state.value == null) return;
    await _applyProfile();
  }

  /// Updates the cached avatar after it changed somewhere other than
  /// /users/profile — PATCH /employees/me also syncs the user's image
  /// server-side, but that response never passes through here, so without this
  /// the profile picture would keep showing the old one until the next sign-in.
  Future<void> setAvatar(String? imagePath) async {
    final current = state.value;
    if (current == null) return;
    final resolved = Env.resolveImageUrl(imagePath);
    final updated = current.copyWith(
      profileImageUrl: resolved,
      clearImage: resolved == null,
    );
    await ref.read(secureStoreProvider).writeUser(updated.toJson());
    state = AsyncValue.data(updated);
  }

  Future<void> _applyProfile() async {
    // /users/profile resolves the token's subject, and an impersonation
    // token is still subject-ed to the admin — so calling this during a
    // session would quietly stamp the admin's name and avatar onto the
    // tenant identity the whole app is currently drawing.
    if (ref.read(impersonationControllerProvider) != null) return;
    final current = state.value;
    if (current == null) return;

    final profile = await ref.read(authRepositoryProvider).getProfile();
    final updated = current.copyWith(
      fullName: profile.fullName,
      profileImageUrl: profile.imageUrl,
      clearImage: profile.imageUrl == null,
    );
    await ref.read(secureStoreProvider).writeUser(updated.toJson());
    state = AsyncValue.data(updated);
  }
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AppUser?>(AuthController.new);

/// The signed-in user, or null while loading or signed out. Screens behind the
/// auth redirect can rely on this being non-null.
final currentUserProvider = Provider<AppUser?>(
  (ref) => ref.watch(authControllerProvider).value,
);
