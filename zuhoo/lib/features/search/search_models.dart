import 'package:flutter/material.dart';

/// One thing the search found.
///
/// The backend returns seven kinds from one query — leads, clients,
/// opportunities, service requests, tickets, invoices and refunds — as a flat
/// list distinguished only by [type].
class SearchHit {
  const SearchHit({
    required this.type,
    required this.id,
    required this.title,
    this.subtitle,
    this.link,
  });

  final String type;
  final int id;
  final String title;
  final String? subtitle;

  /// The Angular route the web app would open. Kept for reference but not
  /// followed — this app has its own routes, and several of these point at a
  /// list rather than the record itself.
  final String? link;

  factory SearchHit.fromJson(Map<String, dynamic> json) => SearchHit(
        type: json['type'] as String? ?? 'UNKNOWN',
        id: (json['id'] as num?)?.toInt() ?? 0,
        title: json['title'] as String? ?? 'Untitled',
        subtitle: json['subtitle'] as String?,
        link: json['link'] as String?,
      );
}

class SearchResults {
  const SearchResults({
    required this.query,
    required this.hits,
    required this.totalMatches,
  });

  final String query;
  final List<SearchHit> hits;

  /// What the server counted before it capped each kind. Larger than
  /// `hits.length` whenever a query matches a lot, and larger again than what
  /// this app shows once permissions have been applied.
  final int totalMatches;

  factory SearchResults.fromJson(Map<String, dynamic> json) => SearchResults(
        query: json['query'] as String? ?? '',
        hits: (json['results'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(SearchHit.fromJson)
                .toList(growable: false) ??
            const [],
        totalMatches: (json['totalMatches'] as num?)?.toInt() ?? 0,
      );
}

/// How each kind is labelled, iconed, and — the important column — which
/// permission governs it.
///
/// `GlobalSearchServiceImpl` performs **no permission check**: it filters by
/// company and nothing else, so the raw response hands an employee without
/// `INVOICE_VIEW` invoice numbers with their totals, and deal values to
/// somebody without `OPPORTUNITY_VIEW`. This app filters the results by the
/// permission that governs each kind before showing them.
///
/// That is not only a privacy decision. A result the reader cannot open is
/// useless anyway: tapping through would 403 at the destination.
class SearchKind {
  const SearchKind({
    required this.label,
    required this.icon,
    required this.permission,
  });

  final String label;
  final IconData icon;

  /// Null means the kind carries no permission of its own.
  final String? permission;

  static const _kinds = <String, SearchKind>{
    'LEAD': SearchKind(
      label: 'Lead',
      icon: Icons.person_search_outlined,
      permission: 'LEAD_VIEW',
    ),
    'CLIENT': SearchKind(
      label: 'Client',
      icon: Icons.business_outlined,
      permission: 'CLIENT_VIEW',
    ),
    'OPPORTUNITY': SearchKind(
      label: 'Opportunity',
      icon: Icons.trending_up_rounded,
      permission: 'OPPORTUNITY_VIEW',
    ),
    'SERVICE_REQUEST': SearchKind(
      label: 'Service request',
      icon: Icons.assignment_outlined,
      permission: 'SERVICE_REQUEST_VIEW',
    ),
    'TICKET': SearchKind(
      label: 'Ticket',
      icon: Icons.support_agent_rounded,
      permission: 'TICKET_VIEW',
    ),
    'INVOICE': SearchKind(
      label: 'Invoice',
      icon: Icons.receipt_long_outlined,
      permission: 'INVOICE_VIEW',
    ),
    // Refunds sit behind the invoice permission, matching the web route.
    'REFUND': SearchKind(
      label: 'Refund',
      icon: Icons.undo_rounded,
      permission: 'INVOICE_VIEW',
    ),
  };

  static SearchKind of(String type) =>
      _kinds[type] ??
      const SearchKind(
        label: 'Result',
        icon: Icons.circle_outlined,
        // An unrecognised kind is one this build does not know how to gate.
        // Requiring nothing would show it; the safe reading is to hide it, so
        // callers treat a null permission as "show" only for known kinds.
        permission: null,
      );

  static bool isKnown(String type) => _kinds.containsKey(type);
}
