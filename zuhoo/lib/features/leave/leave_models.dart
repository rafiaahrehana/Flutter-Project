const leaveTypes = <String>[
  'ANNUAL',
  'SICK',
  'CASUAL',
  'MATERNITY',
  'PATERNITY',
  'UNPAID',
  'COMPENSATORY',
];

abstract final class LeaveStatus {
  static const pending = 'PENDING';
  static const approved = 'APPROVED';
  static const rejected = 'REJECTED';
  static const cancelled = 'CANCELLED';

  static const all = [pending, approved, rejected, cancelled];
}

abstract final class LeavePermissions {
  /// Reading the queue at all.
  static const view = 'LEAVE_VIEW';

  /// Deciding a request.
  ///
  /// The backend checks only this on `PATCH /hr/leaves/{id}/review` — both
  /// approving *and* rejecting go through that one endpoint. `LEAVE_REJECT`
  /// therefore gets somebody into the queue but not through it, which is why
  /// the screen gates the list and the buttons on different codes.
  static const approve = 'LEAVE_APPROVE';

  /// Held by reviewers who may only turn requests down. Enough to see the
  /// queue, per the web app, but not enough for the review call to succeed.
  static const reject = 'LEAVE_REJECT';
}

/// PATCH /hr/leaves/{id}/review
class ReviewLeaveRequest {
  const ReviewLeaveRequest.approve() : status = LeaveStatus.approved, rejectionReason = null;

  /// The reason is not optional on a rejection — the backend rejects a blank
  /// one, and an unexplained refusal tells the person nothing about whether to
  /// ask again.
  const ReviewLeaveRequest.reject(String reason)
      : status = LeaveStatus.rejected,
        rejectionReason = reason;

  final String status;
  final String? rejectionReason;

  Map<String, dynamic> toJson() => {
        'status': status,
        if (rejectionReason != null && rejectionReason!.trim().isNotEmpty)
          'rejectionReason': rejectionReason!.trim(),
      };
}

class LeaveRequest {
  const LeaveRequest({
    required this.id,
    required this.leaveType,
    required this.startDate,
    required this.endDate,
    required this.totalDays,
    required this.status,
    required this.employeeId,
    this.employeeName,
    this.reason,
    this.rejectionReason,
    this.reviewedAt,
    this.reviewedByName,
    this.createdAt,
  });

  final int id;
  final String leaveType;
  final String startDate;
  final String endDate;
  final double totalDays;
  final String status;
  final int employeeId;

  /// Absent on the personal list — you know who you are — and present on the
  /// reviewer's queue, where a list of employee ids would be unusable.
  final String? employeeName;

  final String? reason;
  final String? rejectionReason;
  final String? reviewedAt;
  final String? reviewedByName;
  final String? createdAt;

  /// Only a request nobody has acted on can be withdrawn. Once HR has
  /// approved or rejected it, the record is theirs.
  bool get canCancel => status == LeaveStatus.pending;

  factory LeaveRequest.fromJson(Map<String, dynamic> json) => LeaveRequest(
        id: (json['id'] as num?)?.toInt() ?? 0,
        leaveType: json['leaveType'] as String? ?? '',
        startDate: json['startDate'] as String? ?? '',
        endDate: json['endDate'] as String? ?? '',
        totalDays: (json['totalDays'] as num?)?.toDouble() ?? 0,
        status: json['status'] as String? ?? LeaveStatus.pending,
        employeeId: (json['employeeId'] as num?)?.toInt() ?? 0,
        employeeName: json['employeeName'] as String?,
        reason: json['reason'] as String?,
        rejectionReason: json['rejectionReason'] as String?,
        reviewedAt: json['reviewedAt'] as String?,
        reviewedByName: json['reviewedByName'] as String?,
        createdAt: json['createdAt'] as String?,
      );
}

class LeaveRequestPayload {
  const LeaveRequestPayload({
    required this.leaveType,
    required this.startDate,
    required this.endDate,
    this.reason,
  });

  final String leaveType;
  final String startDate;
  final String endDate;
  final String? reason;

  Map<String, dynamic> toJson() => {
        'leaveType': leaveType,
        'startDate': startDate,
        'endDate': endDate,
        if (reason != null && reason!.trim().isNotEmpty) 'reason': reason!.trim(),
      };
}

class LeaveBalance {
  const LeaveBalance({
    required this.id,
    required this.leaveType,
    required this.year,
    required this.entitledDays,
    required this.usedDays,
    required this.pendingDays,
    required this.remainingDays,
  });

  final int id;
  final String leaveType;
  final int year;
  final double entitledDays;
  final double usedDays;
  final double pendingDays;

  /// The server computes this as max(0, entitled - used - pending). Taken as
  /// given rather than recomputed here, so the two cannot drift apart and show
  /// an employee a different number of days than HR sees.
  final double remainingDays;

  /// Used plus pending as a share of the entitlement, for the progress bar.
  double get consumedFraction {
    if (entitledDays <= 0) return 0;
    final consumed = (usedDays + pendingDays) / entitledDays;
    return consumed.clamp(0, 1).toDouble();
  }

  factory LeaveBalance.fromJson(Map<String, dynamic> json) => LeaveBalance(
        id: (json['id'] as num?)?.toInt() ?? 0,
        leaveType: json['leaveType'] as String? ?? '',
        year: (json['year'] as num?)?.toInt() ?? DateTime.now().year,
        entitledDays: (json['entitledDays'] as num?)?.toDouble() ?? 0,
        usedDays: (json['usedDays'] as num?)?.toDouble() ?? 0,
        pendingDays: (json['pendingDays'] as num?)?.toDouble() ?? 0,
        remainingDays: (json['remainingDays'] as num?)?.toDouble() ?? 0,
      );
}
