import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';

/// The user's resolved permission set, cached so a check can be answered
/// synchronously.
///
/// This matters for routing: the redirect that decides whether a screen may be
/// shown runs synchronously, so the set has to already be here by the time the
/// user lands anywhere. That is why sign-in loads permissions *before* it
/// navigates rather than letting each screen fetch them lazily.
class PermissionState {
  const PermissionState({
    this.codes = const {},
    this.catalog = const {},
    this.loaded = false,
  });

  /// What this user holds.
  final Set<String> codes;

  /// Every code that exists, from GET /permissions.
  final Set<String> catalog;

  /// True once a real fetch has completed *this app session*.
  ///
  /// The set restored from storage on launch can be stale — a different
  /// account, or permissions an owner has since revoked — so a gate must not
  /// trust it as proof of entitlement until the server has confirmed it.
  final bool loaded;

  /// A null or empty requirement means "no permission needed", matching
  /// `hasPermission(null) === true` in the Angular service.
  bool has(String? permission) =>
      permission == null || permission.isEmpty || codes.contains(permission);

  bool hasAny(Iterable<String>? permissions) {
    if (permissions == null || permissions.isEmpty) return true;
    return permissions.any(codes.contains);
  }

  /// True only once the catalog has loaded and this user covers all of it.
  bool get hasAll =>
      catalog.isNotEmpty && catalog.every(codes.contains);

  PermissionState copyWith({
    Set<String>? codes,
    Set<String>? catalog,
    bool? loaded,
  }) =>
      PermissionState(
        codes: codes ?? this.codes,
        catalog: catalog ?? this.catalog,
        loaded: loaded ?? this.loaded,
      );
}

class PermissionController extends Notifier<PermissionState> {
  @override
  PermissionState build() => const PermissionState();

  /// Fills the set from storage so the first frame after a cold start can
  /// render gated UI without waiting on the network. Does **not** set
  /// [PermissionState.loaded] — this is a guess until the server agrees.
  Future<void> hydrateFromCache() async {
    final store = ref.read(secureStoreProvider);
    final codes = await store.readPermissions();
    final catalog = await store.readPermissionCatalog();
    state = state.copyWith(codes: codes.toSet(), catalog: catalog.toSet());
  }

  /// Fetches both sets and caches them. Errors propagate: sign-in awaits this,
  /// and a sign-in that silently produced an empty permission set would drop
  /// the user into an app where nothing is visible and nothing explains why.
  Future<void> load() async {
    final repo = ref.read(authRepositoryProvider);
    final store = ref.read(secureStoreProvider);

    final results = await Future.wait([
      repo.loadPermissions(),
      repo.loadPermissionCatalog(),
    ]);

    final codes = results[0];
    final catalog = results[1];

    await store.writePermissions(codes);
    await store.writePermissionCatalog(catalog);

    state = PermissionState(
      codes: codes.toSet(),
      catalog: catalog.toSet(),
      loaded: true,
    );
  }

  /// Same as [load] but swallows failures. Used on the background warm-up
  /// after a restored session, where the cached set is already good enough to
  /// render with and a transient failure should not sign anyone out.
  Future<void> refreshQuietly() async {
    try {
      await load();
    } catch (_) {
      // Keep whatever the cache gave us.
    }
  }

  void clear() => state = const PermissionState();
}

final permissionControllerProvider =
    NotifierProvider<PermissionController, PermissionState>(
  PermissionController.new,
);

/// Convenience for widgets: `ref.watch(hasPermissionProvider('LEAVE_VIEW'))`.
final hasPermissionProvider = Provider.family<bool, String>(
  (ref, code) => ref.watch(permissionControllerProvider).has(code),
);
