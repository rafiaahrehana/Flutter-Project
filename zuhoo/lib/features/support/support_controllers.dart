import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/paged_response.dart';
import '../../shared/paged_controller.dart';
import 'support_models.dart';
import 'support_repository.dart';

/// Tickets this user raised to BusinessOS.
class MyTicketsController extends AsyncNotifier<PagedState<SupportTicket>>
    with PagedLoader<SupportTicket> {
  @override
  Future<PagedState<SupportTicket>> build() {
    ref.watch(currentUserProvider);
    return loadFirstPage();
  }

  @override
  Future<PagedResponse<SupportTicket>> fetchPage(int page) =>
      ref.read(supportRepositoryProvider).myTickets(page: page);

  /// Raises a ticket, then reloads. The backend assigns the ticket number, the
  /// SLA deadlines and the starting status, so the new row is read back rather
  /// than assembled from the form.
  Future<SupportTicket> create(CreateTicketRequest request) async {
    final created = await ref.read(supportRepositoryProvider).create(request);
    await refresh();
    return created;
  }
}

final myTicketsProvider =
    AsyncNotifierProvider<MyTicketsController, PagedState<SupportTicket>>(
  MyTicketsController.new,
);

/// The staff inbox of this company's own clients' tickets.
class ClientTicketsController extends AsyncNotifier<PagedState<SupportTicket>>
    with PagedLoader<SupportTicket> {
  @override
  Future<PagedState<SupportTicket>> build() {
    ref.watch(currentUserProvider);
    return loadFirstPage();
  }

  @override
  Future<PagedResponse<SupportTicket>> fetchPage(int page) =>
      ref.read(supportRepositoryProvider).clientTickets(page: page);
}

final clientTicketsProvider =
    AsyncNotifierProvider<ClientTicketsController, PagedState<SupportTicket>>(
  ClientTicketsController.new,
);

/// One ticket. Auto-disposed: status, assignee and SLA state all move while
/// you are not looking at it, so re-reading on open is the right default.
final ticketDetailProvider =
    FutureProvider.autoDispose.family<SupportTicket, int>(
  (ref, id) => ref.watch(supportRepositoryProvider).byId(id),
);

/// Which side of a conversation this thread is.
///
/// It selects the endpoint, and the two are not interchangeable: the client
/// thread is external-only, the platform thread is everything this user may
/// see. Passing the wrong one either hides half the conversation or shows a
/// client's counterpart an internal note.
enum ThreadKind { platform, clientChat }

typedef ThreadKey = ({int ticketId, ThreadKind kind});

final ticketMessagesProvider =
    FutureProvider.autoDispose.family<List<SupportMessage>, ThreadKey>(
  (ref, key) {
    final repo = ref.watch(supportRepositoryProvider);
    return switch (key.kind) {
      ThreadKind.platform => repo.messages(key.ticketId),
      ThreadKind.clientChat => repo.clientChatMessages(key.ticketId),
    };
  },
);
