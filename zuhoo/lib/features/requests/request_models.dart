/// Permission codes this module gates on. They are the backend's own strings —
/// the source of truth is `GET /api/users/permissions`, not a value duplicated
/// on both sides, so they stay plain constants rather than an enum.
abstract final class RequestPermissions {
  static const view = 'SERVICE_REQUEST_VIEW';
  static const approve = 'SERVICE_REQUEST_APPROVE';
}

abstract final class RequestStatus {
  static const pending = 'PENDING';
  static const quotationPending = 'QUOTATION_PENDING';
  static const assigned = 'ASSIGNED';
  static const inProgress = 'IN_PROGRESS';
  static const waitingClient = 'WAITING_CLIENT';
  static const underReview = 'UNDER_REVIEW';
  static const completed = 'COMPLETED';
  static const rejected = 'REJECTED';
  static const cancelled = 'CANCELLED';
  static const resubmitted = 'RESUBMITTED';

  /// Nothing further will happen to a request in one of these.
  static const closed = {completed, rejected, cancelled};

  static bool isOpen(String status) => !closed.contains(status);
}

const requestPriorities = <String>['LOW', 'NORMAL', 'HIGH', 'URGENT'];

/// A service request. Mirrors `ServiceRequestResponse`.
///
/// The quotation lives directly on this record rather than as its own entity —
/// the standalone QuotationController was removed server-side, so there is no
/// quotation list or CRUD endpoint to model.
class ServiceRequest {
  const ServiceRequest({
    required this.id,
    required this.title,
    required this.status,
    required this.priority,
    required this.createdAt,
    this.description,
    this.agreedPrice,
    this.slaDeadline,
    this.slaBreach = false,
    this.assignedAt,
    this.completedAt,
    this.clientName,
    this.hubServiceId,
    this.hubServiceName,
    this.assignedEmployeeId,
    this.assignedEmployeeName,
    this.taskCount = 0,
    this.completedTaskCount = 0,
    this.packageName,
    this.resubmitCount = 0,
    this.permanentlyClosed = false,
    this.invoiceId,
    this.govRefNumber,
    this.govRefType,
    this.quotationAmount,
    this.quotationCurrency,
    this.quotationNotes,
    this.quotationValidUntil,
    this.quotationStatus,
    this.aiSummary,
    this.updatedAt,
  });

  final int id;
  final String title;
  final String status;
  final String priority;
  final String createdAt;
  final String? description;
  final double? agreedPrice;
  final String? slaDeadline;

  /// Server-computed. Trusted as-is rather than recomputed from [slaDeadline],
  /// because the backend knows the working-hours calendar and the phone does not.
  final bool slaBreach;

  final String? assignedAt;
  final String? completedAt;
  final String? clientName;
  final int? hubServiceId;
  final String? hubServiceName;
  final int? assignedEmployeeId;
  final String? assignedEmployeeName;
  final int taskCount;
  final int completedTaskCount;
  final String? packageName;
  final int resubmitCount;
  final bool permanentlyClosed;
  final int? invoiceId;
  final String? govRefNumber;
  final String? govRefType;
  final double? quotationAmount;
  final String? quotationCurrency;
  final String? quotationNotes;
  final String? quotationValidUntil;
  final String? quotationStatus;
  final String? aiSummary;
  final String? updatedAt;

  bool get isOpen => RequestStatus.isOpen(status);

  /// Only an open request that has not been permanently closed can be withdrawn.
  bool get canCancel => isOpen && !permanentlyClosed;

  bool get hasQuotation => quotationAmount != null;

  /// A quotation the client still has to answer.
  bool get quotationAwaitsDecision =>
      hasQuotation && (quotationStatus == null || quotationStatus == 'PENDING');

  /// Task completion as a fraction, or null when the request has no tasks —
  /// a bar sitting at 0% would imply work that has not started, rather than
  /// work that was never broken into tasks at all.
  double? get taskProgress {
    if (taskCount <= 0) return null;
    return (completedTaskCount / taskCount).clamp(0.0, 1.0);
  }

  factory ServiceRequest.fromJson(Map<String, dynamic> json) {
    double? d(String key) => (json[key] as num?)?.toDouble();
    int i(String key) => (json[key] as num?)?.toInt() ?? 0;

    return ServiceRequest(
      id: i('id'),
      title: json['title'] as String? ?? '',
      status: json['status'] as String? ?? RequestStatus.pending,
      priority: json['priority'] as String? ?? 'NORMAL',
      createdAt: json['createdAt'] as String? ?? '',
      description: json['description'] as String?,
      agreedPrice: d('agreedPrice'),
      slaDeadline: json['slaDeadline'] as String?,
      slaBreach: json['slaBreach'] as bool? ?? false,
      assignedAt: json['assignedAt'] as String?,
      completedAt: json['completedAt'] as String?,
      clientName: json['clientName'] as String?,
      hubServiceId: (json['hubServiceId'] as num?)?.toInt(),
      hubServiceName: json['hubServiceName'] as String?,
      assignedEmployeeId: (json['assignedEmployeeId'] as num?)?.toInt(),
      assignedEmployeeName: json['assignedEmployeeName'] as String?,
      taskCount: i('taskCount'),
      completedTaskCount: i('completedTaskCount'),
      packageName: json['packageName'] as String?,
      resubmitCount: i('resubmitCount'),
      permanentlyClosed: json['permanentlyClosed'] as bool? ?? false,
      invoiceId: (json['invoiceId'] as num?)?.toInt(),
      govRefNumber: json['govRefNumber'] as String?,
      govRefType: json['govRefType'] as String?,
      quotationAmount: d('quotationAmount'),
      quotationCurrency: json['quotationCurrency'] as String?,
      quotationNotes: json['quotationNotes'] as String?,
      quotationValidUntil: json['quotationValidUntil'] as String?,
      quotationStatus: json['quotationStatus'] as String?,
      aiSummary: json['aiSummary'] as String?,
      updatedAt: json['updatedAt'] as String?,
    );
  }
}

/// A service from the company's catalogue, used when raising a request.
class CatalogService {
  const CatalogService({
    required this.id,
    required this.name,
    this.description,
    this.price,
    this.priceType,
    this.currency,
    this.estimatedDays,
    this.defaultPriority,
    this.categoryName,
    this.requiresQuotation = false,
    this.requiresDocuments = false,
  });

  final int id;
  final String name;
  final String? description;
  final double? price;
  final String? priceType;
  final String? currency;
  final int? estimatedDays;
  final String? defaultPriority;
  final String? categoryName;
  final bool requiresQuotation;
  final bool requiresDocuments;

  factory CatalogService.fromJson(Map<String, dynamic> json) => CatalogService(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? '',
        description: json['description'] as String?,
        price: (json['price'] as num?)?.toDouble(),
        priceType: json['priceType'] as String?,
        currency: json['currency'] as String?,
        estimatedDays: (json['estimatedDays'] as num?)?.toInt(),
        defaultPriority: json['defaultPriority'] as String?,
        categoryName: json['categoryName'] as String?,
        requiresQuotation: json['requiresQuotation'] as bool? ?? false,
        requiresDocuments: json['requiresDocuments'] as bool? ?? false,
      );
}

/// POST /api/service-requests.
///
/// `paymentChoice` is required by the backend. Only PAY_LATER is sent from the
/// phone: PAY_NOW returns an invoice and a gateway redirect URL, and handing
/// someone a half-built checkout is worse than sending them to the invoice.
class CreateServiceRequest {
  const CreateServiceRequest({
    required this.title,
    required this.hubServiceId,
    this.description,
    this.priority,
  });

  final String title;
  final int hubServiceId;
  final String? description;
  final String? priority;

  Map<String, dynamic> toJson() => {
        'title': title.trim(),
        'hubServiceId': hubServiceId,
        if (description != null && description!.trim().isNotEmpty)
          'description': description!.trim(),
        if (priority != null) 'priority': priority,
        'paymentChoice': 'PAY_LATER',
      };
}

/// Comment visibility. PUBLIC is visible to the client, INTERNAL is staff-only.
/// Omitted on create so the backend applies its own role-aware default
/// (CLIENT → PUBLIC, staff → INTERNAL) rather than this client guessing.
class RequestComment {
  const RequestComment({
    required this.id,
    required this.content,
    required this.createdAt,
    this.visibility,
    this.authorName,
    this.authorId,
    this.attachmentUrl,
  });

  final int id;
  final String content;
  final String createdAt;
  final String? visibility;
  final String? authorName;
  final int? authorId;
  final String? attachmentUrl;

  bool get isInternal => visibility == 'INTERNAL';

  factory RequestComment.fromJson(Map<String, dynamic> json) => RequestComment(
        id: (json['id'] as num?)?.toInt() ?? 0,
        content: json['content'] as String? ?? '',
        createdAt: json['createdAt'] as String? ?? '',
        visibility: json['visibility'] as String?,
        authorName: json['authorName'] as String?,
        authorId: (json['authorId'] as num?)?.toInt(),
        attachmentUrl: json['attachmentUrl'] as String?,
      );
}

class RequestStatusChange {
  const RequestStatusChange({
    required this.id,
    required this.newStatus,
    required this.changedAt,
    this.oldStatus,
    this.reason,
    this.changedByName,
  });

  final int id;
  final String newStatus;
  final String changedAt;
  final String? oldStatus;
  final String? reason;
  final String? changedByName;

  factory RequestStatusChange.fromJson(Map<String, dynamic> json) =>
      RequestStatusChange(
        id: (json['id'] as num?)?.toInt() ?? 0,
        newStatus: json['newStatus'] as String? ?? '',
        changedAt: json['changedAt'] as String? ?? '',
        oldStatus: json['oldStatus'] as String?,
        reason: json['reason'] as String?,
        changedByName: json['changedByName'] as String?,
      );
}

/// A workflow stage waiting on someone's decision.
class StageApproval {
  const StageApproval({
    required this.id,
    required this.status,
    required this.serviceRequestId,
    required this.createdAt,
    this.serviceRequestTitle,
    this.workflowStageName,
    this.stageOrder,
    this.approverRole,
    this.requestedByName,
    this.decidedByName,
    this.decisionNotes,
    this.decidedAt,
  });

  final int id;
  final String status;
  final int serviceRequestId;
  final String createdAt;
  final String? serviceRequestTitle;
  final String? workflowStageName;
  final int? stageOrder;
  final String? approverRole;
  final String? requestedByName;
  final String? decidedByName;
  final String? decisionNotes;
  final String? decidedAt;

  bool get isPending => status == 'PENDING';

  factory StageApproval.fromJson(Map<String, dynamic> json) => StageApproval(
        id: (json['id'] as num?)?.toInt() ?? 0,
        status: json['status'] as String? ?? 'PENDING',
        serviceRequestId: (json['serviceRequestId'] as num?)?.toInt() ?? 0,
        createdAt: json['createdAt'] as String? ?? '',
        serviceRequestTitle: json['serviceRequestTitle'] as String?,
        workflowStageName: json['workflowStageName'] as String?,
        stageOrder: (json['stageOrder'] as num?)?.toInt(),
        approverRole: json['approverRole'] as String?,
        requestedByName: json['requestedByName'] as String?,
        decidedByName: json['decidedByName'] as String?,
        decisionNotes: json['decisionNotes'] as String?,
        decidedAt: json['decidedAt'] as String?,
      );
}
