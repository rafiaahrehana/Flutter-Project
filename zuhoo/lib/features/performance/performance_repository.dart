import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/network/paged_response.dart';
import '../../core/providers.dart';
import '../../shared/paged_controller.dart';
import '../profile/employee_repository.dart';
import 'performance_models.dart';

/// Performance reviews.
///
/// Read and progress only. Writing a review means nine scores plus six free
///-text sections plus promotion, salary and training recommendations — the
/// appraisal form itself, which belongs on a desk. Attachments are omitted for
/// the same reason a file picker is: the phone is where you read the review
/// and move it along, not where you compose it.
class PerformanceRepository {
  PerformanceRepository(this._api);

  final ApiClient _api;

  static const _base = '/hr/performance';

  Future<PagedResponse<PerformanceReview>> all({
    int page = 0,
    int size = 20,
  }) =>
      _api.getPaged(
        _base,
        PerformanceReview.fromJson,
        page: page,
        size: size,
      );

  /// One person's reviews.
  ///
  /// Reachable without PERFORMANCE_VIEW when the id is the caller's own —
  /// `guardOwnReviewAccess` allows it deliberately, so this is what the
  /// personal tab uses.
  Future<List<PerformanceReview>> forEmployee(int employeeId) async {
    final list =
        await _api.get<List<dynamic>>('$_base/employee/$employeeId');
    return list
        .whereType<Map<String, dynamic>>()
        .map(PerformanceReview.fromJson)
        .toList(growable: false);
  }

  Future<PerformanceReview> review(int id) async {
    final json = await _api.get<Map<String, dynamic>>('$_base/$id');
    return PerformanceReview.fromJson(json);
  }

  /// Moves a review to the next stage. The backend decides which that is —
  /// there is no way to jump or to go back, so the UI offers one button.
  Future<PerformanceReview> advance(int id) async {
    final json = await _api.post<Map<String, dynamic>>('$_base/$id/advance');
    return PerformanceReview.fromJson(json);
  }

  /// Signs the review off. Irreversible.
  Future<PerformanceReview> finalise(int id) async {
    final json = await _api.patch<Map<String, dynamic>>('$_base/$id/finalise');
    return PerformanceReview.fromJson(json);
  }
}

final performanceRepositoryProvider = Provider<PerformanceRepository>(
  (ref) => PerformanceRepository(ref.watch(apiClientProvider)),
);

/// Everybody's reviews. Needs PERFORMANCE_VIEW.
class TeamReviewsController extends AsyncNotifier<PagedState<PerformanceReview>>
    with PagedLoader<PerformanceReview> {
  @override
  Future<PagedState<PerformanceReview>> build() {
    ref.watch(currentUserProvider);
    return loadFirstPage();
  }

  @override
  Future<PagedResponse<PerformanceReview>> fetchPage(int page) =>
      ref.read(performanceRepositoryProvider).all(page: page);

  void apply(PerformanceReview updated) =>
      replaceItem((review) => review.id == updated.id, updated);
}

final teamReviewsProvider =
    AsyncNotifierProvider<TeamReviewsController, PagedState<PerformanceReview>>(
  TeamReviewsController.new,
);

/// The signed-in person's own reviews.
///
/// Depends on their employee record, which company owners do not have — the
/// screen explains that rather than showing an error.
final myReviewsProvider = FutureProvider<List<PerformanceReview>>((ref) async {
  final employee = await ref.watch(myEmployeeProvider.future);
  if (employee == null) return const [];
  return ref.read(performanceRepositoryProvider).forEmployee(employee.id);
});
