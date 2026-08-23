/// Permission codes this module gates on. Each screen asks for the one the
/// backend enforces for its own endpoints, so a user sees exactly the tabs
/// they could actually load.
abstract final class FinancePermissions {
  static const reportView = 'FINANCIAL_REPORT_VIEW';
  static const invoiceView = 'INVOICE_VIEW';
  static const expenseView = 'EXPENSE_VIEW';

  // Deciding a claim is a different entitlement from reading one, and the
  // two decisions are separate again: ExpenseServiceImpl checks
  // EXPENSE_APPROVE to approve and EXPENSE_REJECT to reject. Gating either
  // button on expenseView shows both to every claimant in the company.
  static const expenseApprove = 'EXPENSE_APPROVE';
  static const expenseReject = 'EXPENSE_REJECT';
  static const walletView = 'WALLET_VIEW';
}

abstract final class ExpenseStatus {
  static const pending = 'PENDING';
  static const approved = 'APPROVED';
  static const rejected = 'REJECTED';
  static const paid = 'PAID';
  static const cancelled = 'CANCELLED';

  static const all = [pending, approved, rejected, paid, cancelled];
}

/// Headline figures for one month — GET /finance/dashboard?month&year.
///
/// The wide parts of the web dashboard (budget lines, category breakdown, the
/// twelve-month trend table) are deliberately not modelled: they are
/// multi-column comparisons that a phone cannot show enough of to be useful,
/// and half a comparison is worse than none.
class FinanceOverview {
  const FinanceOverview({
    required this.month,
    required this.year,
    this.totalRevenue = 0,
    this.totalExpenses = 0,
    this.netProfit = 0,
    this.cashCollected = 0,
    this.outstanding = 0,
    this.overdue = 0,
    this.payables = 0,
    this.payablesOverdue = 0,
    this.payrollCost = 0,
    this.revenueChangePercent,
    this.expenseChangePercent,
    this.recentInvoices = const [],
  });

  final int month;
  final int year;
  final double totalRevenue;
  final double totalExpenses;
  final double netProfit;
  final double cashCollected;

  /// Invoiced but not yet collected.
  final double outstanding;

  /// The part of [outstanding] that is late.
  final double overdue;

  final double payables;
  final double payablesOverdue;
  final double payrollCost;

  /// Month-on-month movement. Null on the first month with data — there is
  /// nothing to compare against, and 0% would claim there was.
  final double? revenueChangePercent;
  final double? expenseChangePercent;

  final List<InvoiceLine> recentInvoices;

  bool get isProfitable => netProfit >= 0;

  /// Share of what is owed that has gone past due, or null when nothing is
  /// owed at all — 0% would read as "all healthy" rather than "nothing out".
  double? get overdueShare {
    if (outstanding <= 0) return null;
    return (overdue / outstanding).clamp(0.0, 1.0);
  }

  factory FinanceOverview.fromJson(Map<String, dynamic> json) {
    double d(String key) => (json[key] as num?)?.toDouble() ?? 0;
    final now = DateTime.now();
    return FinanceOverview(
      month: (json['payMonth'] as num?)?.toInt() ?? now.month,
      year: (json['payYear'] as num?)?.toInt() ?? now.year,
      totalRevenue: d('totalRevenue'),
      totalExpenses: d('totalExpenses'),
      netProfit: d('netProfit'),
      cashCollected: d('cashCollected'),
      outstanding: d('outstanding'),
      overdue: d('overdue'),
      payables: d('payables'),
      payablesOverdue: d('payablesOverdue'),
      payrollCost: d('payrollCost'),
      revenueChangePercent: (json['revenueChangePercent'] as num?)?.toDouble(),
      expenseChangePercent: (json['expenseChangePercent'] as num?)?.toDouble(),
      recentInvoices: (json['recentInvoices'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(InvoiceLine.fromJson)
              .toList() ??
          const [],
    );
  }
}

/// A compact invoice row as the dashboard returns it — fewer fields than the
/// full invoice, and it carries its own `overdue` flag rather than making the
/// caller work it out.
class InvoiceLine {
  const InvoiceLine({
    required this.id,
    required this.invoiceNumber,
    required this.totalAmount,
    required this.balanceAmount,
    required this.status,
    required this.overdue,
    this.clientName,
    this.dueDate,
  });

  final int id;
  final String invoiceNumber;
  final double totalAmount;
  final double balanceAmount;
  final String status;
  final bool overdue;
  final String? clientName;
  final String? dueDate;

  factory InvoiceLine.fromJson(Map<String, dynamic> json) => InvoiceLine(
        id: (json['id'] as num?)?.toInt() ?? 0,
        invoiceNumber: json['invoiceNumber'] as String? ?? '',
        totalAmount: (json['totalAmount'] as num?)?.toDouble() ?? 0,
        balanceAmount: (json['balanceAmount'] as num?)?.toDouble() ?? 0,
        status: json['status'] as String? ?? '',
        overdue: json['overdue'] as bool? ?? false,
        clientName: json['clientName'] as String?,
        dueDate: json['dueDate'] as String?,
      );
}

class Expense {
  const Expense({
    required this.id,
    required this.expenseNumber,
    required this.description,
    required this.amount,
    required this.expenseDate,
    required this.status,
    required this.createdAt,
    this.title,
    this.vendorName,
    this.category,
    this.expenseAccountName,
    this.receiptUrl,
    this.submittedByName,
    this.approvedByName,
    this.approvalNotes,
    this.submittedAt,
    this.notes,
    this.currency,
    this.reimbursedDate,
    this.reimbursementMethod,
    this.referenceNumber,
  });

  final int id;
  final String expenseNumber;
  final String description;
  final double amount;
  final String expenseDate;
  final String status;
  final String createdAt;
  final String? title;
  final String? vendorName;
  final String? category;
  final String? expenseAccountName;
  final String? receiptUrl;
  final String? submittedByName;
  final String? approvedByName;
  final String? approvalNotes;
  final String? submittedAt;
  final String? notes;
  final String? currency;
  final String? reimbursedDate;
  final String? reimbursementMethod;
  final String? referenceNumber;

  bool get isPending => status == ExpenseStatus.pending;
  bool get isApproved => status == ExpenseStatus.approved;
  bool get isPaid => status == ExpenseStatus.paid;

  /// Approved but not yet reimbursed — the state someone is waiting on money in.
  bool get awaitingReimbursement => isApproved && reimbursedDate == null;

  bool get hasReceipt => receiptUrl != null && receiptUrl!.trim().isNotEmpty;

  /// What to show as the row's heading. `title` is the tidy one-liner the AI
  /// composer writes; `description` is what a person typed.
  String get headline {
    final t = title?.trim();
    return (t != null && t.isNotEmpty) ? t : description;
  }

  factory Expense.fromJson(Map<String, dynamic> json) => Expense(
        id: (json['id'] as num?)?.toInt() ?? 0,
        expenseNumber: json['expenseNumber'] as String? ?? '',
        description: json['description'] as String? ?? '',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        expenseDate: json['expenseDate'] as String? ?? '',
        status: json['status'] as String? ?? ExpenseStatus.pending,
        createdAt: json['createdAt'] as String? ?? '',
        title: json['title'] as String?,
        vendorName: json['vendorName'] as String?,
        category: json['category'] as String?,
        expenseAccountName: json['expenseAccountName'] as String?,
        receiptUrl: json['receiptUrl'] as String?,
        submittedByName: json['submittedByName'] as String?,
        approvedByName: json['approvedByName'] as String?,
        approvalNotes: json['approvalNotes'] as String?,
        submittedAt: json['submittedAt'] as String?,
        notes: json['notes'] as String?,
        currency: json['currency'] as String?,
        reimbursedDate: json['reimbursedDate'] as String?,
        reimbursementMethod: json['reimbursementMethod'] as String?,
        referenceNumber: json['referenceNumber'] as String?,
      );
}

/// POST /company/finance/expenses
class CreateExpenseRequest {
  const CreateExpenseRequest({
    required this.description,
    required this.amount,
    required this.expenseDate,
    this.title,
    this.vendorName,
    this.category,
    this.notes,
  });

  final String description;
  final double amount;

  /// `yyyy-MM-dd`.
  final String expenseDate;

  final String? title;
  final String? vendorName;
  final String? category;
  final String? notes;

  Map<String, dynamic> toJson() {
    String? clean(String? value) {
      final trimmed = value?.trim();
      return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    }

    return {
      'description': description.trim(),
      'amount': amount,
      'expenseDate': expenseDate,
      if (clean(title) != null) 'title': clean(title),
      if (clean(vendorName) != null) 'vendorName': clean(vendorName),
      if (clean(category) != null) 'category': clean(category),
      if (clean(notes) != null) 'notes': clean(notes),
    };
  }
}

class Wallet {
  const Wallet({
    required this.id,
    required this.balance,
    required this.creditBalance,
    required this.totalAvailable,
    required this.currency,
  });

  final int id;
  final double balance;

  /// Promotional or refunded credit, spendable but not withdrawable.
  final double creditBalance;

  /// Cash plus credit. Server-computed, so the two cannot disagree.
  final double totalAvailable;

  final String currency;

  bool get hasCredit => creditBalance > 0;

  factory Wallet.fromJson(Map<String, dynamic> json) => Wallet(
        id: (json['id'] as num?)?.toInt() ?? 0,
        balance: (json['balance'] as num?)?.toDouble() ?? 0,
        creditBalance: (json['creditBalance'] as num?)?.toDouble() ?? 0,
        totalAvailable: (json['totalAvailable'] as num?)?.toDouble() ?? 0,
        currency: json['currency'] as String? ?? '',
      );
}

class WalletTransaction {
  const WalletTransaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.balanceAfter,
    required this.transactedAt,
    this.reference,
    this.notes,
  });

  final int id;
  final String type;
  final double amount;
  final double balanceAfter;
  final String transactedAt;
  final String? reference;
  final String? notes;

  /// Whether this put money in or took it out.
  ///
  /// Decided from the type rather than the sign of [amount]: the backend
  /// stores amounts as positive magnitudes on both sides, so reading the sign
  /// would show every debit as a credit.
  bool get isCredit => const {
        'TOP_UP',
        'CREDIT',
        'REFUND',
        'DEPOSIT',
        'BONUS',
        'ADJUSTMENT_CREDIT',
      }.contains(type);

  factory WalletTransaction.fromJson(Map<String, dynamic> json) =>
      WalletTransaction(
        id: (json['id'] as num?)?.toInt() ?? 0,
        type: json['type'] as String? ?? '',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        balanceAfter: (json['balanceAfter'] as num?)?.toDouble() ?? 0,
        transactedAt: json['transactedAt'] as String? ?? '',
        reference: json['reference'] as String?,
        notes: json['notes'] as String?,
      );
}
