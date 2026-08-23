import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/permission_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/providers.dart';
import 'search_models.dart';

/// One query across leads, clients, opportunities, service requests, tickets,
/// invoices and refunds.
///
/// `POST /search/ask` — the assistant's question-and-answer form of the same
/// thing — is not here. It belongs with the AI module and needs `AI_CHAT`,
/// which is a different entitlement from looking something up.
class SearchRepository {
  SearchRepository(this._api);

  final ApiClient _api;

  Future<SearchResults> search(String query) async {
    final json = await _api.get<Map<String, dynamic>>(
      '/search',
      query: {'q': query},
    );
    return SearchResults.fromJson(json);
  }
}

final searchRepositoryProvider = Provider<SearchRepository>(
  (ref) => SearchRepository(ref.watch(apiClientProvider)),
);

/// The term being searched for. Empty means the screen is idle.
class SearchQueryController extends Notifier<String> {
  @override
  String build() => '';

  void set(String value) {
    final trimmed = value.trim();
    if (state == trimmed) return;
    state = trimmed;
  }
}

final searchQueryProvider = NotifierProvider<SearchQueryController, String>(
  SearchQueryController.new,
);

/// Results for the current term, filtered to what the reader may actually see.
///
/// The filtering happens here rather than in the widget so that every consumer
/// gets the same list — there is no path through the app that reaches the
/// unfiltered response.
final searchResultsProvider = FutureProvider<SearchResults?>((ref) async {
  final query = ref.watch(searchQueryProvider);

  // One character matches most of a database and tells the reader nothing.
  if (query.length < 2) return null;

  final permissions = ref.watch(permissionControllerProvider);
  final raw = await ref.read(searchRepositoryProvider).search(query);

  final visible = raw.hits.where((hit) {
    // A kind this build does not recognise cannot be gated, so it is not
    // shown. New result types should arrive with a permission mapping.
    if (!SearchKind.isKnown(hit.type)) return false;
    return permissions.has(SearchKind.of(hit.type).permission);
  }).toList(growable: false);

  return SearchResults(
    query: raw.query,
    hits: visible,
    totalMatches: raw.totalMatches,
  );
});
