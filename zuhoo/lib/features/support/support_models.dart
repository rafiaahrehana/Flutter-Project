/// Permission codes this module gates on.
abstract final class SupportPermissions {
  static const messageView = 'SUPPORT_MESSAGE_VIEW';
  static const ticketView = 'TICKET_VIEW';
}

/// Which direction a ticket runs in.
///
/// The two are different products sharing one table, and conflating them is
/// the easiest mistake to make here: PLATFORM_SUPPORT is this company asking
/// BusinessOS for help, CUSTOMER_SUPPORT is one of this company's own portal
/// clients asking *them*. The list endpoints are filtered by type server-side,
/// so a screen has to call the right one — there is no single "all tickets".
abstract final class TicketType {
  static const platform = 'PLATFORM_SUPPORT';
  static const customer = 'CUSTOMER_SUPPORT';
}

abstract final class TicketStatus {
  static const isNew = 'NEW';
  static const open = 'OPEN';
  static const inProgress = 'IN_PROGRESS';
  static const waiting = 'WAITING';
  static const onHold = 'ON_HOLD';
  static const resolved = 'RESOLVED';
  static const closed = 'CLOSED';

  static const all = [
    isNew,
    open,
    inProgress,
    waiting,
    onHold,
    resolved,
    closed,
  ];

  /// Nothing more is expected from anyone on a ticket in one of these.
  static const settled = {resolved, closed};

  static bool isOpen(String status) => !settled.contains(status);
}

/// Support uses a different priority scale from service requests — MEDIUM and
/// CRITICAL here, NORMAL and URGENT there. They are separate backend enums, so
/// they stay separate lists rather than one shared constant that would fit
/// neither.
const ticketPriorities = <String>['LOW', 'MEDIUM', 'HIGH', 'CRITICAL'];

class SupportTicket {
  const SupportTicket({
    required this.id,
    required this.ticketNumber,
    required this.title,
    required this.status,
    required this.priority,
    required this.createdAt,
    this.ticketType,
    this.description,
    this.categoryName,
    this.source,
    this.assignedToAgentId,
    this.assignedToAgentName,
    this.assignedEmployeeName,
    this.assignedDate,
    this.firstResponseDeadline,
    this.resolutionDeadline,
    this.slaBreached = false,
    this.resolutionNotes,
    this.closedDate,
    this.satisfactionRating,
    this.satisfactionFeedback,
    this.escalationLevel = 0,
    this.escalatedDate,
    this.createdByName,
    this.firstResponseTime,
    this.resolutionTime,
    this.attachmentUrl,
    this.attachmentFileName,
    this.updatedAt,
  });

  final int id;
  final String ticketNumber;
  final String title;
  final String status;
  final String priority;
  final String createdAt;
  final String? ticketType;
  final String? description;
  final String? categoryName;
  final String? source;
  final int? assignedToAgentId;
  final String? assignedToAgentName;
  final String? assignedEmployeeName;
  final String? assignedDate;
  final String? firstResponseDeadline;
  final String? resolutionDeadline;

  /// Server-computed against the SLA policy. Shown, never recalculated here.
  final bool slaBreached;

  final String? resolutionNotes;
  final String? closedDate;
  final int? satisfactionRating;
  final String? satisfactionFeedback;
  final int escalationLevel;
  final String? escalatedDate;
  final String? createdByName;
  final String? firstResponseTime;
  final String? resolutionTime;
  final String? attachmentUrl;
  final String? attachmentFileName;
  final String? updatedAt;

  bool get isOpen => TicketStatus.isOpen(status);
  bool get isResolved => status == TicketStatus.resolved;
  bool get isClosed => status == TicketStatus.closed;

  /// Escalated past the first tier. Worth surfacing: it is the difference
  /// between a ticket that is merely open and one that someone has already
  /// pushed up the chain.
  bool get isEscalated => escalationLevel > 0;

  /// Nobody has picked this up yet.
  bool get isUnassigned =>
      assignedToAgentName == null && assignedEmployeeName == null;

  /// Whoever is handling it, whichever field the backend filled in.
  String? get handlerName => assignedToAgentName ?? assignedEmployeeName;

  factory SupportTicket.fromJson(Map<String, dynamic> json) => SupportTicket(
        id: (json['id'] as num?)?.toInt() ?? 0,
        ticketNumber: json['ticketNumber'] as String? ?? '',
        title: json['title'] as String? ?? '',
        status: json['status'] as String? ?? TicketStatus.isNew,
        priority: json['priority'] as String? ?? 'MEDIUM',
        createdAt: json['createdAt'] as String? ?? '',
        ticketType: json['ticketType'] as String?,
        description: json['description'] as String?,
        categoryName: json['categoryName'] as String?,
        source: json['source'] as String?,
        assignedToAgentId: (json['assignedToAgentId'] as num?)?.toInt(),
        assignedToAgentName: json['assignedToAgentName'] as String?,
        assignedEmployeeName: json['assignedEmployeeName'] as String?,
        assignedDate: json['assignedDate'] as String?,
        firstResponseDeadline: json['firstResponseDeadline'] as String?,
        resolutionDeadline: json['resolutionDeadline'] as String?,
        slaBreached: json['slaBreached'] as bool? ?? false,
        resolutionNotes: json['resolutionNotes'] as String?,
        closedDate: json['closedDate'] as String?,
        satisfactionRating: (json['satisfactionRating'] as num?)?.toInt(),
        satisfactionFeedback: json['satisfactionFeedback'] as String?,
        escalationLevel: (json['escalationLevel'] as num?)?.toInt() ?? 0,
        escalatedDate: json['escalatedDate'] as String?,
        createdByName: json['createdByName'] as String?,
        firstResponseTime: json['firstResponseTime'] as String?,
        resolutionTime: json['resolutionTime'] as String?,
        attachmentUrl: json['attachmentUrl'] as String?,
        attachmentFileName: json['attachmentFileName'] as String?,
        updatedAt: json['updatedAt'] as String?,
      );
}

class SupportMessage {
  const SupportMessage({
    required this.id,
    required this.ticketId,
    required this.message,
    required this.createdAt,
    required this.sentById,
    this.sentByName,
    this.messageType,
    this.isInternal = false,
    this.isResolution = false,
    this.attachmentUrl,
    this.attachmentFileName,
  });

  final int id;
  final int ticketId;
  final String message;
  final String createdAt;
  final int sentById;
  final String? sentByName;
  final String? messageType;

  /// Staff-only. The mobile client chat never reads or writes these — see
  /// [SupportRepository.clientChatMessages].
  final bool isInternal;

  final bool isResolution;
  final String? attachmentUrl;
  final String? attachmentFileName;

  bool get hasAttachment =>
      attachmentUrl != null && attachmentUrl!.isNotEmpty;

  factory SupportMessage.fromJson(Map<String, dynamic> json) => SupportMessage(
        id: (json['id'] as num?)?.toInt() ?? 0,
        ticketId: (json['ticketId'] as num?)?.toInt() ?? 0,
        message: json['message'] as String? ?? '',
        createdAt: json['createdAt'] as String? ?? '',
        sentById: (json['sentById'] as num?)?.toInt() ?? 0,
        sentByName: json['sentByName'] as String?,
        messageType: json['messageType'] as String?,
        isInternal: json['isInternal'] as bool? ?? false,
        isResolution: json['isResolution'] as bool? ?? false,
        attachmentUrl: json['attachmentUrl'] as String?,
        attachmentFileName: json['attachmentFileName'] as String?,
      );
}

/// POST /api/v1/support/tickets — a platform-support ticket, this company
/// asking BusinessOS for help.
class CreateTicketRequest {
  const CreateTicketRequest({
    required this.title,
    required this.description,
    this.priority = 'MEDIUM',
    this.categoryId,
  });

  final String title;
  final String description;
  final String priority;
  final int? categoryId;

  Map<String, dynamic> toJson() => {
        'title': title.trim(),
        'description': description.trim(),
        'priority': priority,
        if (categoryId != null) 'categoryId': categoryId,
      };
}
