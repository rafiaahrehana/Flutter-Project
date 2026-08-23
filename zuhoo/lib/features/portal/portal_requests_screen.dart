import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/bos_tokens.dart';
import '../../shared/widgets/paged_list_view.dart';
import '../requests/raise_request_sheet.dart';
import '../requests/request_card.dart';
import '../requests/request_controllers.dart';
import '../requests/request_detail_screen.dart';
import '../requests/request_models.dart';

/// The client's own service requests.
///
/// Backed by `/service-requests/my`, which resolves a Client row from the
/// caller — the endpoint that 400s for staff. Here it is exactly right, which
/// is why it lives in the portal shell and not the staff one.
///
/// The card, the detail screen and the raise sheet are the same widgets the
/// staff module uses: the backend already returns a client-shaped view of a
/// request, so a second set of near-identical screens would only be somewhere
/// for the two to drift apart.
class PortalRequestsScreen extends ConsumerWidget {
  const PortalRequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final controller = ref.read(myRequestsProvider.notifier);

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(title: const Text('My requests')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showRaiseRequestSheet(context),
        backgroundColor: bos.brand,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Request'),
      ),
      body: PagedListView<ServiceRequest>(
        async: ref.watch(myRequestsProvider),
        onRefresh: controller.refresh,
        onLoadMore: () => guardListAction(context, controller.loadMore),
        emptyIcon: Icons.assignment_outlined,
        emptyTitle: 'Nothing requested yet',
        emptyMessage:
            'Pick a service and ask for it — you can follow its progress here.',
        errorMessage: 'Could not load your requests.',
        itemBuilder: (context, request) => RequestCard(
          request: request,
          onTap: () => openRequestDetail(context, request.id),
        ),
      ),
    );
  }
}
