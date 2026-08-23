import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/widgets/primitives.dart';
import '../crm/clients_tab.dart';
import '../crm/lead_detail_screen.dart';
import '../crm/opportunity_detail_screen.dart';
import '../requests/request_detail_screen.dart';
import 'search_models.dart';
import 'search_repository.dart';

/// Find anything, from one box.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Debounced: this query fans out to seven repositories server-side, so
  /// firing one per keystroke is expensive at the far end, not just here.
  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      ref.read(searchQueryProvider.notifier).set(value);
    });
  }

  void _openHit(SearchHit hit) {
    switch (hit.type) {
      case 'LEAD':
        openLead(context, hit.id);
      case 'OPPORTUNITY':
        openOpportunity(context, hit.id);
      case 'SERVICE_REQUEST':
        openRequestDetail(context, hit.id);
      case 'CLIENT':
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ClientDetailScreen(id: hit.id),
          ),
        );
      case 'TICKET':
        // The result does not say whether this is a platform ticket or a
        // client one, and the two open different conversations. Landing on the
        // support module is honest; guessing would open the wrong thread.
        context.push(Routes.support);
      case 'INVOICE':
      case 'REFUND':
        context.push(Routes.finance);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final query = ref.watch(searchQueryProvider);
    final async = ref.watch(searchResultsProvider);

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(title: const Text('Search')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: _onChanged,
              onSubmitted: (value) {
                _debounce?.cancel();
                ref.read(searchQueryProvider.notifier).set(value);
              },
              decoration: InputDecoration(
                hintText: 'Leads, clients, tickets, invoices…',
                prefixIcon:
                    Icon(Icons.search_rounded, size: 20, color: bos.muted),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        icon: Icon(Icons.close_rounded,
                            size: 18, color: bos.muted),
                        onPressed: () {
                          _controller.clear();
                          _debounce?.cancel();
                          ref.read(searchQueryProvider.notifier).set('');
                          setState(() {});
                        },
                        tooltip: 'Clear',
                      ),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: Builder(
              builder: (context) {
                if (query.length < 2) {
                  return const EmptyState(
                    icon: Icons.search_rounded,
                    title: 'Search everything',
                    message:
                        'Type at least two characters. Only records you have '
                        'permission to open are shown.',
                  );
                }
                return async.when(
                  loading: () => const Loader(),
                  error: (error, _) => ErrorState(
                    message: error is ApiException
                        ? error.message
                        : 'Search failed. Try again.',
                    onRetry: () => ref.invalidate(searchResultsProvider),
                  ),
                  data: (results) {
                    if (results == null) return const SizedBox.shrink();
                    if (results.hits.isEmpty) {
                      return EmptyState(
                        icon: Icons.search_off_rounded,
                        title: 'Nothing found',
                        message: results.totalMatches > 0
                            // The server matched things this reader may not
                            // see. Saying so beats "nothing found", which
                            // would be untrue.
                            ? 'Nothing you have access to matches '
                                '“${results.query}”.'
                            : 'No record matches “${results.query}”.',
                      );
                    }
                    return _Results(
                      results: results,
                      onTap: _openHit,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({required this.results, required this.onTap});

  final SearchResults results;
  final void Function(SearchHit hit) onTap;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    // Grouped by kind, in the order the server returns them, so leads stay
    // together rather than interleaving with invoices.
    final grouped = <String, List<SearchHit>>{};
    for (final hit in results.hits) {
      grouped.putIfAbsent(hit.type, () => []).add(hit);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        for (final entry in grouped.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 10, 2, 8),
            child: Row(
              children: [
                Icon(
                  SearchKind.of(entry.key).icon,
                  size: 15,
                  color: bos.muted,
                ),
                const SizedBox(width: 7),
                Text(
                  '${SearchKind.of(entry.key).label}'
                  '${entry.value.length > 1 ? 's' : ''}',
                  style: TextStyle(
                    color: bos.muted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${entry.value.length}',
                  style: TextStyle(color: bos.muted, fontSize: 11.5),
                ),
              ],
            ),
          ),
          for (final hit in entry.value)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => onTap(hit),
                child: AppCard(
                  padding: const EdgeInsets.all(13),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              hit.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: bos.text,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (hit.subtitle?.trim().isNotEmpty == true)
                              Text(
                                hit.subtitle!.trim(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: bos.textSecondary,
                                  fontSize: 12.5,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 19,
                        color: bos.muted,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }
}
