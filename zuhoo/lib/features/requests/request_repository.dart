import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/paged_response.dart';
import '../../core/providers.dart';
import 'request_models.dart';

class RequestRepository {
  RequestRepository(this._api);

  final ApiClient _api;

  static const _base = '/service-requests';
  static const _approvals = '/approvals';

  /// Requests raised by this user **as a portal client**.
  ///
  /// Client-scoped, not "mine" in the everyday sense: the backend looks up a
  /// Client row by user id and answers 400 "Client profile not found" for any
  /// staff account, which is most of this app's users. The screen only offers
  /// this list to a CLIENT, and the catch below is the backstop for anything
  /// that reaches it another way — a 400 here means "not applicable to you",
  /// not "something broke".
  Future<PagedResponse<ServiceRequest>> mine({int page = 0, int size = 20}) async {
    try {
      return await _api.getPaged(
        '$_base/my',
        ServiceRequest.fromJson,
        page: page,
        size: size,
      );
    } on ApiException catch (e) {
      if (e.statusCode == 400 || e.isForbidden || e.isNotFound) {
        return const PagedResponse<ServiceRequest>.empty();
      }
      rethrow;
    }
  }

  /// Requests assigned to this user to work on.
  Future<PagedResponse<ServiceRequest>> assignedToMe({
    int page = 0,
    int size = 20,
  }) =>
      _api.getPaged(
        '$_base/assigned-to-me',
        ServiceRequest.fromJson,
        page: page,
        size: size,
      );

  Future<ServiceRequest> byId(int id) async {
    final json = await _api.get<Map<String, dynamic>>('$_base/$id');
    return ServiceRequest.fromJson(json);
  }

  Future<ServiceRequest> create(CreateServiceRequest request) async {
    final json = await _api.post<Map<String, dynamic>>(_base, request.toJson());
    return ServiceRequest.fromJson(json);
  }

  /// text/plain response.
  Future<void> cancel(int id) => _api.patchText('$_base/$id/cancel');

  Future<PagedResponse<RequestComment>> comments(
    int id, {
    int page = 0,
    int size = 30,
  }) =>
      _api.getPaged(
        '$_base/$id/comments',
        RequestComment.fromJson,
        page: page,
        size: size,
      );

  /// Visibility is deliberately not sent: the backend picks a role-aware
  /// default (a client's comment is PUBLIC, a staff member's is INTERNAL), and
  /// a phone guessing wrong would either leak an internal note to the client or
  /// hide a reply they were waiting for.
  Future<RequestComment> addComment(int id, String content) async {
    final json = await _api.post<Map<String, dynamic>>(
      '$_base/$id/comments',
      {'content': content.trim()},
    );
    return RequestComment.fromJson(json);
  }

  /// The status timeline. Optional: an employee without the permission to read
  /// history should still get the rest of the detail screen.
  Future<List<RequestStatusChange>> history(int id) async {
    try {
      final list = await _api.get<List<dynamic>>('$_base/$id/history');
      return list
          .whereType<Map<String, dynamic>>()
          .map(RequestStatusChange.fromJson)
          .toList(growable: false);
    } on ApiException catch (e) {
      if (e.isForbidden || e.isNotFound) return const [];
      rethrow;
    }
  }

  /// The active catalogue, for the raise-a-request sheet.
  Future<List<CatalogService>> activeServices() async {
    final list = await _api.get<List<dynamic>>('/services/active');
    return list
        .whereType<Map<String, dynamic>>()
        .map(CatalogService.fromJson)
        .toList(growable: false);
  }

  // ── Approvals ───────────────────────────────────────────────

  Future<PagedResponse<StageApproval>> pendingApprovals({
    int page = 0,
    int size = 20,
  }) =>
      _api.getPaged(
        '$_approvals/pending',
        StageApproval.fromJson,
        page: page,
        size: size,
      );

  /// The note is omitted rather than sent as null when there isn't one — the
  /// web app's `{ decisionNotes }` drops an undefined key on serialisation, and
  /// sending an explicit null is a different thing to a validator that has to
  /// tell "not provided" from "provided as empty".
  Future<void> approve(int id, {String? notes}) => _api.post<dynamic>(
        '$_approvals/$id/approve',
        {
          if (notes != null && notes.trim().isNotEmpty)
            'decisionNotes': notes.trim(),
        },
      );

  /// A rejection must say why — the backend requires the notes, and an
  /// unexplained rejection is useless to whoever has to act on it.
  Future<void> reject(int id, String notes) => _api.post<dynamic>(
        '$_approvals/$id/reject',
        {'decisionNotes': notes.trim()},
      );
}

final requestRepositoryProvider = Provider<RequestRepository>(
  (ref) => RequestRepository(ref.watch(apiClientProvider)),
);
