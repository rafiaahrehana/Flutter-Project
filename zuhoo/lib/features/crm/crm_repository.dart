import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/paged_response.dart';
import '../../core/providers.dart';
import 'crm_models.dart';

/// Which slice of leads to show. Each is a server-side definition rather than
/// a client-side filter, so "stale" means whatever the backend says it means
/// and cannot drift from the web app's answer.
enum LeadView { mine, all, highPriority, neverContacted, stale, unassigned }

class CrmRepository {
  CrmRepository(this._api);

  final ApiClient _api;

  static const _leads = '/crm/leads';
  static const _opportunities = '/crm/opportunities';
  static const _clients = '/clients';

  // ── Leads ───────────────────────────────────────────────────

  Future<PagedResponse<Lead>> leads(
    LeadView view, {
    int page = 0,
    int size = 20,
  }) {
    final path = switch (view) {
      LeadView.mine => '$_leads/my',
      LeadView.all => _leads,
      LeadView.highPriority => '$_leads/high-priority',
      LeadView.neverContacted => '$_leads/never-contacted',
      LeadView.stale => '$_leads/stale',
      LeadView.unassigned => '$_leads/unassigned',
    };
    return _api.getPaged(path, Lead.fromJson, page: page, size: size);
  }

  Future<Lead> lead(int id) async {
    final json = await _api.get<Map<String, dynamic>>('$_leads/$id');
    return Lead.fromJson(json);
  }

  Future<Lead> createLead(CreateLeadRequest request) async {
    final json = await _api.post<Map<String, dynamic>>(_leads, request.toJson());
    return Lead.fromJson(json);
  }

  /// Turns a qualified lead into an opportunity. No client is created here —
  /// that happens later, if and when the opportunity is won.
  Future<Opportunity> convertLead(int id, ConvertLeadRequest request) async {
    final json = await _api.patch<Map<String, dynamic>>(
      '$_leads/$id/convert-to-opportunity',
      request.toJson(),
    );
    return Opportunity.fromJson(json);
  }

  /// Lead activities have their own endpoints: the generic `/crm/activities`
  /// one requires a clientId or opportunityId, neither of which a lead has.
  Future<List<CrmActivity>> leadActivities(int id) async {
    final page = await _api.getPaged(
      '$_leads/$id/activities',
      CrmActivity.fromJson,
      page: 0,
      size: 50,
    );
    final activities = [...page.content]
      ..sort((a, b) => b.activityDate.compareTo(a.activityDate));
    return activities;
  }

  Future<CrmActivity> logActivity(int id, LogActivityRequest request) async {
    final json = await _api.post<Map<String, dynamic>>(
      '$_leads/$id/activities',
      request.toJson(),
    );
    return CrmActivity.fromJson(json);
  }

  // ── Opportunities ───────────────────────────────────────────

  Future<PagedResponse<Opportunity>> opportunities({
    String? stage,
    int page = 0,
    int size = 20,
  }) =>
      _api.getPaged(
        _opportunities,
        Opportunity.fromJson,
        page: page,
        size: size,
        query: {'stage': stage},
      );

  Future<Opportunity> opportunity(int id) async {
    final json = await _api.get<Map<String, dynamic>>('$_opportunities/$id');
    return Opportunity.fromJson(json);
  }

  Future<PipelineSummary> pipelineSummary() async {
    final json =
        await _api.get<Map<String, dynamic>>('$_opportunities/pipeline-summary');
    return PipelineSummary.fromJson(json);
  }

  Future<Opportunity> changeStage(int id, ChangeStageRequest request) async {
    final json = await _api.patch<Map<String, dynamic>>(
      '$_opportunities/$id/stage',
      request.toJson(),
    );
    return Opportunity.fromJson(json);
  }

  /// Asks whether winning this deal would duplicate an existing client.
  ///
  /// Fails open, exactly as the web app does: a preview check that cannot
  /// complete must not stand between a rep and closing a deal. A null answer
  /// means "no duplicate, or we could not tell" and the caller proceeds.
  Future<DuplicateMatch?> wonDuplicateCheck(int id) async {
    try {
      final json =
          await _api.get<dynamic>('$_opportunities/$id/won-duplicate-check');
      return DuplicateMatch.tryFrom(json);
    } on ApiException {
      return null;
    }
  }

  // ── Clients ─────────────────────────────────────────────────

  Future<PagedResponse<Client>> clients({int page = 0, int size = 20}) =>
      _api.getPaged(_clients, Client.fromJson, page: page, size: size);

  Future<Client> client(int id) async {
    final json = await _api.get<Map<String, dynamic>>('$_clients/$id');
    return Client.fromJson(json);
  }
}

final crmRepositoryProvider = Provider<CrmRepository>(
  (ref) => CrmRepository(ref.watch(apiClientProvider)),
);
