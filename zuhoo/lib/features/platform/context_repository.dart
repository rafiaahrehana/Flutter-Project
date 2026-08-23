import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/paged_response.dart';
import '../../core/providers.dart';
import '../../shared/paged_controller.dart';
import 'context_models.dart';

/// Support context switches.
///
/// Note the prefix: `/support/context-switches`, **not** the `/v1/support/...`
/// the ticket endpoints use. The support module is versioned in one half and
/// not the other, so the path cannot be shared with the tickets repository.
class ContextSwitchRepository {
  ContextSwitchRepository(this._api);

  final ApiClient _api;

  static const _base = '/support/context-switches';

  /// Declares that the caller is now working inside [companyId].
  ///
  /// The agent is taken from the session, never from the body — an earlier
  /// version of this endpoint accepted both the actor and the IP as JSON,
  /// which let the one record meant to hold someone accountable be written by
  /// the person it was about.
  ///
  /// Starting a second switch silently ends the first: the backend allows one
  /// active switch per agent and closes the previous one itself.
  Future<SupportContextSwitch> start({
    required int companyId,
    String? purpose,
  }) async {
    final trimmed = purpose?.trim();
    final json = await _api.post<Map<String, dynamic>>('$_base/switch', {
      'viewedCompanyId': companyId,
      // Optional here, unlike impersonation's reason, so an empty box is sent
      // as absent rather than as a blank string that reads like a real answer.
      if (trimmed != null && trimmed.isNotEmpty) 'purpose': trimmed,
    });
    return SupportContextSwitch.fromJson(json);
  }

  Future<void> end(int id) => _api.post<dynamic>('$_base/$id/end');

  /// The agent's current switch, or null when they have none.
  ///
  /// "None" arrives as a **404**, not as an empty 200 — the service throws
  /// `ResourceNotFoundException` rather than returning an optional. Having no
  /// switch open is the normal state for most of the day, so treating that as
  /// an error would put a red banner on the screen of everyone who is simply
  /// not working on anything right now.
  Future<SupportContextSwitch?> activeForAgent(int agentId) async {
    try {
      final json = await _api.get<Map<String, dynamic>>(
        '$_base/active/agent/$agentId',
      );
      return SupportContextSwitch.fromJson(json);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Everyone currently inside a company. Managers and above only.
  Future<List<SupportContextSwitch>> activeEverywhere() async {
    final list = await _api.get<List<dynamic>>('$_base/active');
    return list
        .whereType<Map<String, dynamic>>()
        .map(SupportContextSwitch.fromJson)
        .toList(growable: false);
  }

  /// One agent's past switches. Managers and above only — an agent cannot
  /// read even their own.
  Future<PagedResponse<SupportContextSwitch>> historyForAgent(
    int agentId, {
    int page = 0,
    int size = 20,
  }) =>
      _api.getPaged(
        '$_base/history/agent/$agentId',
        SupportContextSwitch.fromJson,
        page: page,
        size: size,
      );
}

final contextSwitchRepositoryProvider = Provider<ContextSwitchRepository>(
  (ref) => ContextSwitchRepository(ref.watch(apiClientProvider)),
);

/// The signed-in agent's own open switch, if any.
class MyContextSwitchController extends AsyncNotifier<SupportContextSwitch?> {
  @override
  Future<SupportContextSwitch?> build() async {
    final user = ref.watch(currentUserProvider);
    // Gated here as well as in the UI: without the role this 403s, and a
    // failed request would render as "something went wrong" on a screen the
    // person is entitled to see the rest of.
    if (user == null || !user.hasAnyRole(contextSwitchRoles)) return null;
    return ref.read(contextSwitchRepositoryProvider).activeForAgent(user.id);
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(build);
  }

  Future<void> start({required int companyId, String? purpose}) async {
    final started = await ref
        .read(contextSwitchRepositoryProvider)
        .start(companyId: companyId, purpose: purpose);
    state = AsyncValue.data(started);
    // Starting one closes any previous one server-side, so the board other
    // people are looking at is now wrong in two places.
    ref.invalidate(activeContextSwitchesProvider);
  }

  Future<void> end() async {
    final current = state.value;
    if (current == null) return;
    await ref.read(contextSwitchRepositoryProvider).end(current.id);
    state = const AsyncValue.data(null);
    ref.invalidate(activeContextSwitchesProvider);
  }
}

final myContextSwitchProvider =
    AsyncNotifierProvider<MyContextSwitchController, SupportContextSwitch?>(
  MyContextSwitchController.new,
);

/// The live board: everyone currently inside a company.
final activeContextSwitchesProvider =
    FutureProvider<List<SupportContextSwitch>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null || !user.hasAnyRole(contextSwitchReviewRoles)) {
    return Future.value(const []);
  }
  return ref.read(contextSwitchRepositoryProvider).activeEverywhere();
});

/// One agent's history, keyed by agent id.
class AgentContextHistoryController
    extends AsyncNotifier<PagedState<SupportContextSwitch>>
    with PagedLoader<SupportContextSwitch> {
  AgentContextHistoryController(this.agentId);

  /// Riverpod 3 hands a family argument to the constructor rather than to
  /// build(), so it is held here for fetchPage to read on every page.
  final int agentId;

  @override
  Future<PagedState<SupportContextSwitch>> build() {
    ref.watch(currentUserProvider);
    return loadFirstPage();
  }

  @override
  Future<PagedResponse<SupportContextSwitch>> fetchPage(int page) =>
      ref.read(contextSwitchRepositoryProvider).historyForAgent(
            agentId,
            page: page,
          );
}

final agentContextHistoryProvider = AsyncNotifierProvider.family<
    AgentContextHistoryController, PagedState<SupportContextSwitch>, int>(
  AgentContextHistoryController.new,
);
