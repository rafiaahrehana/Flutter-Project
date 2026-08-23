import 'package:flutter_test/flutter_test.dart';
import 'package:zuhoo/core/auth/permission_controller.dart';
import 'package:zuhoo/features/search/search_models.dart';

/// Global search returns seven kinds of record from one query and applies
/// **no permission check** server-side — `GlobalSearchServiceImpl` filters by
/// company and nothing else. So the raw response carries invoice totals,
/// refund amounts and deal values to anybody who can call it.
///
/// The client is what decides which of those a reader may see, which makes
/// this mapping load-bearing rather than cosmetic.
void main() {
  /// Mirrors the filter in `searchResultsProvider`.
  List<SearchHit> visible(List<SearchHit> hits, PermissionState permissions) =>
      hits
          .where((hit) =>
              SearchKind.isKnown(hit.type) &&
              permissions.has(SearchKind.of(hit.type).permission))
          .toList();

  PermissionState holding(List<String> codes) =>
      PermissionState(codes: codes.toSet(), catalog: const {}, loaded: true);

  SearchHit hit(String type) =>
      SearchHit(type: type, id: 1, title: 'x', subtitle: 'y');

  group('every kind the server returns is mapped', () {
    // If the backend gains a result type and this list is not updated, the
    // new kind is hidden rather than shown ungated — the safe direction, and
    // the reason the test names them explicitly.
    const serverKinds = [
      'LEAD',
      'CLIENT',
      'OPPORTUNITY',
      'SERVICE_REQUEST',
      'TICKET',
      'INVOICE',
      'REFUND',
    ];

    test('each has a permission and a label', () {
      for (final kind in serverKinds) {
        expect(SearchKind.isKnown(kind), isTrue, reason: kind);
        expect(
          SearchKind.of(kind).permission,
          isNotNull,
          reason: '$kind would otherwise be shown to everyone',
        );
        expect(SearchKind.of(kind).label, isNotEmpty, reason: kind);
      }
    });

    test('financial kinds sit behind the invoice permission', () {
      expect(SearchKind.of('INVOICE').permission, 'INVOICE_VIEW');
      expect(
        SearchKind.of('REFUND').permission,
        'INVOICE_VIEW',
        reason: 'refund subtitles carry the amount, same as invoices',
      );
    });
  });

  group('filtering', () {
    test('hides what the reader cannot open', () {
      final hits = [
        hit('LEAD'),
        hit('INVOICE'),
        hit('TICKET'),
      ];

      final shown = visible(hits, holding(['LEAD_VIEW', 'TICKET_VIEW']));

      expect(shown.map((h) => h.type), ['LEAD', 'TICKET']);
    });

    test('an employee without INVOICE_VIEW never sees a total', () {
      // The subtitle is where the amount lives — "PAID · 4500.00". Dropping
      // the whole hit is what keeps it off the screen.
      final hits = [
        const SearchHit(
          type: 'INVOICE',
          id: 1,
          title: 'INV-0042',
          subtitle: 'PAID · 4500.00',
        ),
      ];

      expect(visible(hits, holding(['LEAD_VIEW'])), isEmpty);
    });

    test('an unrecognised kind is hidden, not shown ungated', () {
      expect(visible([hit('PAYSLIP')], holding(['PAYROLL_VIEW'])), isEmpty);
      expect(
        visible([hit('PAYSLIP')], holding([])),
        isEmpty,
        reason: 'a kind with no mapping cannot be gated, so it is not shown',
      );
    });

    test('holding everything shows everything known', () {
      final hits = [
        hit('LEAD'),
        hit('CLIENT'),
        hit('OPPORTUNITY'),
        hit('SERVICE_REQUEST'),
        hit('TICKET'),
        hit('INVOICE'),
        hit('REFUND'),
      ];

      final all = holding([
        'LEAD_VIEW',
        'CLIENT_VIEW',
        'OPPORTUNITY_VIEW',
        'SERVICE_REQUEST_VIEW',
        'TICKET_VIEW',
        'INVOICE_VIEW',
      ]);

      expect(visible(hits, all), hasLength(7));
    });
  });

  group('parsing', () {
    test('reads the response the controller sends', () {
      final results = SearchResults.fromJson(const {
        'query': 'acme',
        'totalMatches': 12,
        'results': [
          {
            'type': 'CLIENT',
            'id': 3,
            'title': 'Acme Ltd',
            'subtitle': 'Manufacturing',
            'link': '/crm/clients/3',
          },
        ],
      });

      expect(results.query, 'acme');
      expect(results.totalMatches, 12);
      expect(results.hits.single.title, 'Acme Ltd');
      expect(results.hits.single.id, 3);
    });

    test('survives an empty or malformed result list', () {
      expect(SearchResults.fromJson(const {}).hits, isEmpty);
      expect(SearchResults.fromJson(const {'results': null}).hits, isEmpty);
      expect(
        SearchResults.fromJson(const {'results': ['nonsense', 42]}).hits,
        isEmpty,
        reason: 'non-object entries are skipped rather than crashing the list',
      );
    });

    test('totalMatches is the server count, not what is shown', () {
      // Kept deliberately: it is how the screen can say "nothing you have
      // access to matches" instead of the untrue "nothing found".
      final results = SearchResults.fromJson(const {
        'query': 'x',
        'totalMatches': 9,
        'results': [],
      });

      expect(results.totalMatches, 9);
      expect(results.hits, isEmpty);
    });
  });
}
