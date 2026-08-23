import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/paged_response.dart';
import '../../shared/paged_controller.dart';
import 'crm_models.dart';
import 'crm_repository.dart';

/// Which lead view the Leads tab is showing. A plain notifier rather than
/// widget state so switching views survives navigating into a lead and back.
class LeadViewController extends Notifier<LeadView> {
  @override
  LeadView build() => LeadView.mine;

  void set(LeadView view) {
    if (state == view) return;
    state = view;
  }
}

final leadViewProvider =
    NotifierProvider<LeadViewController, LeadView>(LeadViewController.new);

class LeadsController extends AsyncNotifier<PagedState<Lead>>
    with PagedLoader<Lead> {
  @override
  Future<PagedState<Lead>> build() {
    ref.watch(currentUserProvider);
    // Watched, not read: changing the view is what reloads this list.
    ref.watch(leadViewProvider);
    return loadFirstPage();
  }

  @override
  Future<PagedResponse<Lead>> fetchPage(int page) => ref
      .read(crmRepositoryProvider)
      .leads(ref.read(leadViewProvider), page: page);

  Future<Lead> create(CreateLeadRequest request) async {
    final created = await ref.read(crmRepositoryProvider).createLead(request);
    await refresh();
    return created;
  }
}

final leadsProvider = AsyncNotifierProvider<LeadsController, PagedState<Lead>>(
  LeadsController.new,
);

final leadDetailProvider = FutureProvider.autoDispose.family<Lead, int>(
  (ref, id) => ref.watch(crmRepositoryProvider).lead(id),
);

final leadActivitiesProvider =
    FutureProvider.autoDispose.family<List<CrmActivity>, int>(
  (ref, id) => ref.watch(crmRepositoryProvider).leadActivities(id),
);

/// Which stage the pipeline is filtered to. Null means every open stage.
class PipelineStageController extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? stage) {
    if (state == stage) return;
    state = stage;
  }
}

final pipelineStageProvider =
    NotifierProvider<PipelineStageController, String?>(
  PipelineStageController.new,
);

class OpportunitiesController extends AsyncNotifier<PagedState<Opportunity>>
    with PagedLoader<Opportunity> {
  @override
  Future<PagedState<Opportunity>> build() {
    ref.watch(currentUserProvider);
    ref.watch(pipelineStageProvider);
    return loadFirstPage();
  }

  @override
  Future<PagedResponse<Opportunity>> fetchPage(int page) => ref
      .read(crmRepositoryProvider)
      .opportunities(stage: ref.read(pipelineStageProvider), page: page);

  /// Moves a deal, then refreshes the list and the headline figures.
  ///
  /// The summary is refetched rather than adjusted locally: probability and the
  /// weighted forecast are server-derived from the stage, and a phone
  /// recalculating them would quietly disagree with the web app's numbers.
  Future<Opportunity> changeStage(int id, ChangeStageRequest request) async {
    final updated =
        await ref.read(crmRepositoryProvider).changeStage(id, request);
    ref.invalidate(pipelineSummaryProvider);
    ref.invalidate(opportunityDetailProvider(id));
    await refresh();
    return updated;
  }
}

final opportunitiesProvider =
    AsyncNotifierProvider<OpportunitiesController, PagedState<Opportunity>>(
  OpportunitiesController.new,
);

final opportunityDetailProvider =
    FutureProvider.autoDispose.family<Opportunity, int>(
  (ref, id) => ref.watch(crmRepositoryProvider).opportunity(id),
);

final pipelineSummaryProvider = FutureProvider<PipelineSummary>((ref) {
  ref.watch(currentUserProvider);
  return ref.watch(crmRepositoryProvider).pipelineSummary();
});

class ClientsController extends AsyncNotifier<PagedState<Client>>
    with PagedLoader<Client> {
  @override
  Future<PagedState<Client>> build() {
    ref.watch(currentUserProvider);
    return loadFirstPage();
  }

  @override
  Future<PagedResponse<Client>> fetchPage(int page) =>
      ref.read(crmRepositoryProvider).clients(page: page);
}

final clientsProvider =
    AsyncNotifierProvider<ClientsController, PagedState<Client>>(
  ClientsController.new,
);

final clientDetailProvider = FutureProvider.autoDispose.family<Client, int>(
  (ref, id) => ref.watch(crmRepositoryProvider).client(id),
);
