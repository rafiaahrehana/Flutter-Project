import 'package:flutter_test/flutter_test.dart';
import 'package:zuhoo/features/support/support_models.dart';

/// Support has two ticket types running in opposite directions through one
/// table, and several flags that decide what the UI offers. Getting one of
/// these backwards produces no error — just an action that is missing, or a
/// private note that looks public.
void main() {
  SupportTicket build({
    String status = TicketStatus.open,
    bool slaBreached = false,
    int escalationLevel = 0,
    String? assignedToAgentName,
    String? assignedEmployeeName,
  }) =>
      SupportTicket(
        id: 1,
        ticketNumber: 'TKT-0001',
        title: 'Cannot generate payslips',
        status: status,
        priority: 'HIGH',
        createdAt: '2026-08-01T10:00:00',
        slaBreached: slaBreached,
        escalationLevel: escalationLevel,
        assignedToAgentName: assignedToAgentName,
        assignedEmployeeName: assignedEmployeeName,
      );

  group('SupportTicket', () {
    test('open means anything not resolved or closed', () {
      expect(build(status: TicketStatus.isNew).isOpen, isTrue);
      expect(build(status: TicketStatus.inProgress).isOpen, isTrue);
      expect(build(status: TicketStatus.waiting).isOpen, isTrue);
      expect(build(status: TicketStatus.onHold).isOpen, isTrue);
      expect(build(status: TicketStatus.resolved).isOpen, isFalse);
      expect(build(status: TicketStatus.closed).isOpen, isFalse);
    });

    test('an unknown status counts as open', () {
      // The composer and the agent actions key off this. Treating an
      // unrecognised status as settled would silently lock a live conversation.
      expect(build(status: 'PENDING_VENDOR').isOpen, isTrue);
    });

    test('resolved and closed are distinguished, not lumped together', () {
      // They offer different actions: a resolved ticket can still be closed,
      // a closed one can only be reopened.
      final resolved = build(status: TicketStatus.resolved);
      expect(resolved.isResolved, isTrue);
      expect(resolved.isClosed, isFalse);

      final closed = build(status: TicketStatus.closed);
      expect(closed.isClosed, isTrue);
      expect(closed.isResolved, isFalse);
    });

    test('escalation is only flagged above level zero', () {
      expect(build().isEscalated, isFalse);
      expect(build(escalationLevel: 1).isEscalated, isTrue);
    });

    test('a handler from either field counts as assigned', () {
      // The backend fills one or the other depending on whether a support
      // agent or an ordinary employee picked it up; reading only one would
      // show half the worked tickets as unassigned.
      expect(build().isUnassigned, isTrue);
      expect(build().handlerName, isNull);

      expect(build(assignedToAgentName: 'Rehana').isUnassigned, isFalse);
      expect(build(assignedToAgentName: 'Rehana').handlerName, 'Rehana');

      expect(build(assignedEmployeeName: 'Tanvir').isUnassigned, isFalse);
      expect(build(assignedEmployeeName: 'Tanvir').handlerName, 'Tanvir');
    });

    test('parses what the cards and detail screen read', () {
      final ticket = SupportTicket.fromJson(const {
        'id': 9,
        'ticketNumber': 'TKT-0009',
        'title': 'Payroll run failed',
        'status': 'IN_PROGRESS',
        'priority': 'CRITICAL',
        'createdAt': '2026-08-01T10:00:00',
        'ticketType': 'CUSTOMER_SUPPORT',
        'slaBreached': true,
        'escalationLevel': 2,
        'createdByName': 'Client Co',
        'satisfactionRating': 4,
      });

      expect(ticket.ticketNumber, 'TKT-0009');
      expect(ticket.ticketType, TicketType.customer);
      expect(ticket.slaBreached, isTrue);
      expect(ticket.isEscalated, isTrue);
      expect(ticket.satisfactionRating, 4);
    });

    test('survives a response missing everything optional', () {
      final ticket = SupportTicket.fromJson(const {});
      expect(ticket.id, 0);
      expect(ticket.status, TicketStatus.isNew);
      expect(ticket.slaBreached, isFalse);
      expect(ticket.escalationLevel, 0);
      expect(ticket.isOpen, isTrue);
    });
  });

  group('SupportMessage', () {
    test('defaults to external when the flag is absent', () {
      // The safe direction: a message wrongly treated as internal merely gets
      // an extra label, whereas the reverse hides that it was private.
      expect(SupportMessage.fromJson(const {'id': 1}).isInternal, isFalse);
      expect(
        SupportMessage.fromJson(const {'id': 1, 'isInternal': true}).isInternal,
        isTrue,
      );
    });

    test('knows whether it carries an attachment', () {
      expect(SupportMessage.fromJson(const {'id': 1}).hasAttachment, isFalse);
      expect(
        SupportMessage.fromJson(const {'id': 1, 'attachmentUrl': ''})
            .hasAttachment,
        isFalse,
        reason: 'an empty string is not an attachment',
      );
      expect(
        SupportMessage.fromJson(const {'id': 1, 'attachmentUrl': '/files/a.pdf'})
            .hasAttachment,
        isTrue,
      );
    });
  });

  group('CreateTicketRequest', () {
    test('trims and defaults priority', () {
      final json = const CreateTicketRequest(
        title: '  Payroll fails  ',
        description: '  It errors on save  ',
      ).toJson();

      expect(json['title'], 'Payroll fails');
      expect(json['description'], 'It errors on save');
      expect(json['priority'], 'MEDIUM');
      expect(json.containsKey('categoryId'), isFalse);
    });
  });

  group('priorities', () {
    test('support uses its own scale, not the service-request one', () {
      // MEDIUM/CRITICAL here vs NORMAL/URGENT there. Sharing one list would
      // send a value the backend enum does not contain.
      expect(ticketPriorities, contains('MEDIUM'));
      expect(ticketPriorities, contains('CRITICAL'));
      expect(ticketPriorities, isNot(contains('NORMAL')));
      expect(ticketPriorities, isNot(contains('URGENT')));
    });
  });
}
