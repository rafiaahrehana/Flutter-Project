import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/paged_response.dart';
import '../../core/providers.dart';
import '../../shared/paged_controller.dart';
import '../profile/employee_repository.dart';
import 'leave_models.dart';

class LeaveRepository {
  LeaveRepository(this._api);

  final ApiClient _api;

  static const _leaves = '/hr/leaves';
  static const _balances = '/hr/leave-balances';

  Future<PagedResponse<LeaveRequest>> myRequests({
    int page = 0,
    int size = 20,
  }) =>
      _api.getPaged('$_leaves/my', LeaveRequest.fromJson, page: page, size: size);

  Future<LeaveRequest> apply(LeaveRequestPayload payload) async {
    final json =
        await _api.post<Map<String, dynamic>>(_leaves, payload.toJson());
    return LeaveRequest.fromJson(json);
  }

  /// Returns text/plain, so nothing is parsed out of the response.
  Future<void> cancel(int id) => _api.patchText('$_leaves/$id/cancel');

  /// Every employee's requests — the reviewer's queue.
  Future<PagedResponse<LeaveRequest>> allRequests({
    String? status,
    int page = 0,
    int size = 20,
  }) =>
      _api.getPaged(
        _leaves,
        LeaveRequest.fromJson,
        page: page,
        size: size,
        query: {'status': status},
      );

  /// Approves or rejects. Only a PENDING request can be reviewed — the backend
  /// refuses anything else — so the caller must not offer this on a decided one.
  Future<LeaveRequest> review(int id, ReviewLeaveRequest request) async {
    final json = await _api.patch<Map<String, dynamic>>(
      '$_leaves/$id/review',
      request.toJson(),
    );
    return LeaveRequest.fromJson(json);
  }

  /// One employee's balances, for deciding a request against what they have
  /// left. Optional: a reviewer without LEAVE_VIEW on balances still gets the
  /// queue, just without the context.
  Future<List<LeaveBalance>> employeeBalances(int employeeId, {int? year}) async {
    try {
      // Note the prefix: this one hangs off the *leaves* controller, while
      // `myBalances` above uses the separate leave-balances controller. They
      // are different endpoints with confusingly similar names.
      final list = await _api.get<List<dynamic>>(
        '$_leaves/balances/employee/$employeeId',
        query: {'year': year},
      );
      return list
          .whereType<Map<String, dynamic>>()
          .map(LeaveBalance.fromJson)
          .toList(growable: false);
    } on ApiException catch (e) {
      if (e.isForbidden || e.isNotFound) return const [];
      rethrow;
    }
  }

  /// Balances for the caller. The unscoped list endpoint returns every
  /// employee's, which an employee neither needs nor should see.
  ///
  /// An employee whose HR has not configured balances yet gets a 403 or an
  /// empty list, and neither is an error worth showing: the screen simply has
  /// no balances to draw.
  Future<List<LeaveBalance>> myBalances({int? year}) async {
    try {
      final list = await _api.get<List<dynamic>>(
        '$_balances/my',
        query: {'year': year},
      );
      return list
          .whereType<Map<String, dynamic>>()
          .map(LeaveBalance.fromJson)
          .toList(growable: false);
    } on ApiException catch (e) {
      if (e.isForbidden || e.isNotFound) return const [];
      rethrow;
    }
  }
}

final leaveRepositoryProvider = Provider<LeaveRepository>(
  (ref) => LeaveRepository(ref.watch(apiClientProvider)),
);

@immutable
class LeaveState {
  const LeaveState({
    this.requests = const [],
    this.balances = const [],
    this.page = 0,
    this.totalPages = 0,
    this.loadingMore = false,
    this.hasEmployeeRecord = true,
  });

  final List<LeaveRequest> requests;
  final List<LeaveBalance> balances;
  final int page;
  final int totalPages;
  final bool loadingMore;

  /// False when the signed-in account has no employee record — an owner, say.
  /// Leave is recorded against an employee, so there is nothing to list and
  /// nothing to apply for, and the screen should say which of the two empty
  /// states this is.
  final bool hasEmployeeRecord;

  bool get hasMore => page + 1 < totalPages;

  /// Total days still available across every type, or null when no balances
  /// are configured — a dash, not a zero, since zero would read as "you have
  /// used everything up".
  double? get totalAvailable {
    if (balances.isEmpty) return null;
    return balances.fold<double>(0, (sum, b) => sum + b.remainingDays);
  }

  LeaveState copyWith({
    List<LeaveRequest>? requests,
    List<LeaveBalance>? balances,
    int? page,
    int? totalPages,
    bool? loadingMore,
    bool? hasEmployeeRecord,
  }) =>
      LeaveState(
        requests: requests ?? this.requests,
        balances: balances ?? this.balances,
        page: page ?? this.page,
        totalPages: totalPages ?? this.totalPages,
        loadingMore: loadingMore ?? this.loadingMore,
        hasEmployeeRecord: hasEmployeeRecord ?? this.hasEmployeeRecord,
      );
}

class LeaveController extends AsyncNotifier<LeaveState> {
  @override
  Future<LeaveState> build() {
    // Bound to the signed-in user so that signing out and signing back in as
    // someone else rebuilds this. Without it the provider — which is not
    // auto-disposed — would keep serving the previous person's leave requests
    // to the new one, and nothing would ever invalidate them.
    ref.watch(currentUserProvider);
    return _load();
  }

  Future<LeaveState> _load() async {
    // Checked first because `/hr/leaves/my` answers a missing employee record
    // with a 400, not an empty page. Asking anyway would turn a perfectly
    // ordinary situation into a red error banner on a main tab.
    //
    // `read`, not `watch`: this runs from refresh() too, outside any build.
    final employee = await ref.read(myEmployeeProvider.future);
    if (employee == null) return const LeaveState(hasEmployeeRecord: false);

    final repo = ref.read(leaveRepositoryProvider);
    final requestsCall = repo.myRequests();
    final balancesCall = repo.myBalances();

    final requests = await requestsCall;
    return LeaveState(
      requests: requests.content,
      balances: await balancesCall,
      page: requests.currentPage,
      totalPages: requests.totalPages,
    );
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(_load);
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;

    state = AsyncValue.data(current.copyWith(loadingMore: true));
    try {
      final next = await ref
          .read(leaveRepositoryProvider)
          .myRequests(page: current.page + 1);
      state = AsyncValue.data(
        current.copyWith(
          requests: [...current.requests, ...next.content],
          page: next.currentPage,
          totalPages: next.totalPages,
          loadingMore: false,
        ),
      );
    } catch (_) {
      state = AsyncValue.data(current.copyWith(loadingMore: false));
      rethrow;
    }
  }

  /// Applies, then reloads. The server decides `totalDays` (it excludes
  /// weekends and holidays from the count) and the starting status, so the new
  /// row is read back rather than assembled locally from the form.
  Future<void> apply(LeaveRequestPayload payload) async {
    await ref.read(leaveRepositoryProvider).apply(payload);
    await refresh();
  }

  Future<void> cancel(int id) async {
    await ref.read(leaveRepositoryProvider).cancel(id);
    await refresh();
  }
}

final leaveControllerProvider =
    AsyncNotifierProvider<LeaveController, LeaveState>(LeaveController.new);

/// Which slice of the reviewer's queue is showing. Pending is the default
/// because that is the only status anyone can act on.
class LeaveQueueFilterController extends Notifier<String?> {
  @override
  String? build() => LeaveStatus.pending;

  void set(String? status) {
    if (state == status) return;
    state = status;
  }
}

final leaveQueueFilterProvider =
    NotifierProvider<LeaveQueueFilterController, String?>(
  LeaveQueueFilterController.new,
);

/// Everyone's leave requests, for someone who reviews them.
class LeaveQueueController extends AsyncNotifier<PagedState<LeaveRequest>>
    with PagedLoader<LeaveRequest> {
  @override
  Future<PagedState<LeaveRequest>> build() {
    ref.watch(currentUserProvider);
    ref.watch(leaveQueueFilterProvider);
    return loadFirstPage();
  }

  @override
  Future<PagedResponse<LeaveRequest>> fetchPage(int page) => ref
      .read(leaveRepositoryProvider)
      .allRequests(status: ref.read(leaveQueueFilterProvider), page: page);

  /// Decides a request.
  ///
  /// Approving moves days out of the employee's pending balance and into used,
  /// so their balances — and the reviewer's own, if they are looking at their
  /// own list — are stale afterwards and get invalidated.
  Future<void> review(int id, ReviewLeaveRequest request) async {
    await ref.read(leaveRepositoryProvider).review(id, request);

    if (ref.read(leaveQueueFilterProvider) == LeaveStatus.pending) {
      // A decided request is no longer pending, so it leaves this list.
      removeItem((leave) => leave.id == id);
    } else {
      await refresh();
    }
    ref.invalidate(employeeBalancesProvider);
    ref.read(leaveControllerProvider.notifier).refresh();
  }
}

final leaveQueueProvider =
    AsyncNotifierProvider<LeaveQueueController, PagedState<LeaveRequest>>(
  LeaveQueueController.new,
);

/// One employee's balances, for judging a request against what they have left.
///
/// Auto-disposed and keyed by employee: a reviewer works through a queue of
/// different people, and holding every one of them would be a slow leak for no
/// benefit.
final employeeBalancesProvider =
    FutureProvider.autoDispose.family<List<LeaveBalance>, int>(
  (ref, employeeId) =>
      ref.watch(leaveRepositoryProvider).employeeBalances(employeeId),
);
