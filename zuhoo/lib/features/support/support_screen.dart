import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/permission_controller.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/widgets/paged_list_view.dart';
import '../../shared/widgets/primitives.dart';
import 'new_ticket_sheet.dart';
import 'support_controllers.dart';
import 'support_models.dart';
import 'ticket_card.dart';
import 'ticket_detail_screen.dart';

class SupportScreen extends ConsumerWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final permissions = ref.watch(permissionControllerProvider);

    // "Not confirmed yet" is not "denied" — see PermissionState.loaded.
    if (!permissions.loaded && permissions.codes.isEmpty) {
      return Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(title: const Text('Support')),
        body: const Loader(),
      );
    }

    // Client Chat is the staff inbox for this company's own clients. Anyone
    // may raise their own ticket to BusinessOS, so the first tab needs no
    // permission at all — which is why the whole screen is not gated.
    final canSeeClientChat =
        permissions.has(SupportPermissions.messageView);

    final tabs = <({String label, Widget view})>[
      (label: 'My tickets', view: const _MyTicketsTab()),
      if (canSeeClientChat)
        (label: 'Client chat', view: const _ClientChatTab()),
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(
          title: const Text('Support'),
          bottom: tabs.length > 1
              ? TabBar(tabs: [for (final tab in tabs) Tab(text: tab.label)])
              : null,
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => showNewTicketSheet(context),
          backgroundColor: bos.brand,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add_rounded),
          label: const Text('New'),
        ),
        body: tabs.length > 1
            ? TabBarView(children: [for (final tab in tabs) tab.view])
            : tabs.first.view,
      ),
    );
  }
}

class _MyTicketsTab extends ConsumerWidget {
  const _MyTicketsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(myTicketsProvider.notifier);

    return PagedListView<SupportTicket>(
      async: ref.watch(myTicketsProvider),
      onRefresh: controller.refresh,
      onLoadMore: () => guardListAction(context, controller.loadMore),
      emptyIcon: Icons.support_agent_rounded,
      emptyTitle: 'No tickets raised',
      emptyMessage:
          'Anything you report to the Zuhoo team appears here, with its status '
          'and their replies.',
      errorMessage: 'Could not load your tickets.',
      itemBuilder: (context, ticket) => TicketCard(
        ticket: ticket,
        onTap: () => openTicket(context, ticket.id, ThreadKind.platform),
      ),
    );
  }
}

class _ClientChatTab extends ConsumerWidget {
  const _ClientChatTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(clientTicketsProvider.notifier);

    return PagedListView<SupportTicket>(
      async: ref.watch(clientTicketsProvider),
      onRefresh: controller.refresh,
      onLoadMore: () => guardListAction(context, controller.loadMore),
      emptyIcon: Icons.chat_bubble_outline_rounded,
      emptyTitle: 'No client conversations',
      emptyMessage:
          'Tickets your own clients raise through their portal land here.',
      errorMessage: 'Could not load your client conversations.',
      itemBuilder: (context, ticket) => TicketCard(
        ticket: ticket,
        showRaisedBy: true,
        onTap: () => openTicket(context, ticket.id, ThreadKind.clientChat),
      ),
    );
  }
}
