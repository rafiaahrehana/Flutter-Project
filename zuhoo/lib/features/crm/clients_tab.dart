import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/paged_list_view.dart';
import '../../shared/widgets/primitives.dart';
import 'crm_controllers.dart';
import 'crm_models.dart';
import 'leads_tab.dart' show TagChip;

class ClientsTab extends ConsumerWidget {
  const ClientsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(clientsProvider.notifier);

    return PagedListView<Client>(
      async: ref.watch(clientsProvider),
      onRefresh: controller.refresh,
      onLoadMore: () => guardListAction(context, controller.loadMore),
      emptyIcon: Icons.business_outlined,
      emptyTitle: 'No clients yet',
      emptyMessage: 'Won deals become clients, and they show up here.',
      errorMessage: 'Could not load your clients.',
      itemBuilder: (context, client) => _ClientCard(
        client: client,
        onTap: () => _openClient(context, client.id),
      ),
    );
  }

  static void _openClient(BuildContext context, int id) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ClientDetailScreen(id: id)),
    );
  }
}

class _ClientCard extends StatelessWidget {
  const _ClientCard({required this.client, this.onTap});

  final Client client;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return AppCard(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Avatar(initials: client.initials, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        client.headline,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: bos.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    StatusChip(client.status, dense: true),
                  ],
                ),
                if (client.subline != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    client.subline!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: bos.muted, fontSize: 12.5),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (client.lifetimeValue != null) ...[
                      Text(
                        Fmt.money(client.lifetimeValue),
                        style: TextStyle(
                          color: bos.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        ' lifetime',
                        style: TextStyle(color: bos.muted, fontSize: 11.5),
                      ),
                      const SizedBox(width: 12),
                    ],
                    if (client.totalRequests != null)
                      Text(
                        '${client.totalRequests} request'
                        '${client.totalRequests == 1 ? '' : 's'}',
                        style: TextStyle(color: bos.muted, fontSize: 11.5),
                      ),
                    const Spacer(),
                    if (client.portalAccessEnabled == true)
                      Icon(Icons.lock_open_rounded, size: 14, color: bos.success),
                  ],
                ),
                if (client.tags.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final tag in client.tags.take(3)) TagChip(tag: tag),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ClientDetailScreen extends ConsumerWidget {
  const ClientDetailScreen({super.key, required this.id});

  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(clientDetailProvider(id));

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(title: const Text('Client')),
      body: async.when(
        loading: () => const Loader(),
        error: (error, _) => ErrorState(
          message: error is ApiException
              ? error.message
              : 'Could not load that client.',
          onRetry: () => ref.invalidate(clientDetailProvider(id)),
        ),
        data: (client) => RefreshIndicator(
          color: bos.brand,
          backgroundColor: bos.bgCard,
          onRefresh: () async => ref.invalidate(clientDetailProvider(id)),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              AppCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    Avatar(initials: client.initials, size: 56),
                    const SizedBox(height: 12),
                    Text(
                      client.headline,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: bos.text,
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                    if (client.subline != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        client.subline!,
                        style: TextStyle(color: bos.muted, fontSize: 13),
                      ),
                    ],
                    const SizedBox(height: 10),
                    StatusChip(client.status),
                    if (client.tags.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        alignment: WrapAlignment.center,
                        children: [
                          for (final tag in client.tags) TagChip(tag: tag),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _ClientFacts(client: client),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClientFacts extends StatelessWidget {
  const _ClientFacts({required this.client});

  final Client client;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    final rows = <({String label, String? value})>[
      (label: 'Email', value: client.email),
      (label: 'Phone', value: client.phone),
      (label: 'Industry', value: client.industry),
      (label: 'Website', value: client.website),
      (label: 'Account manager', value: client.accountManagerName),
      (
        label: 'Employees',
        value: client.employeeCount == null ? null : '${client.employeeCount}'
      ),
      (
        label: 'Annual revenue',
        value:
            client.annualRevenue == null ? null : Fmt.money(client.annualRevenue)
      ),
      (
        label: 'Lifetime value',
        value:
            client.lifetimeValue == null ? null : Fmt.money(client.lifetimeValue)
      ),
      (
        label: 'Requests',
        value: client.totalRequests == null ? null : '${client.totalRequests}'
      ),
      (
        label: 'Portal access',
        value: client.portalAccessEnabled == null
            ? null
            : (client.portalAccessEnabled! ? 'Enabled' : 'Not enabled')
      ),
      (
        label: 'Onboarded',
        value: client.onboardedAt == null ? null : Fmt.date(client.onboardedAt)
      ),
      (label: 'Created', value: Fmt.date(client.createdAt)),
    ].where((row) => row.value != null && row.value!.isNotEmpty).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Account', icon: Icons.business_outlined),
        AppCard(
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) ...[
                  const SizedBox(height: 10),
                  Divider(height: 1, color: bos.borderLight),
                  const SizedBox(height: 10),
                ],
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        rows[i].label,
                        style: TextStyle(color: bos.muted, fontSize: 13),
                      ),
                    ),
                    Flexible(
                      child: Text(
                        rows[i].value!,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: bos.text,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
