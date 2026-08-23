/// Hiring permissions, taken from the services rather than the Angular routes.
abstract final class RecruitmentPermissions {
  static const jobView = 'JOB_POSTING_VIEW';

  /// Publishing, closing and reassigning a posting are all one permission.
  static const jobUpdate = 'JOB_POSTING_UPDATE';

  static const applicationView = 'APPLICATION_VIEW';

  /// Moving an application along, scoring it, and every interview and offer
  /// action share this one code.
  static const applicationUpdate = 'APPLICATION_UPDATE';

  /// Hiring is gated on **EMPLOYEE_CREATE**, not APPLICATION_UPDATE — it
  /// creates a person, not a status change. Named here so the distinction is
  /// visible even though the app does not offer the action.
  static const hire = 'EMPLOYEE_CREATE';
}

abstract final class JobPostingStatus {
  static const draft = 'DRAFT';
  static const open = 'OPEN';
  static const closed = 'CLOSED';
  static const onHold = 'ON_HOLD';
}

/// The hiring pipeline, in the order an application travels.
abstract final class ApplicationStatus {
  static const applied = 'APPLIED';
  static const screening = 'SCREENING';
  static const shortlisted = 'SHORTLISTED';
  static const interviewScheduled = 'INTERVIEW_SCHEDULED';
  static const interviewed = 'INTERVIEWED';
  static const selected = 'SELECTED';
  static const offerPending = 'OFFER_PENDING';
  static const offerSent = 'OFFER_SENT';
  static const offerAccepted = 'OFFER_ACCEPTED';
  static const offerRejected = 'OFFER_REJECTED';
  static const hired = 'HIRED';
  static const rejected = 'REJECTED';
  static const withdrawn = 'WITHDRAWN';

  /// Offered as filters and as next steps, in pipeline order.
  static const pipeline = [
    applied,
    screening,
    shortlisted,
    interviewScheduled,
    interviewed,
    selected,
    offerPending,
    offerSent,
    offerAccepted,
  ];

  /// Nobody is waiting on these — the application is finished either way.
  static const terminal = {hired, rejected, withdrawn, offerRejected};
}

class JobPosting {
  const JobPosting({
    required this.id,
    required this.title,
    required this.status,
    required this.vacancies,
    this.jobTitle,
    this.location,
    this.employmentType,
    this.departmentName,
    this.deadline,
    this.remote = false,
    this.assignedRecruiterName,
    this.description,
    this.requirements,
    this.responsibilities,
    this.salaryMin,
    this.salaryMax,
  });

  final int id;
  final String title;
  final String status;
  final int vacancies;
  final String? jobTitle;
  final String? location;
  final String? employmentType;
  final String? departmentName;
  final String? deadline;
  final bool remote;
  final String? assignedRecruiterName;
  final String? description;
  final String? requirements;
  final String? responsibilities;
  final num? salaryMin;
  final num? salaryMax;

  bool get isDraft => status == JobPostingStatus.draft;
  bool get isOpen => status == JobPostingStatus.open;
  bool get isClosed => status == JobPostingStatus.closed;

  /// A draft is not visible to candidates yet; publishing is what opens it.
  bool get canPublish => isDraft || status == JobPostingStatus.onHold;
  bool get canClose => !isClosed;

  /// Past its deadline while still accepting applications — the posting is
  /// live on the careers page and shouldn't be.
  bool get deadlinePassed {
    if (!isOpen) return false;
    final date = DateTime.tryParse(deadline ?? '');
    if (date == null) return false;
    return DateTime.now().isAfter(date);
  }

  String? get whereLabel {
    if (remote) return location == null ? 'Remote' : 'Remote · $location';
    return location;
  }

  factory JobPosting.fromJson(Map<String, dynamic> json) => JobPosting(
        id: (json['id'] as num?)?.toInt() ?? 0,
        // The DTO carries both a posting title and the role's job title; the
        // posting title is the headline and the other is a fallback.
        title: json['title'] as String? ??
            json['jobTitle'] as String? ??
            'Untitled posting',
        status: json['status'] as String? ?? JobPostingStatus.draft,
        vacancies: (json['vacancies'] as num?)?.toInt() ?? 0,
        jobTitle: json['jobTitle'] as String?,
        location: json['location'] as String?,
        employmentType: json['employmentType'] as String?,
        departmentName: json['departmentName'] as String?,
        deadline: json['deadline'] as String?,
        remote: json['remote'] as bool? ?? false,
        assignedRecruiterName: json['assignedRecruiterName'] as String?,
        description: json['description'] as String?,
        requirements: json['requirements'] as String?,
        responsibilities: json['responsibilities'] as String?,
        salaryMin: json['salaryMin'] as num?,
        salaryMax: json['salaryMax'] as num?,
      );
}

class JobApplication {
  const JobApplication({
    required this.id,
    required this.status,
    this.candidateId,
    this.candidateName,
    this.candidateEmail,
    this.candidatePhone,
    this.jobPostingId,
    this.jobPostingTitle,
    this.source,
    this.notes,
    this.resumeUrl,
    this.linkedInUrl,
    this.portfolioUrl,
    this.reviewedByName,
    this.scoreEducation,
    this.scoreExperience,
    this.scoreTechnicalSkills,
    this.scoreInterview,
    this.scoreCommunication,
    this.overallScore,
    this.atsScore,
  });

  final int id;
  final String status;
  final int? candidateId;
  final String? candidateName;
  final String? candidateEmail;
  final String? candidatePhone;
  final int? jobPostingId;
  final String? jobPostingTitle;
  final String? source;
  final String? notes;
  final String? resumeUrl;
  final String? linkedInUrl;
  final String? portfolioUrl;
  final String? reviewedByName;

  /// The five manual scores, each nullable until somebody sets them.
  final int? scoreEducation;
  final int? scoreExperience;
  final int? scoreTechnicalSkills;
  final int? scoreInterview;
  final int? scoreCommunication;

  /// Averaged server-side from whichever scores are set.
  final double? overallScore;

  /// From CV parsing, not from a human. Kept visibly separate from
  /// [overallScore] because the two mean very different things.
  final int? atsScore;

  String get personLabel => candidateName?.trim().isNotEmpty == true
      ? candidateName!.trim()
      : 'Candidate #${candidateId ?? id}';

  bool get isTerminal => ApplicationStatus.terminal.contains(status);
  bool get isHired => status == ApplicationStatus.hired;

  bool get hasScores =>
      scoreEducation != null ||
      scoreExperience != null ||
      scoreTechnicalSkills != null ||
      scoreInterview != null ||
      scoreCommunication != null;

  /// The statuses worth offering next.
  ///
  /// Terminal applications offer nothing — reopening one is not a transition
  /// the backend models — and the current status is left out so the list is
  /// only ever a move, never a no-op.
  List<String> get nextStatuses {
    if (isTerminal) return const [];
    return [
      ...ApplicationStatus.pipeline.where((s) => s != status),
      ApplicationStatus.rejected,
      ApplicationStatus.withdrawn,
    ];
  }

  factory JobApplication.fromJson(Map<String, dynamic> json) => JobApplication(
        id: (json['id'] as num?)?.toInt() ?? 0,
        status: json['status'] as String? ?? ApplicationStatus.applied,
        candidateId: (json['candidateId'] as num?)?.toInt(),
        candidateName: json['candidateName'] as String?,
        candidateEmail: json['candidateEmail'] as String?,
        candidatePhone: json['candidatePhone'] as String?,
        jobPostingId: (json['jobPostingId'] as num?)?.toInt(),
        jobPostingTitle: json['jobPostingTitle'] as String?,
        source: json['source'] as String?,
        notes: json['notes'] as String?,
        resumeUrl: json['resumeUrl'] as String?,
        linkedInUrl: json['linkedInUrl'] as String?,
        portfolioUrl: json['portfolioUrl'] as String?,
        reviewedByName: json['reviewedByName'] as String?,
        scoreEducation: (json['scoreEducation'] as num?)?.toInt(),
        scoreExperience: (json['scoreExperience'] as num?)?.toInt(),
        scoreTechnicalSkills: (json['scoreTechnicalSkills'] as num?)?.toInt(),
        scoreInterview: (json['scoreInterview'] as num?)?.toInt(),
        scoreCommunication: (json['scoreCommunication'] as num?)?.toInt(),
        overallScore: (json['overallScore'] as num?)?.toDouble(),
        atsScore: (json['atsScore'] as num?)?.toInt(),
      );
}

abstract final class InterviewStatus {
  static const scheduled = 'SCHEDULED';
  static const completed = 'COMPLETED';
  static const cancelled = 'CANCELLED';
  static const noShow = 'NO_SHOW';
}

class Interview {
  const Interview({
    required this.id,
    required this.jobApplicationId,
    required this.status,
    this.applicantName,
    this.jobTitle,
    this.round,
    this.scheduledAt,
    this.durationMinutes,
    this.mode,
    this.meetingLink,
    this.interviewerName,
    this.rating,
    this.strengths,
    this.concerns,
    this.recommendation,
  });

  final int id;
  final int jobApplicationId;
  final String status;
  final String? applicantName;
  final String? jobTitle;
  final String? round;
  final String? scheduledAt;
  final int? durationMinutes;
  final String? mode;
  final String? meetingLink;
  final String? interviewerName;
  final int? rating;
  final String? strengths;
  final String? concerns;
  final String? recommendation;

  bool get isScheduled => status == InterviewStatus.scheduled;
  bool get hasFeedback => rating != null || recommendation != null;

  DateTime? get when => DateTime.tryParse(scheduledAt ?? '');

  /// Still scheduled but the slot has passed — somebody owes feedback.
  bool get awaitingFeedback {
    final at = when;
    return isScheduled && at != null && DateTime.now().isAfter(at);
  }

  bool get isToday {
    final at = when;
    if (at == null) return false;
    final now = DateTime.now();
    return at.year == now.year && at.month == now.month && at.day == now.day;
  }

  factory Interview.fromJson(Map<String, dynamic> json) => Interview(
        id: (json['id'] as num?)?.toInt() ?? 0,
        jobApplicationId: (json['jobApplicationId'] as num?)?.toInt() ?? 0,
        status: json['status'] as String? ?? InterviewStatus.scheduled,
        applicantName: json['applicantName'] as String?,
        jobTitle: json['jobTitle'] as String?,
        round: json['round'] as String?,
        scheduledAt: json['scheduledAt'] as String?,
        durationMinutes: (json['durationMinutes'] as num?)?.toInt(),
        mode: json['mode'] as String?,
        meetingLink: json['meetingLink'] as String?,
        interviewerName: json['interviewerName'] as String?,
        rating: (json['rating'] as num?)?.toInt(),
        strengths: json['strengths'] as String?,
        concerns: json['concerns'] as String?,
        recommendation: json['recommendation'] as String?,
      );
}

abstract final class OfferStatus {
  static const draft = 'DRAFT';
  static const sent = 'SENT';
  static const accepted = 'ACCEPTED';
  static const declined = 'DECLINED';
  static const withdrawn = 'WITHDRAWN';
}

class JobOffer {
  const JobOffer({
    required this.id,
    required this.jobApplicationId,
    required this.status,
    required this.expired,
    this.applicantName,
    this.jobPostingTitle,
    this.offeredJobTitle,
    this.joiningDate,
    this.expiryDate,
    this.grossSalary,
    this.sentAt,
    this.decidedAt,
    this.declineReason,
  });

  final int id;
  final int jobApplicationId;
  final String status;

  /// Computed server-side: a SENT offer past its expiry date. Expiry is not a
  /// stored status, so this is the only thing that says so — re-deriving it
  /// from the date here would risk disagreeing with the server.
  final bool expired;

  final String? applicantName;
  final String? jobPostingTitle;
  final String? offeredJobTitle;
  final String? joiningDate;
  final String? expiryDate;
  final num? grossSalary;
  final String? sentAt;
  final String? decidedAt;
  final String? declineReason;

  bool get isDraft => status == OfferStatus.draft;
  bool get isSent => status == OfferStatus.sent;

  /// Awaiting an answer. An expired offer is still SENT server-side but is not
  /// something to keep waiting on.
  bool get isPending => isSent && !expired;

  bool get isSettled =>
      status == OfferStatus.accepted ||
      status == OfferStatus.declined ||
      status == OfferStatus.withdrawn;

  /// What the chip should say. The stored status alone would show an expired
  /// offer as merely "Sent".
  String get displayStatus => expired && isSent ? 'EXPIRED' : status;

  factory JobOffer.fromJson(Map<String, dynamic> json) => JobOffer(
        id: (json['id'] as num?)?.toInt() ?? 0,
        jobApplicationId: (json['jobApplicationId'] as num?)?.toInt() ?? 0,
        status: json['status'] as String? ?? OfferStatus.draft,
        expired: json['expired'] as bool? ?? false,
        applicantName: json['applicantName'] as String?,
        jobPostingTitle: json['jobPostingTitle'] as String?,
        offeredJobTitle: json['offeredJobTitle'] as String?,
        joiningDate: json['joiningDate'] as String?,
        expiryDate: json['expiryDate'] as String?,
        grossSalary: json['grossSalary'] as num?,
        sentAt: json['sentAt'] as String?,
        decidedAt: json['decidedAt'] as String?,
        declineReason: json['declineReason'] as String?,
      );
}
