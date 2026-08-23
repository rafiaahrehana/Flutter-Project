import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/permission_controller.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/widgets/paged_list_view.dart';
import '../../shared/widgets/primitives.dart';
import 'approvals_tab.dart';
import 'raise_request_sheet.dart';
import 'request_card.dart';
import 'request_controllers.dart';
import 'request_detail_screen.dart';
import 'request_models.dart';

class RequestsScreen extends ConsumerWidget {
  const RequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final permissions = ref.watch(permissionControllerProvider);

    final canView = permissions.has(RequestPermissions.view);
    final canApprove = permissions.has(RequestPermissions.approve);

    // An empty set that has not been confirmed this session is "we do not know
    // yet", not "you may not". Telling someone they lack a permission because
    // the answer has not arrived is worse than making them wait a moment.
    if (!permissions.loaded && permissions.codes.isEmpty) {
      return Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(title: const Text('Requests')),
        body: const Loader(),
      );
    }

    // Gated on the same permission the backend enforces, so the two cannot
    // drift: a user who would be refused by the API never sees the screen that
    // calls it.
    if (!canView) {
      return Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(title: const Text('Requests')),
        body: const EmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Not available to you',
          message:
              'Your role does not include access to service requests. Ask your '
              'administrator if you think it should.',
        ),
      );
    }

    // "Raised by me" is client-only, and deliberately so: the endpoint behind
    // it resolves a Client row from the user id and answers 400 for every staff
    // account. Showing that tab to an employee would put a permanent error on a
    // main tab of a screen that otherwise works.
    final isClient = ref.watch(currentUserProvider)?.isClient ?? false;

    final tabs = <({String label, Widget view})>[
      // Assigned first: for staff — this app's usual reader — it is the list
      // that means "my work".
      (label: 'Assigned', view: const _AssignedTab()),
      if (isClient) (label: 'Raised by me', view: const _MyRequestsTab()),
      if (canApprove) (label: 'Approvals', view: const ApprovalsTab()),
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(
          title: const Text('Requests'),
          bottom: TabBar(
            tabs: [for (final tab in tabs) Tab(text: tab.label)],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => showRaiseRequestSheet(context),
          backgroundColor: bos.brand,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add_rounded),
          label: const Text('New'),
        ),
        body: TabBarView(children: [for (final tab in tabs) tab.view]),
      ),
    );
  }
}

class _MyRequestsTab extends ConsumerWidget {
  const _MyRequestsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(myRequestsProvider.notifier);

    return PagedListView<ServiceRequest>(
      async: ref.watch(myRequestsProvider),
      onRefresh: controller.refresh,
      onLoadMore: () => guardListAction(context, controller.loadMore),
      emptyIcon: Icons.assignment_outlined,
      emptyTitle: 'No requests yet',
      emptyMessage:
          'Anything you raise from the catalogue appears here with its status.',
      errorMessage: 'Could not load your requests.',
      itemBuilder: (context, request) => RequestCard(
        request: request,
        onTap: () => openRequestDetail(context, request.id),
      ),
    );
  }
}

class _AssignedTab extends ConsumerWidget {
  const _AssignedTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(assignedRequestsProvider.notifier);

    return PagedListView<ServiceRequest>(
      async: ref.watch(assignedRequestsProvider),
      onRefresh: controller.refresh,
      onLoadMore: () => guardListAction(context, controller.loadMore),
      emptyIcon: Icons.inbox_outlined,
      emptyTitle: 'Nothing assigned to you',
      emptyMessage: 'Requests routed to you for work will show up here.',
      errorMessage: 'Could not load your assigned work.',
      itemBuilder: (context, request) => RequestCard(
        request: request,
        onTap: () => openRequestDetail(context, request.id),
      ),
    );
  }
}
