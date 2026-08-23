/// Headline counts for the client's own dashboard — GET /dashboard/client-summary.
class ClientSummary {
  const ClientSummary({
    this.pendingRequests = 0,
    this.inProgressRequests = 0,
    this.completedRequests = 0,
    this.unpaidInvoices = 0,
    this.outstandingInvoiceAmount = 0,
  });

  final int pendingRequests;
  final int inProgressRequests;
  final int completedRequests;
  final int unpaidInvoices;
  final double outstandingInvoiceAmount;

  int get openRequests => pendingRequests + inProgressRequests;
  bool get owesMoney => unpaidInvoices > 0;

  factory ClientSummary.fromJson(Map<String, dynamic> json) => ClientSummary(
        pendingRequests: (json['pendingRequests'] as num?)?.toInt() ?? 0,
        inProgressRequests: (json['inProgressRequests'] as num?)?.toInt() ?? 0,
        completedRequests: (json['completedRequests'] as num?)?.toInt() ?? 0,
        unpaidInvoices: (json['unpaidInvoices'] as num?)?.toInt() ?? 0,
        outstandingInvoiceAmount:
            (json['outstandingInvoiceAmount'] as num?)?.toDouble() ?? 0,
      );
}

/// The backend's `InvoiceStatus` enum, verbatim.
///
/// Verbatim matters: the status filter is a path segment, and a value the Java
/// enum cannot parse comes back as a 500, not a 400 or an empty page. There is
/// no `SENT` — an issued invoice is `ISSUED`.
abstract final class InvoiceStatus {
  static const draft = 'DRAFT';
  static const issued = 'ISSUED';
  static const partiallyPaid = 'PARTIALLY_PAID';
  static const paid = 'PAID';
  static const overdue = 'OVERDUE';
  static const cancelled = 'CANCELLED';
  static const voided = 'VOIDED';
  static const refunded = 'REFUNDED';

  static const all = [
    draft,
    issued,
    partiallyPaid,
    paid,
    overdue,
    cancelled,
    voided,
    refunded,
  ];

  /// Nothing further will be collected on these, for whatever reason.
  static const settled = {paid, cancelled, voided, refunded};
}

class Invoice {
  const Invoice({
    required this.id,
    required this.invoiceNumber,
    required this.status,
    required this.subtotal,
    required this.taxAmount,
    required this.totalAmount,
    required this.paidAmount,
    required this.balanceAmount,
    this.invoiceDate,
    this.dueDate,
    this.currency,
    this.discountAmount,
    this.description,
    this.notes,
    this.paymentTerms,
    this.sentDate,
    this.paidDate,
    this.createdAt,
  });

  final int id;
  final String invoiceNumber;
  final String status;
  final double subtotal;
  final double taxAmount;
  final double totalAmount;
  final double paidAmount;

  /// What is still owed. Server-computed — it accounts for credits and
  /// part-payments, which a phone subtracting two numbers would miss.
  final double balanceAmount;

  final String? invoiceDate;
  final String? dueDate;
  final String? currency;
  final double? discountAmount;
  final String? description;
  final String? notes;
  final String? paymentTerms;
  final String? sentDate;
  final String? paidDate;
  final String? createdAt;

  bool get isSettled => InvoiceStatus.settled.contains(status);
  bool get isPartlyPaid => paidAmount > 0 && balanceAmount > 0;

  /// Past its due date with money still outstanding.
  ///
  /// Derived rather than trusting the status alone: a bill can be past due
  /// before any nightly job has relabelled it OVERDUE, and a client looking at
  /// their own account should see that immediately.
  bool get isOverdue {
    // Order matters. Settled or fully paid wins outright, so a paid bill is
    // never chased. Then the server's own label — it may know something the
    // dates do not, and a missing `dueDate` must not suppress it. Only then
    // fall back to comparing the date ourselves.
    if (isSettled || balanceAmount <= 0) return false;
    if (status == InvoiceStatus.overdue) return true;
    if (dueDate == null) return false;
    final due = DateTime.tryParse(dueDate!);
    if (due == null) return false;
    final today = DateTime.now();
    return DateTime(due.year, due.month, due.day)
        .isBefore(DateTime(today.year, today.month, today.day));
  }

  factory Invoice.fromJson(Map<String, dynamic> json) {
    double d(String key) => (json[key] as num?)?.toDouble() ?? 0;
    return Invoice(
      id: (json['id'] as num?)?.toInt() ?? 0,
      invoiceNumber: json['invoiceNumber'] as String? ?? '',
      status: json['status'] as String? ?? InvoiceStatus.draft,
      subtotal: d('subtotal'),
      taxAmount: d('taxAmount'),
      totalAmount: d('totalAmount'),
      paidAmount: d('paidAmount'),
      balanceAmount: d('balanceAmount'),
      invoiceDate: json['invoiceDate'] as String?,
      dueDate: json['dueDate'] as String?,
      currency: json['currency'] as String?,
      discountAmount: (json['discountAmount'] as num?)?.toDouble(),
      description: json['description'] as String?,
      notes: json['notes'] as String?,
      paymentTerms: json['paymentTerms'] as String?,
      sentDate: json['sentDate'] as String?,
      paidDate: json['paidDate'] as String?,
      createdAt: json['createdAt'] as String?,
    );
  }
}

class PaymentReceipt {
  const PaymentReceipt({
    required this.id,
    required this.receiptNumber,
    required this.amount,
    required this.paymentDate,
    required this.status,
    this.invoiceNumber,
    this.paymentMethod,
    this.transactionReference,
    this.notes,
    this.createdAt,
  });

  final int id;
  final String receiptNumber;
  final double amount;
  final String paymentDate;
  final String status;
  final String? invoiceNumber;
  final String? paymentMethod;
  final String? transactionReference;
  final String? notes;
  final String? createdAt;

  factory PaymentReceipt.fromJson(Map<String, dynamic> json) => PaymentReceipt(
        id: (json['id'] as num?)?.toInt() ?? 0,
        receiptNumber: json['receiptNumber'] as String? ?? '',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        paymentDate: json['paymentDate'] as String? ?? '',
        status: json['status'] as String? ?? '',
        invoiceNumber: json['invoiceNumber'] as String?,
        paymentMethod: json['paymentMethod'] as String?,
        transactionReference: json['transactionReference'] as String?,
        notes: json['notes'] as String?,
        createdAt: json['createdAt'] as String?,
      );
}

class PackageSubscription {
  const PackageSubscription({
    required this.id,
    required this.packageId,
    required this.status,
    required this.requestsUsed,
    required this.remainingRequests,
    required this.autoRenew,
    required this.createdAt,
    this.packageName,
    this.billingCycle,
    this.startDate,
    this.endDate,
    this.nextBillingDate,
    this.pricePaid,
    this.requestQuota,
  });

  final int id;
  final int packageId;
  final String status;
  final int requestsUsed;
  final int remainingRequests;
  final bool autoRenew;
  final String createdAt;
  final String? packageName;
  final String? billingCycle;
  final String? startDate;
  final String? endDate;
  final String? nextBillingDate;
  final double? pricePaid;
  final int? requestQuota;

  bool get isActive => status == 'ACTIVE';

  /// How much of the quota is used, or null when the plan is unmetered — a
  /// bar at 0% would imply a limit that does not exist.
  double? get quotaUsedFraction {
    final quota = requestQuota;
    if (quota == null || quota <= 0) return null;
    return (requestsUsed / quota).clamp(0.0, 1.0);
  }

  factory PackageSubscription.fromJson(Map<String, dynamic> json) =>
      PackageSubscription(
        id: (json['id'] as num?)?.toInt() ?? 0,
        packageId: (json['packageId'] as num?)?.toInt() ?? 0,
        status: json['status'] as String? ?? '',
        requestsUsed: (json['requestsUsed'] as num?)?.toInt() ?? 0,
        remainingRequests: (json['remainingRequests'] as num?)?.toInt() ?? 0,
        autoRenew: json['autoRenew'] as bool? ?? false,
        createdAt: json['createdAt'] as String? ?? '',
        packageName: json['packageName'] as String?,
        billingCycle: json['billingCycle'] as String?,
        startDate: json['startDate'] as String?,
        endDate: json['endDate'] as String?,
        nextBillingDate: json['nextBillingDate'] as String?,
        pricePaid: (json['pricePaid'] as num?)?.toDouble(),
        requestQuota: (json['requestQuota'] as num?)?.toInt(),
      );
}

/// The client's own account record — GET /clients/me.
class ClientProfile {
  const ClientProfile({
    required this.id,
    required this.status,
    this.firstName,
    this.lastName,
    this.email,
    this.phone,
    this.clientCompanyName,
    this.industry,
    this.website,
    this.billingAddress,
    this.accountManagerName,
    this.onboardedAt,
    this.lifetimeValue,
    this.totalRequests,
  });

  final int id;
  final String status;
  final String? firstName;
  final String? lastName;
  final String? email;
  final String? phone;
  final String? clientCompanyName;
  final String? industry;
  final String? website;
  final String? billingAddress;
  final String? accountManagerName;
  final String? onboardedAt;
  final double? lifetimeValue;
  final int? totalRequests;

  String get contactName => [firstName, lastName]
      .where((part) => part != null && part.trim().isNotEmpty)
      .join(' ')
      .trim();

  String get headline {
    final company = clientCompanyName?.trim();
    if (company != null && company.isNotEmpty) return company;
    final contact = contactName;
    return contact.isNotEmpty ? contact : (email ?? 'Your account');
  }

  String get initials {
    final parts =
        headline.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  factory ClientProfile.fromJson(Map<String, dynamic> json) => ClientProfile(
        id: (json['id'] as num?)?.toInt() ?? 0,
        status: json['status'] as String? ?? 'ACTIVE',
        firstName: json['firstName'] as String?,
        lastName: json['lastName'] as String?,
        email: json['email'] as String?,
        phone: json['phone'] as String?,
        clientCompanyName: json['clientCompanyName'] as String?,
        industry: json['industry'] as String?,
        website: json['website'] as String?,
        billingAddress: json['billingAddress'] as String?,
        accountManagerName: json['accountManagerName'] as String?,
        onboardedAt: json['onboardedAt'] as String?,
        lifetimeValue: (json['lifetimeValue'] as num?)?.toDouble(),
        totalRequests: (json['totalRequests'] as num?)?.toInt(),
      );
}
