import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/paged_response.dart';
import '../../core/providers.dart';
import 'support_models.dart';

class SupportRepository {
  SupportRepository(this._api);

  final ApiClient _api;

  // Support sits under a versioned prefix, unlike the rest of the API. Not a
  // typo — `/api/v1/support/...` is what the controllers are mapped to.
  static const _tickets = '/v1/support/tickets';
  static const _messages = '/v1/support/messages';

  // ── Tickets this user raised to BusinessOS ──────────────────

  Future<PagedResponse<SupportTicket>> myTickets({
    int page = 0,
    int size = 20,
  }) =>
      _api.getPaged(
        '$_tickets/my-tickets',
        SupportTicket.fromJson,
        page: page,
        size: size,
      );

  Future<SupportTicket> byId(int id) async {
    final json = await _api.get<Map<String, dynamic>>('$_tickets/$id');
    return SupportTicket.fromJson(json);
  }

  Future<SupportTicket> create(CreateTicketRequest request) async {
    final json =
        await _api.post<Map<String, dynamic>>(_tickets, request.toJson());
    return SupportTicket.fromJson(json);
  }

  // ── This company's own clients' tickets ─────────────────────

  /// The staff-side "Client Chat" inbox. A different endpoint from
  /// [myTickets], not a filter on it: the backend splits the two by
  /// `ticketType`, so asking the wrong one returns the wrong conversation
  /// entirely rather than an empty list.
  Future<PagedResponse<SupportTicket>> clientTickets({
    int page = 0,
    int size = 20,
  }) =>
      _api.getPaged(
        '$_tickets/company/client-tickets',
        SupportTicket.fromJson,
        page: page,
        size: size,
      );

  // ── Messages ────────────────────────────────────────────────

  /// The full thread on a ticket, as far as this user is permitted to see it.
  Future<List<SupportMessage>> messages(int ticketId) async {
    final page = await _api.getPaged(
      '$_messages/ticket/$ticketId',
      SupportMessage.fromJson,
      page: 0,
      size: 100,
    );
    return _oldestFirst(page.content);
  }

  /// Only the messages the client can also see.
  ///
  /// Deliberately the external-only endpoint. A staff member replying from a
  /// phone is having the conversation the client is reading, and showing
  /// internal notes in that same thread is how a private remark gets answered
  /// as though the client had seen it. Internal notes remain a web feature.
  Future<List<SupportMessage>> clientChatMessages(int ticketId) async {
    final list =
        await _api.get<List<dynamic>>('$_messages/ticket/$ticketId/external');
    return _oldestFirst(
      list.whereType<Map<String, dynamic>>().map(SupportMessage.fromJson).toList(),
    );
  }

  /// Posts a reply.
  ///
  /// `isInternal` is sent explicitly rather than left to the backend's default
  /// because the two callers want opposite things and a silent default would
  /// eventually pick the wrong one.
  Future<SupportMessage> reply({
    required int ticketId,
    required String message,
    required bool internal,
  }) async {
    final json = await _api.post<Map<String, dynamic>>(_messages, {
      'ticketId': ticketId,
      'message': message.trim(),
      'isInternal': internal,
    });
    return SupportMessage.fromJson(json);
  }

  // ── Agent actions ───────────────────────────────────────────
  // These take their arguments as query parameters, not a JSON body — the
  // controllers declare @RequestParam. Sending a body instead silently does
  // nothing, so the encoding here matters.

  Future<void> resolve(int id, String notes) => _api.post<dynamic>(
        '$_tickets/$id/resolve?notes=${Uri.encodeQueryComponent(notes.trim())}',
      );

  Future<void> close(int id) => _api.post<dynamic>('$_tickets/$id/close');

  Future<void> reopen(int id, String reason) => _api.post<dynamic>(
        '$_tickets/$id/reopen?reason=${Uri.encodeQueryComponent(reason.trim())}',
      );

  static List<SupportMessage> _oldestFirst(List<SupportMessage> messages) {
    // A conversation reads top to bottom; the newest message is where the
    // reader is heading, which is also where the composer sits.
    final sorted = [...messages]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return sorted;
  }
}

final supportRepositoryProvider = Provider<SupportRepository>(
  (ref) => SupportRepository(ref.watch(apiClientProvider)),
);
