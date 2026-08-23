import 'package:flutter_test/flutter_test.dart';
import 'package:zuhoo/core/auth/auth_models.dart';
import 'package:zuhoo/features/portal/portal_models.dart';

/// The portal shows a client their own money and their own jobs, so the two
/// ways to be wrong are both bad: telling someone they owe nothing when they
/// do, and telling them a paid bill is overdue.
void main() {
  Invoice invoice({
    String status = InvoiceStatus.issued,
    double total = 1000,
    double paid = 0,
    double balance = 1000,
    String? dueDate,
  }) =>
      Invoice(
        id: 1,
        invoiceNumber: 'INV-0001',
        status: status,
        subtotal: total,
        taxAmount: 0,
        totalAmount: total,
        paidAmount: paid,
        balanceAmount: balance,
        dueDate: dueDate,
      );

  String iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  final past = iso(DateTime.now().subtract(const Duration(days: 5)));
  final future = iso(DateTime.now().add(const Duration(days: 5)));

  group('Invoice', () {
    test('overdue is derived, not just read off the status', () {
      // A bill can be past due before any nightly job relabels it, and the
      // person who owes the money should see that immediately.
      expect(invoice(dueDate: past).isOverdue, isTrue);
      expect(invoice(dueDate: future).isOverdue, isFalse);
      expect(invoice().isOverdue, isFalse, reason: 'no due date, nothing to miss');
    });

    test('a settled invoice is never overdue', () {
      // The opposite failure: chasing someone for money they have already paid.
      expect(invoice(status: InvoiceStatus.paid, balance: 0, dueDate: past).isOverdue,
          isFalse);
      expect(
        invoice(status: InvoiceStatus.cancelled, balance: 0, dueDate: past).isOverdue,
        isFalse,
      );
    });

    test('a zero balance is not overdue even if the status lags', () {
      expect(
        invoice(status: InvoiceStatus.overdue, balance: 0, dueDate: past).isOverdue,
        isFalse,
      );
    });

    test('the status alone can mark it overdue', () {
      // The server may know something the due date does not show.
      expect(invoice(status: InvoiceStatus.overdue).isOverdue, isTrue);
    });

    test('part-paid needs money both paid and still owing', () {
      expect(invoice(paid: 400, balance: 600).isPartlyPaid, isTrue);
      expect(invoice(paid: 0, balance: 1000).isPartlyPaid, isFalse);
      expect(invoice(paid: 1000, balance: 0).isPartlyPaid, isFalse);
    });

    test('parses amounts sent as ints', () {
      final parsed = Invoice.fromJson(const {
        'id': 2,
        'invoiceNumber': 'INV-0002',
        'status': 'SENT',
        'subtotal': 1000,
        'taxAmount': 150,
        'totalAmount': 1150,
        'paidAmount': 0,
        'balanceAmount': 1150,
      });
      expect(parsed.totalAmount, 1150.0);
      expect(parsed.balanceAmount, 1150.0);
    });
  });

  group('InvoiceStatus', () {
    test('matches the backend enum exactly', () {
      // The status filter is a path segment, so a value the Java enum cannot
      // parse comes back as a 500 rather than an empty page. There is no
      // 'SENT' — an issued invoice is ISSUED.
      expect(InvoiceStatus.all, [
        'DRAFT',
        'ISSUED',
        'PARTIALLY_PAID',
        'PAID',
        'OVERDUE',
        'CANCELLED',
        'VOIDED',
        'REFUNDED',
      ]);
      expect(InvoiceStatus.all, isNot(contains('SENT')));
    });

    test('settled covers every way an invoice stops being collectable', () {
      expect(InvoiceStatus.settled, contains('PAID'));
      expect(InvoiceStatus.settled, contains('CANCELLED'));
      expect(InvoiceStatus.settled, contains('VOIDED'));
      expect(InvoiceStatus.settled, contains('REFUNDED'));
      expect(InvoiceStatus.settled, isNot(contains('OVERDUE')));
    });
  });

  group('ClientSummary', () {
    test('open requests are pending plus in progress', () {
      const summary = ClientSummary(
        pendingRequests: 2,
        inProgressRequests: 3,
        completedRequests: 9,
        unpaidInvoices: 1,
        outstandingInvoiceAmount: 5000,
      );
      expect(summary.openRequests, 5);
      expect(summary.owesMoney, isTrue);
    });

    test('nothing owed when there are no unpaid invoices', () {
      expect(const ClientSummary().owesMoney, isFalse);
    });
  });

  group('PackageSubscription', () {
    PackageSubscription plan({int? quota, int used = 0}) => PackageSubscription(
          id: 1,
          packageId: 1,
          status: 'ACTIVE',
          requestsUsed: used,
          remainingRequests: (quota ?? 0) - used,
          autoRenew: true,
          createdAt: '2026-01-01T00:00:00',
          requestQuota: quota,
        );

    test('an unmetered plan has no usage fraction', () {
      // A bar at 0% would imply a limit that does not exist.
      expect(plan().quotaUsedFraction, isNull);
      expect(plan(quota: 0).quotaUsedFraction, isNull);
    });

    test('usage is clamped so a stale count cannot overflow the bar', () {
      expect(plan(quota: 10, used: 3).quotaUsedFraction, 0.3);
      expect(plan(quota: 10, used: 25).quotaUsedFraction, 1.0);
    });
  });

  group('ClientProfile', () {
    test('the company is the headline, the person the fallback', () {
      const withCompany = ClientProfile(
        id: 1,
        status: 'ACTIVE',
        firstName: 'Rehana',
        lastName: 'Akter',
        clientCompanyName: 'Dhrubotara Ltd',
      );
      expect(withCompany.headline, 'Dhrubotara Ltd');
      expect(withCompany.contactName, 'Rehana Akter');
      expect(withCompany.initials, 'DL');

      const personOnly = ClientProfile(
        id: 1,
        status: 'ACTIVE',
        firstName: 'Rehana',
        lastName: 'Akter',
      );
      expect(personOnly.headline, 'Rehana Akter');
    });

    test('falls back to the email when there is no name at all', () {
      const bare = ClientProfile(id: 1, status: 'ACTIVE', email: 'a@b.c');
      expect(bare.headline, 'a@b.c');
    });
  });

  group('role routing', () {
    AppUser user(String role) => AppUser(
          id: 1,
          email: 'a@b.c',
          fullName: 'A B',
          roles: [role],
        );

    test('only CLIENT gets the portal', () {
      // The rule the router turns into a redirect. Inverting it would put a
      // client on the attendance tab and an employee on client-scoped
      // endpoints that 400 for them.
      expect(user('CLIENT').isClient, isTrue);
      expect(user('EMPLOYEE').isClient, isFalse);
      expect(user('COMPANY_OWNER').isClient, isFalse);
      expect(user('SUPPORT_AGENT').isClient, isFalse);
    });

    test('platform staff are staff, not clients', () {
      expect(user('SUPER_ADMIN').isPlatformStaff, isTrue);
      expect(user('SUPER_ADMIN').isClient, isFalse);
      expect(user('EMPLOYEE').isPlatformStaff, isFalse);
    });
  });
}
