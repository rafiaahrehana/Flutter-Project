import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/paged_response.dart';
import '../../shared/paged_controller.dart';
import 'request_models.dart';
import 'request_repository.dart';

/// Requests this user raised.
class MyRequestsController extends AsyncNotifier<PagedState<ServiceRequest>>
    with PagedLoader<ServiceRequest> {
  @override
  Future<PagedState<ServiceRequest>> build() {
    // Rebuilt on sign-in/out, like the other list controllers, so a second
    // account on the same device never inherits the first one's requests.
    ref.watch(currentUserProvider);
    return loadFirstPage();
  }

  @override
  Future<PagedResponse<ServiceRequest>> fetchPage(int page) =>
      ref.read(requestRepositoryProvider).mine(page: page);

  /// Raises a request and puts it at the top of the list.
  ///
  /// Reloaded rather than prepended from the response: the backend assigns the
  /// status, the SLA deadline and possibly a workflow stage on create, and a
  /// locally-assembled row would show none of that until the next refresh.
  Future<ServiceRequest> create(CreateServiceRequest request) async {
    final created = await ref.read(requestRepositoryProvider).create(request);
    await refresh();
    return created;
  }

  Future<void> cancel(int id) async {
    await ref.read(requestRepositoryProvider).cancel(id);
    await refresh();
  }
}

final myRequestsProvider =
    AsyncNotifierProvider<MyRequestsController, PagedState<ServiceRequest>>(
  MyRequestsController.new,
);

/// Requests assigned to this user to work on.
class AssignedRequestsController
    extends AsyncNotifier<PagedState<ServiceRequest>>
    with PagedLoader<ServiceRequest> {
  @override
  Future<PagedState<ServiceRequest>> build() {
    ref.watch(currentUserProvider);
    return loadFirstPage();
  }

  @override
  Future<PagedResponse<ServiceRequest>> fetchPage(int page) =>
      ref.read(requestRepositoryProvider).assignedToMe(page: page);
}

final assignedRequestsProvider = AsyncNotifierProvider<
    AssignedRequestsController, PagedState<ServiceRequest>>(
  AssignedRequestsController.new,
);

/// Workflow stages waiting on this user's decision.
class ApprovalsController extends AsyncNotifier<PagedState<StageApproval>>
    with PagedLoader<StageApproval> {
  @override
  Future<PagedState<StageApproval>> build() {
    ref.watch(currentUserProvider);
    return loadFirstPage();
  }

  @override
  Future<PagedResponse<StageApproval>> fetchPage(int page) =>
      ref.read(requestRepositoryProvider).pendingApprovals(page: page);

  /// Deciding an approval removes it from this list — it is the *pending*
  /// list, and a decided row no longer belongs in it. Dropped immediately so
  /// the queue visibly shrinks as it is worked through, then reconciled with
  /// the server on the next refresh.
  Future<void> decide(
    int id, {
    required bool approved,
    String? notes,
  }) async {
    final repo = ref.read(requestRepositoryProvider);
    if (approved) {
      await repo.approve(id, notes: notes);
    } else {
      await repo.reject(id, notes ?? '');
    }
    removeItem((approval) => approval.id == id);
  }
}

final approvalsProvider =
    AsyncNotifierProvider<ApprovalsController, PagedState<StageApproval>>(
  ApprovalsController.new,
);

/// One request, keyed by id.
///
/// Auto-disposed: a request's status, assignee and comment count all move while
/// you are not looking at it, so re-reading on open is right — and it keeps a
/// long session from accumulating every request the user has ever tapped.
final requestDetailProvider =
    FutureProvider.autoDispose.family<ServiceRequest, int>((ref, id) {
  return ref.watch(requestRepositoryProvider).byId(id);
});

final requestCommentsProvider =
    FutureProvider.autoDispose.family<List<RequestComment>, int>((ref, id) async {
  final page = await ref.watch(requestRepositoryProvider).comments(id);
  // Oldest first: a conversation reads top to bottom, and the newest reply is
  // where the reader is heading anyway.
  final comments = [...page.content]
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  return comments;
});

final requestHistoryProvider = FutureProvider.autoDispose
    .family<List<RequestStatusChange>, int>((ref, id) async {
  final history = await ref.watch(requestRepositoryProvider).history(id);
  // Newest first: the current state is what a phone screen should open on.
  final sorted = [...history]
    ..sort((a, b) => b.changedAt.compareTo(a.changedAt));
  return sorted;
});

/// The active catalogue for the raise-a-request sheet.
///
/// Bound to the signed-in user, not merely cached. The catalogue is a *tenant's*
/// list of services; without this, signing out and signing in as someone from
/// another company would offer them the previous company's services — and the
/// backend would then reject the ids, which looks like a broken app rather than
/// a leaked list.
final catalogServicesProvider = FutureProvider<List<CatalogService>>((ref) {
  ref.watch(currentUserProvider);
  return ref.watch(requestRepositoryProvider).activeServices();
});
