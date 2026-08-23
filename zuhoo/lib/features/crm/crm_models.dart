abstract final class CrmPermissions {
  static const leadView = 'LEAD_VIEW';
  static const opportunityView = 'OPPORTUNITY_VIEW';
  static const clientView = 'CLIENT_VIEW';
}

/// Where a deal sits. Order matters — it is the order of the pipeline, and the
/// screens render stages in this sequence.
abstract final class Stage {
  static const qualification = 'QUALIFICATION';
  static const presentation = 'PRESENTATION';
  static const proposal = 'PROPOSAL';
  static const negotiation = 'NEGOTIATION';
  static const won = 'WON';
  static const lost = 'LOST';

  /// Still in play. The closed pair is deliberately excluded from the board:
  /// a pipeline is what you can still act on.
  static const open = [qualification, presentation, proposal, negotiation];

  static const all = [...open, won, lost];

  static bool isOpen(String stage) => open.contains(stage);
  static bool isClosed(String stage) => stage == won || stage == lost;
}

abstract final class LeadStatus {
  static const isNew = 'NEW';
  static const contacted = 'CONTACTED';
  static const qualified = 'QUALIFIED';
  static const disqualified = 'DISQUALIFIED';

  static const all = [isNew, contacted, qualified, disqualified];
}

const leadSources = <String>[
  'WEBSITE',
  'REFERRAL',
  'SOCIAL_MEDIA',
  'EMAIL',
  'PHONE',
  'COLD_CALL',
  'OTHER',
];

const leadPriorities = <String>['LOW', 'NORMAL', 'HIGH', 'URGENT'];

const crmActivityTypes = <String>[
  'CALL',
  'MEETING',
  'EMAIL',
  'NOTE',
  'TASK',
  'FOLLOW_UP',
];

/// Why a deal was lost. The backend requires the code on a LOST transition, and
/// free-text detail on top of it when the code is OTHER.
const lostReasons = <({String code, String label})>[
  (code: 'PRICE', label: 'Price too high'),
  (code: 'COMPETITOR', label: 'Chose a competitor'),
  (code: 'NO_BUDGET', label: 'No budget'),
  (code: 'NO_RESPONSE', label: 'Went silent / no response'),
  (code: 'BAD_TIMING', label: 'Bad timing'),
  (code: 'REQUIREMENTS_MISMATCH', label: "Requirements didn't fit"),
  (code: 'OTHER', label: 'Other'),
];

class Tag {
  const Tag({required this.id, required this.name, required this.color});

  final int id;
  final String name;
  final String color;

  /// The backend stores a CSS hex. Anything it cannot parse falls back to null
  /// so the caller can use a neutral chip rather than crash on a bad value.
  int? get argb {
    var hex = color.trim().replaceFirst('#', '');
    if (hex.length == 3) {
      hex = hex.split('').map((c) => '$c$c').join();
    }
    if (hex.length != 6) return null;
    final value = int.tryParse(hex, radix: 16);
    return value == null ? null : 0xFF000000 | value;
  }

  factory Tag.fromJson(Map<String, dynamic> json) => Tag(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? '',
        color: json['color'] as String? ?? '',
      );

  static List<Tag> listFrom(Object? raw) => raw is List
      ? raw.whereType<Map<String, dynamic>>().map(Tag.fromJson).toList()
      : const [];
}

/// A client the backend thinks this deal might already belong to.
class DuplicateMatch {
  const DuplicateMatch({
    required this.clientId,
    required this.clientCompanyName,
    required this.matchedOn,
  });

  final int clientId;
  final String clientCompanyName;

  /// Which field matched — the reason to trust or dismiss the suggestion.
  final String matchedOn;

  static DuplicateMatch? tryFrom(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = (json['clientId'] as num?)?.toInt();
    if (id == null) return null;
    return DuplicateMatch(
      clientId: id,
      clientCompanyName: json['clientCompanyName'] as String? ?? '',
      matchedOn: json['matchedOn'] as String? ?? '',
    );
  }
}

class Lead {
  const Lead({
    required this.id,
    required this.contactName,
    required this.status,
    required this.source,
    required this.createdAt,
    required this.converted,
    this.companyName,
    this.email,
    this.phone,
    this.industry,
    this.jobTitle,
    this.notes,
    this.priority,
    this.estimatedValue,
    this.expectedCloseDate,
    this.assignedToName,
    this.lastContactDate,
    this.lastActivityAt,
    this.convertedClientName,
    this.activitiesCount,
    this.tags = const [],
    this.possibleDuplicate,
  });

  final int id;
  final String contactName;
  final String status;
  final String source;
  final String createdAt;
  final bool converted;
  final String? companyName;
  final String? email;
  final String? phone;
  final String? industry;
  final String? jobTitle;
  final String? notes;
  final String? priority;
  final double? estimatedValue;
  final String? expectedCloseDate;
  final String? assignedToName;
  final String? lastContactDate;
  final String? lastActivityAt;
  final String? convertedClientName;
  final int? activitiesCount;
  final List<Tag> tags;
  final DuplicateMatch? possibleDuplicate;

  /// Only a qualified lead that has not already been converted can become an
  /// opportunity — the backend enforces both, and offering the action anyway
  /// would just produce an error.
  bool get canConvert => status == LeadStatus.qualified && !converted;

  bool get isUnassigned => assignedToName == null;

  /// Nobody has recorded contact yet.
  bool get neverContacted => lastContactDate == null && lastActivityAt == null;

  /// What to call this lead in a list: the company if there is one, since a
  /// rep thinks in accounts, with the person underneath.
  String get headline =>
      (companyName != null && companyName!.trim().isNotEmpty)
          ? companyName!
          : contactName;

  String? get subline =>
      (companyName != null && companyName!.trim().isNotEmpty)
          ? contactName
          : (jobTitle ?? email);

  factory Lead.fromJson(Map<String, dynamic> json) => Lead(
        id: (json['id'] as num?)?.toInt() ?? 0,
        contactName: json['contactName'] as String? ?? '',
        status: json['status'] as String? ?? LeadStatus.isNew,
        source: json['source'] as String? ?? '',
        createdAt: json['createdAt'] as String? ?? '',
        converted: json['converted'] as bool? ?? false,
        companyName: json['companyName'] as String?,
        email: json['email'] as String?,
        phone: json['phone'] as String?,
        industry: json['industry'] as String?,
        jobTitle: json['jobTitle'] as String?,
        notes: json['notes'] as String? ?? json['description'] as String?,
        priority: json['priority'] as String?,
        estimatedValue: (json['estimatedValue'] as num?)?.toDouble(),
        expectedCloseDate: json['expectedCloseDate'] as String?,
        assignedToName: json['assignedToName'] as String?,
        lastContactDate: json['lastContactDate'] as String?,
        lastActivityAt: json['lastActivityAt'] as String?,
        convertedClientName: json['convertedClientName'] as String?,
        activitiesCount: (json['activitiesCount'] as num?)?.toInt(),
        tags: Tag.listFrom(json['tags']),
        possibleDuplicate: DuplicateMatch.tryFrom(json['possibleDuplicate']),
      );
}

class Opportunity {
  const Opportunity({
    required this.id,
    required this.name,
    required this.stage,
    required this.probability,
    required this.createdAt,
    this.description,
    this.source,
    this.amount,
    this.weightedAmount,
    this.expectedCloseDate,
    this.actualCloseDate,
    this.nextStep,
    this.lostReason,
    this.lostReasonCode,
    this.clientId,
    this.clientCompanyName,
    this.contactName,
    this.ownerName,
    this.lastActivityAt,
    this.stageChangedAt,
    this.sourceLeadId,
    this.tags = const [],
  });

  final int id;
  final String name;
  final String stage;

  /// Percent, server-derived from the stage.
  final int probability;

  final String createdAt;
  final String? description;
  final String? source;
  final double? amount;

  /// amount × probability, computed server-side. Taken as given so the phone
  /// and the web forecast cannot disagree.
  final double? weightedAmount;

  final String? expectedCloseDate;
  final String? actualCloseDate;
  final String? nextStep;
  final String? lostReason;
  final String? lostReasonCode;

  /// Null until the deal reaches Won and a client is created or linked.
  final int? clientId;

  final String? clientCompanyName;
  final String? contactName;
  final String? ownerName;
  final String? lastActivityAt;
  final String? stageChangedAt;
  final int? sourceLeadId;
  final List<Tag> tags;

  bool get isOpen => Stage.isOpen(stage);
  bool get isWon => stage == Stage.won;
  bool get isLost => stage == Stage.lost;

  /// Winning a deal with no client attached is what triggers the duplicate
  /// check — the backend has to decide whether to create a client or link an
  /// existing one, and it asks first.
  bool get needsClientDecisionOnWin => clientId == null;

  /// Past its expected close date and still open.
  bool get isOverdue {
    if (!isOpen || expectedCloseDate == null) return false;
    final due = DateTime.tryParse(expectedCloseDate!);
    if (due == null) return false;
    final today = DateTime.now();
    return DateTime(due.year, due.month, due.day)
        .isBefore(DateTime(today.year, today.month, today.day));
  }

  factory Opportunity.fromJson(Map<String, dynamic> json) => Opportunity(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? '',
        stage: json['stage'] as String? ?? Stage.qualification,
        probability: (json['probability'] as num?)?.toInt() ?? 0,
        createdAt: json['createdAt'] as String? ?? '',
        description: json['description'] as String?,
        source: json['source'] as String?,
        amount: (json['amount'] as num?)?.toDouble(),
        weightedAmount: (json['weightedAmount'] as num?)?.toDouble(),
        expectedCloseDate: json['expectedCloseDate'] as String?,
        actualCloseDate: json['actualCloseDate'] as String?,
        nextStep: json['nextStep'] as String?,
        lostReason: json['lostReason'] as String?,
        lostReasonCode: json['lostReasonCode'] as String?,
        clientId: (json['clientId'] as num?)?.toInt(),
        clientCompanyName: json['clientCompanyName'] as String?,
        contactName: json['contactName'] as String?,
        ownerName: json['ownerName'] as String?,
        lastActivityAt: json['lastActivityAt'] as String?,
        stageChangedAt: json['stageChangedAt'] as String?,
        sourceLeadId: (json['sourceLeadId'] as num?)?.toInt(),
        tags: Tag.listFrom(json['tags']),
      );
}

class PipelineStageSummary {
  const PipelineStageSummary({
    required this.stage,
    required this.dealCount,
    required this.totalAmount,
    required this.weightedAmount,
  });

  final String stage;
  final int dealCount;
  final double totalAmount;
  final double weightedAmount;

  factory PipelineStageSummary.fromJson(Map<String, dynamic> json) =>
      PipelineStageSummary(
        stage: json['stage'] as String? ?? '',
        dealCount: (json['dealCount'] as num?)?.toInt() ?? 0,
        totalAmount: (json['totalAmount'] as num?)?.toDouble() ?? 0,
        weightedAmount: (json['weightedAmount'] as num?)?.toDouble() ?? 0,
      );
}

class PipelineSummary {
  const PipelineSummary({
    this.stages = const [],
    this.openPipelineValue = 0,
    this.weightedForecast = 0,
    this.wonValue = 0,
    this.totalOpenDeals = 0,
  });

  final List<PipelineStageSummary> stages;
  final double openPipelineValue;
  final double weightedForecast;
  final double wonValue;
  final int totalOpenDeals;

  PipelineStageSummary? forStage(String stage) {
    for (final summary in stages) {
      if (summary.stage == stage) return summary;
    }
    return null;
  }

  factory PipelineSummary.fromJson(Map<String, dynamic> json) =>
      PipelineSummary(
        stages: (json['stages'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(PipelineStageSummary.fromJson)
                .toList() ??
            const [],
        openPipelineValue: (json['openPipelineValue'] as num?)?.toDouble() ?? 0,
        weightedForecast: (json['weightedForecast'] as num?)?.toDouble() ?? 0,
        wonValue: (json['wonValue'] as num?)?.toDouble() ?? 0,
        totalOpenDeals: (json['totalOpenDeals'] as num?)?.toInt() ?? 0,
      );
}

class CrmActivity {
  const CrmActivity({
    required this.id,
    required this.type,
    required this.subject,
    required this.activityDate,
    required this.completed,
    required this.systemGenerated,
    this.description,
    this.performedByName,
    this.createdAt,
  });

  final int id;
  final String type;
  final String subject;
  final String activityDate;
  final bool completed;

  /// Written by the backend rather than a person — a stage change, say. Shown
  /// differently so a rep can tell their own notes from the audit trail.
  final bool systemGenerated;

  final String? description;
  final String? performedByName;
  final String? createdAt;

  factory CrmActivity.fromJson(Map<String, dynamic> json) => CrmActivity(
        id: (json['id'] as num?)?.toInt() ?? 0,
        type: json['type'] as String? ?? 'NOTE',
        subject: json['subject'] as String? ?? '',
        activityDate: json['activityDate'] as String? ??
            json['createdAt'] as String? ??
            '',
        completed: json['completed'] as bool? ?? false,
        systemGenerated: json['systemGenerated'] as bool? ?? false,
        description: json['description'] as String?,
        performedByName: json['performedByName'] as String?,
        createdAt: json['createdAt'] as String?,
      );
}

class Client {
  const Client({
    required this.id,
    required this.status,
    required this.createdAt,
    this.firstName,
    this.lastName,
    this.email,
    this.phone,
    this.clientCompanyName,
    this.industry,
    this.website,
    this.portalAccessEnabled,
    this.accountManagerName,
    this.onboardedAt,
    this.employeeCount,
    this.annualRevenue,
    this.lifetimeValue,
    this.totalRequests,
    this.tags = const [],
  });

  final int id;
  final String status;
  final String createdAt;
  final String? firstName;
  final String? lastName;
  final String? email;
  final String? phone;
  final String? clientCompanyName;
  final String? industry;
  final String? website;
  final bool? portalAccessEnabled;
  final String? accountManagerName;
  final String? onboardedAt;
  final int? employeeCount;
  final double? annualRevenue;
  final double? lifetimeValue;
  final int? totalRequests;
  final List<Tag> tags;

  String get contactName => [firstName, lastName]
      .where((part) => part != null && part.trim().isNotEmpty)
      .join(' ')
      .trim();

  /// The account is the company where there is one; otherwise the person.
  String get headline {
    final company = clientCompanyName?.trim();
    if (company != null && company.isNotEmpty) return company;
    final contact = contactName;
    return contact.isNotEmpty ? contact : (email ?? 'Client #$id');
  }

  String? get subline {
    final company = clientCompanyName?.trim();
    if (company != null && company.isNotEmpty) {
      final contact = contactName;
      return contact.isNotEmpty ? contact : email;
    }
    return email;
  }

  String get initials {
    final source = headline.trim();
    if (source.isEmpty) return '?';
    final parts = source.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  factory Client.fromJson(Map<String, dynamic> json) => Client(
        id: (json['id'] as num?)?.toInt() ?? 0,
        status: json['status'] as String? ?? 'ACTIVE',
        createdAt: json['createdAt'] as String? ?? '',
        firstName: json['firstName'] as String?,
        lastName: json['lastName'] as String?,
        email: json['email'] as String?,
        phone: json['phone'] as String?,
        clientCompanyName: json['clientCompanyName'] as String?,
        industry: json['industry'] as String?,
        website: json['website'] as String?,
        portalAccessEnabled: json['portalAccessEnabled'] as bool?,
        accountManagerName: json['accountManagerName'] as String?,
        onboardedAt: json['onboardedAt'] as String?,
        employeeCount: (json['employeeCount'] as num?)?.toInt(),
        annualRevenue: (json['annualRevenue'] as num?)?.toDouble(),
        lifetimeValue: (json['lifetimeValue'] as num?)?.toDouble(),
        totalRequests: (json['totalRequests'] as num?)?.toInt(),
        tags: Tag.listFrom(json['tagList']),
      );
}

/// PATCH /crm/leads/{id}/convert-to-opportunity
class ConvertLeadRequest {
  const ConvertLeadRequest({
    required this.opportunityName,
    required this.expectedValue,
    required this.expectedCloseDate,
  });

  final String opportunityName;
  final double expectedValue;

  /// `yyyy-MM-dd`.
  final String expectedCloseDate;

  Map<String, dynamic> toJson() => {
        'opportunityName': opportunityName.trim(),
        'expectedValue': expectedValue,
        'expectedCloseDate': expectedCloseDate,
      };
}

/// PATCH /crm/opportunities/{id}/stage
class ChangeStageRequest {
  const ChangeStageRequest({
    required this.stage,
    this.lostReasonCode,
    this.lostReason,
    this.linkToExistingClientId,
    this.forceCreateNewClient,
  });

  final String stage;
  final String? lostReasonCode;
  final String? lostReason;

  /// Winning a client-less deal: attach it to this existing client…
  final int? linkToExistingClientId;

  /// …or tell the backend to make a new one anyway.
  final bool? forceCreateNewClient;

  Map<String, dynamic> toJson() => {
        'stage': stage,
        if (lostReasonCode != null) 'lostReasonCode': lostReasonCode,
        if (lostReason != null && lostReason!.trim().isNotEmpty)
          'lostReason': lostReason!.trim(),
        if (linkToExistingClientId != null)
          'linkToExistingClientId': linkToExistingClientId,
        if (forceCreateNewClient != null)
          'forceCreateNewClient': forceCreateNewClient,
      };
}

/// POST /crm/leads
class CreateLeadRequest {
  const CreateLeadRequest({
    required this.contactName,
    required this.source,
    this.companyName,
    this.email,
    this.phone,
    this.jobTitle,
    this.priority,
    this.estimatedValue,
    this.notes,
  });

  final String contactName;
  final String source;
  final String? companyName;
  final String? email;
  final String? phone;
  final String? jobTitle;
  final String? priority;
  final double? estimatedValue;
  final String? notes;

  Map<String, dynamic> toJson() {
    String? clean(String? value) {
      final trimmed = value?.trim();
      return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    }

    return {
      'contactName': contactName.trim(),
      'source': source,
      if (clean(companyName) != null) 'companyName': clean(companyName),
      if (clean(email) != null) 'email': clean(email),
      if (clean(phone) != null) 'phone': clean(phone),
      if (clean(jobTitle) != null) 'jobTitle': clean(jobTitle),
      if (priority != null) 'priority': priority,
      if (estimatedValue != null) 'estimatedValue': estimatedValue,
      if (clean(notes) != null) 'notes': clean(notes),
    };
  }
}

/// POST /crm/leads/{id}/activities
class LogActivityRequest {
  const LogActivityRequest({
    required this.type,
    required this.subject,
    this.description,
  });

  final String type;
  final String subject;
  final String? description;

  Map<String, dynamic> toJson() => {
        'type': type,
        'subject': subject.trim(),
        if (description != null && description!.trim().isNotEmpty)
          'description': description!.trim(),
        // Logging something that already happened; a scheduled follow-up is a
        // different flow the web app owns.
        'completed': true,
      };
}
