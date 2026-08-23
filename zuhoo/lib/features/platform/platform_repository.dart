import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/auth_models.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/paged_response.dart';
import '../../core/providers.dart';
import '../../shared/paged_controller.dart';
import 'platform_models.dart';

/// The SaaS operator's own console.
///
/// Everything here crosses tenant boundaries, so it is guarded by role rather
/// than by permission: only platform staff reach it at all, and the backend
/// checks the same thing again on every call.
///
/// Deliberately absent: **impersonation**. `POST /platform-admin/companies/{id}/
/// impersonate` swaps the caller's session for one inside a tenant, and getting
/// the restore path wrong would either strand an admin in someone else's
/// account or leave a live cross-tenant token in storage. That is not something
/// to ship untested, and it is a support tool that belongs on a desk anyway.
/// Also absent: custom roles (a hundred-checkbox permission matrix), locations,
/// and plan definitions — all configuration work that a phone cannot lay out.
class PlatformRepository {
  PlatformRepository(this._api);

  final ApiClient _api;

  static const _companies = '/companies';
  static const _flags = '/feature-flags';
  static const _users = '/platform/users';

  Future<PagedResponse<Company>> companies({
    String? status,
    String? plan,
    String? keyword,
    int page = 0,
    int size = 20,
  }) =>
      _api.getPaged(
        _companies,
        Company.fromJson,
        page: page,
        size: size,
        query: {'status': status, 'plan': plan, 'keyword': keyword},
      );

  Future<Company> company(int id) async {
    final json = await _api.get<Map<String, dynamic>>('$_companies/$id');
    return Company.fromJson(json);
  }

  /// Suspends, reactivates, or otherwise moves a tenant.
  ///
  /// The status is a query parameter, not a body — the controller declares
  /// `@RequestParam`, so a JSON body would be accepted and ignored, which
  /// looks exactly like a no-op that succeeded.
  Future<Company> changeStatus(int id, String status) async {
    final json = await _api.patch<Map<String, dynamic>>(
      '$_companies/$id/status?status=${Uri.encodeQueryComponent(status)}',
    );
    return Company.fromJson(json);
  }

  /// Moves a tenant onto another plan.
  ///
  /// `amountPaid` and `transactionRef` are optional and get recorded into the
  /// subscription history that the platform revenue figures are built from —
  /// so a plan change made without them is invisible to those numbers.
  Future<Company> changePlan(
    int id,
    String plan, {
    double? amountPaid,
    String? transactionRef,
  }) async {
    final query = <String>[
      'plan=${Uri.encodeQueryComponent(plan)}',
      if (amountPaid != null) 'amountPaid=$amountPaid',
      if (transactionRef != null && transactionRef.trim().isNotEmpty)
        'transactionRef=${Uri.encodeQueryComponent(transactionRef.trim())}',
    ].join('&');

    final json =
        await _api.patch<Map<String, dynamic>>('$_companies/$id/plan?$query');
    return Company.fromJson(json);
  }

  /// The plans a company can be moved onto. Optional: without them the plan
  /// action simply is not offered, which beats offering a blank picker.
  Future<List<SubscriptionPlanOption>> plans() async {
    try {
      final list = await _api.get<List<dynamic>>('/subscription-plans');
      return list
          .whereType<Map<String, dynamic>>()
          .map(SubscriptionPlanOption.fromJson)
          .where((plan) => plan.key.isNotEmpty)
          .toList(growable: false);
    } on ApiException {
      return const [];
    }
  }

  /// Who has been inside which tenant, and why.
  ///
  /// Read access is narrower than the rest of this controller — a support
  /// agent can open a session but not review everyone else's.
  Future<PagedResponse<ImpersonationAuditEntry>> impersonationHistory({
    int? companyId,
    int page = 0,
    int size = 20,
  }) =>
      _api.getPaged(
        '/platform-admin/impersonate/history',
        ImpersonationAuditEntry.fromJson,
        page: page,
        size: size,
        query: {'companyId': companyId},
      );

  Future<List<FeatureFlag>> flags() async {
    final list = await _api.get<List<dynamic>>(_flags);
    final flags = list
        .whereType<Map<String, dynamic>>()
        .map(FeatureFlag.fromJson)
        .toList()
      ..sort((a, b) => a.flagKey.compareTo(b.flagKey));
    return flags;
  }

  /// Toggling is keyed by the flag's string key, not its id.
  Future<FeatureFlag> toggleFlag(String key) async {
    final json = await _api.patch<Map<String, dynamic>>('$_flags/$key/toggle');
    return FeatureFlag.fromJson(json);
  }

  Future<PagedResponse<PlatformUser>> users({int page = 0, int size = 20}) =>
      _api.getPaged(_users, PlatformUser.fromJson, page: page, size: size);
}

final platformRepositoryProvider = Provider<PlatformRepository>(
  (ref) => PlatformRepository(ref.watch(apiClientProvider)),
);

/// Which company status the list is filtered to. Null means every one.
class CompanyFilterController extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? status) {
    if (state == status) return;
    state = status;
  }
}

final companyFilterProvider =
    NotifierProvider<CompanyFilterController, String?>(
  CompanyFilterController.new,
);

/// Free-text search across the tenant list.
class CompanySearchController extends Notifier<String> {
  @override
  String build() => '';

  void set(String keyword) {
    final trimmed = keyword.trim();
    if (state == trimmed) return;
    state = trimmed;
  }
}

final companySearchProvider =
    NotifierProvider<CompanySearchController, String>(
  CompanySearchController.new,
);

class CompaniesController extends AsyncNotifier<PagedState<Company>>
    with PagedLoader<Company> {
  @override
  Future<PagedState<Company>> build() {
    ref.watch(currentUserProvider);
    ref.watch(companyFilterProvider);
    ref.watch(companySearchProvider);
    return loadFirstPage();
  }

  @override
  Future<PagedResponse<Company>> fetchPage(int page) {
    final keyword = ref.read(companySearchProvider);
    return ref.read(platformRepositoryProvider).companies(
          status: ref.read(companyFilterProvider),
          keyword: keyword.isEmpty ? null : keyword,
          page: page,
        );
  }

  /// Applies a change and swaps the row in place rather than reloading — the
  /// admin is usually working through a list and should not lose their place.
  Future<void> setStatus(int id, String status) async {
    final updated =
        await ref.read(platformRepositoryProvider).changeStatus(id, status);
    _applyOrRefresh(updated);
  }

  Future<void> setPlan(
    int id,
    String plan, {
    double? amountPaid,
    String? transactionRef,
  }) async {
    final updated = await ref.read(platformRepositoryProvider).changePlan(
          id,
          plan,
          amountPaid: amountPaid,
          transactionRef: transactionRef,
        );
    _applyOrRefresh(updated);
  }

  void _applyOrRefresh(Company updated) {
    final filter = ref.read(companyFilterProvider);
    // If a filter is active and the change moves the row out of it, the row no
    // longer belongs in this list; otherwise update it where it sits.
    if (filter != null && updated.status != filter) {
      removeItem((company) => company.id == updated.id);
    } else {
      replaceItem((company) => company.id == updated.id, updated);
    }
  }
}

final companiesProvider =
    AsyncNotifierProvider<CompaniesController, PagedState<Company>>(
  CompaniesController.new,
);

final subscriptionPlansProvider =
    FutureProvider<List<SubscriptionPlanOption>>((ref) {
  ref.watch(currentUserProvider);
  return ref.watch(platformRepositoryProvider).plans();
});

class FeatureFlagsController extends AsyncNotifier<List<FeatureFlag>> {
  @override
  Future<List<FeatureFlag>> build() {
    ref.watch(currentUserProvider);
    return ref.read(platformRepositoryProvider).flags();
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(
      () => ref.read(platformRepositoryProvider).flags(),
    );
  }

  /// Flips a flag optimistically.
  ///
  /// A switch that does not move when tapped feels broken, so it moves first
  /// and is put back if the call fails. The confirmed value from the server
  /// replaces the guess either way — a flag is platform-wide, and showing a
  /// stale one is worse than a moment of flicker.
  Future<void> toggle(String key) async {
    final current = state.value;
    if (current == null) return;

    final index = current.indexWhere((flag) => flag.flagKey == key);
    if (index < 0) return;

    final optimistic = [...current]..[index] = current[index].toggled();
    state = AsyncValue.data(optimistic);

    try {
      final confirmed =
          await ref.read(platformRepositoryProvider).toggleFlag(key);
      final settled = [...optimistic]..[index] = confirmed;
      state = AsyncValue.data(settled);
    } catch (_) {
      state = AsyncValue.data(current);
      rethrow;
    }
  }
}

final featureFlagsProvider =
    AsyncNotifierProvider<FeatureFlagsController, List<FeatureFlag>>(
  FeatureFlagsController.new,
);

class PlatformUsersController extends AsyncNotifier<PagedState<PlatformUser>>
    with PagedLoader<PlatformUser> {
  @override
  Future<PagedState<PlatformUser>> build() {
    ref.watch(currentUserProvider);
    return loadFirstPage();
  }

  @override
  Future<PagedResponse<PlatformUser>> fetchPage(int page) =>
      ref.read(platformRepositoryProvider).users(page: page);
}

final platformUsersProvider =
    AsyncNotifierProvider<PlatformUsersController, PagedState<PlatformUser>>(
  PlatformUsersController.new,
);

class ImpersonationHistoryController
    extends AsyncNotifier<PagedState<ImpersonationAuditEntry>>
    with PagedLoader<ImpersonationAuditEntry> {
  @override
  Future<PagedState<ImpersonationAuditEntry>> build() {
    ref.watch(currentUserProvider);
    return loadFirstPage();
  }

  @override
  Future<PagedResponse<ImpersonationAuditEntry>> fetchPage(int page) =>
      ref.read(platformRepositoryProvider).impersonationHistory(page: page);
}

final impersonationHistoryProvider = AsyncNotifierProvider<
    ImpersonationHistoryController, PagedState<ImpersonationAuditEntry>>(
  ImpersonationHistoryController.new,
);
