import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/paged_response.dart';
import '../../core/providers.dart';
import '../../shared/paged_controller.dart';
import '../support/support_models.dart';
import 'portal_models.dart';

/// Everything the client portal reads.
///
/// All of it is `/me`-scoped: the backend resolves the caller's Client row and
/// answers only for that account. Nothing here takes a client id, which is what
/// keeps one client from asking about another.
class PortalRepository {
  PortalRepository(this._api);

  final ApiClient _api;

  static const _invoices = '/company/finance/invoices';
  static const _receipts = '/company/finance/payment-receipts';
  static const _packages = '/packages';
  static const _tickets = '/v1/support/tickets';

  Future<ClientSummary> summary() async {
    final json = await _api.get<Map<String, dynamic>>('/dashboard/client-summary');
    return ClientSummary.fromJson(json);
  }

  Future<ClientProfile> profile() async {
    final json = await _api.get<Map<String, dynamic>>('/clients/me');
    return ClientProfile.fromJson(json);
  }

  Future<PagedResponse<Invoice>> invoices({int page = 0, int size = 20}) =>
      _api.getPaged('$_invoices/me', Invoice.fromJson, page: page, size: size);

  Future<PagedResponse<PaymentReceipt>> receipts({
    int page = 0,
    int size = 20,
  }) =>
      _api.getPaged(
        '$_receipts/me',
        PaymentReceipt.fromJson,
        page: page,
        size: size,
      );

  /// Downloads an invoice PDF to a temp file and returns its path.
  ///
  /// Temp rather than permanent storage: it is handed straight to the platform
  /// viewer, and an invoice is not something to leave sitting in app storage.
  Future<String> invoicePdf(Invoice invoice) async {
    final bytes = await _api.getBytes('$_invoices/${invoice.id}/pdf');
    final dir = await getTemporaryDirectory();
    final safeNumber =
        invoice.invoiceNumber.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-');
    final file = File('${dir.path}${Platform.pathSeparator}invoice-$safeNumber.pdf');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<PagedResponse<PackageSubscription>> subscriptions({
    int page = 0,
    int size = 20,
  }) =>
      _api.getPaged(
        '$_packages/subscriptions/my',
        PackageSubscription.fromJson,
        page: page,
        size: size,
      );

  /// The client's own support tickets — raised by them, to this company.
  ///
  /// A different endpoint from the staff-facing lists: `/client/my` resolves
  /// the caller's Client row, where `/my-tickets` resolves a staff user. Same
  /// table, opposite audiences.
  Future<PagedResponse<SupportTicket>> tickets({
    int page = 0,
    int size = 20,
  }) =>
      _api.getPaged(
        '$_tickets/client/my',
        SupportTicket.fromJson,
        page: page,
        size: size,
      );

  /// Messages on one of the client's tickets. External only by construction —
  /// this endpoint never returns staff-internal notes.
  Future<List<SupportMessage>> ticketMessages(int ticketId) async {
    final list =
        await _api.get<List<dynamic>>('/v1/support/messages/client/ticket/$ticketId');
    final messages = list
        .whereType<Map<String, dynamic>>()
        .map(SupportMessage.fromJson)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return messages;
  }

  /// Posts a client reply. The backend forces `isInternal` false here, so a
  /// client cannot accidentally write a note only staff would see.
  Future<SupportMessage> replyToTicket(int ticketId, String message) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/v1/support/messages/client',
      {'ticketId': ticketId, 'message': message.trim()},
    );
    return SupportMessage.fromJson(json);
  }

  Future<SupportTicket> raiseTicket(CreateTicketRequest request) async {
    final json =
        await _api.post<Map<String, dynamic>>('$_tickets/client', request.toJson());
    return SupportTicket.fromJson(json);
  }
}

final portalRepositoryProvider = Provider<PortalRepository>(
  (ref) => PortalRepository(ref.watch(apiClientProvider)),
);

final clientSummaryProvider = FutureProvider<ClientSummary>((ref) {
  ref.watch(currentUserProvider);
  return ref.watch(portalRepositoryProvider).summary();
});

final clientProfileProvider = FutureProvider<ClientProfile>((ref) {
  ref.watch(currentUserProvider);
  return ref.watch(portalRepositoryProvider).profile();
});

/// Subscriptions are optional: a client who buys services one at a time has
/// none, and that is not an error worth a panel.
final clientSubscriptionsProvider =
    FutureProvider<List<PackageSubscription>>((ref) async {
  ref.watch(currentUserProvider);
  try {
    final page = await ref.watch(portalRepositoryProvider).subscriptions();
    return page.content;
  } on ApiException {
    return const [];
  }
});

class ClientInvoicesController extends AsyncNotifier<PagedState<Invoice>>
    with PagedLoader<Invoice> {
  @override
  Future<PagedState<Invoice>> build() {
    ref.watch(currentUserProvider);
    return loadFirstPage();
  }

  @override
  Future<PagedResponse<Invoice>> fetchPage(int page) =>
      ref.read(portalRepositoryProvider).invoices(page: page);
}

final clientInvoicesProvider =
    AsyncNotifierProvider<ClientInvoicesController, PagedState<Invoice>>(
  ClientInvoicesController.new,
);

class ClientReceiptsController extends AsyncNotifier<PagedState<PaymentReceipt>>
    with PagedLoader<PaymentReceipt> {
  @override
  Future<PagedState<PaymentReceipt>> build() {
    ref.watch(currentUserProvider);
    return loadFirstPage();
  }

  @override
  Future<PagedResponse<PaymentReceipt>> fetchPage(int page) =>
      ref.read(portalRepositoryProvider).receipts(page: page);
}

final clientReceiptsProvider =
    AsyncNotifierProvider<ClientReceiptsController, PagedState<PaymentReceipt>>(
  ClientReceiptsController.new,
);

class ClientTicketsController extends AsyncNotifier<PagedState<SupportTicket>>
    with PagedLoader<SupportTicket> {
  @override
  Future<PagedState<SupportTicket>> build() {
    ref.watch(currentUserProvider);
    return loadFirstPage();
  }

  @override
  Future<PagedResponse<SupportTicket>> fetchPage(int page) =>
      ref.read(portalRepositoryProvider).tickets(page: page);

  Future<SupportTicket> raise(CreateTicketRequest request) async {
    final created = await ref.read(portalRepositoryProvider).raiseTicket(request);
    await refresh();
    return created;
  }
}

final clientTicketsProvider =
    AsyncNotifierProvider<ClientTicketsController, PagedState<SupportTicket>>(
  ClientTicketsController.new,
);

final clientTicketMessagesProvider =
    FutureProvider.autoDispose.family<List<SupportMessage>, int>(
  (ref, id) => ref.watch(portalRepositoryProvider).ticketMessages(id),
);
