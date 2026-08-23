/// Who may start a context switch, and end one — the `@PreAuthorize` on
/// `SupportContextSwitchController`'s write endpoints.
///
/// Note who is *missing*: SYSTEM_ADMIN. Impersonation allows it and this does
/// not, so the two features cannot share a role list however similar they look.
const contextSwitchRoles = <String>[
  'SUPER_ADMIN',
  'SUPPORT_MANAGER',
  'SUPPORT_AGENT',
];

/// Who may see other people's switches — the live board, an agent's history,
/// and a single record by id.
///
/// A support agent can declare their own work but cannot read anybody's back,
/// including their own history. Anything built on the wider list above would
/// 403 for exactly the people who use this feature most.
const contextSwitchReviewRoles = <String>[
  'SUPER_ADMIN',
  'SUPPORT_MANAGER',
];

/// A record that a member of support staff was looking at a customer's company.
///
/// The thing to be clear about: this grants **no access at all**. Unlike
/// impersonation there is no token — the agent's own session is unchanged and
/// tenant endpoints still refuse it. A switch is a declaration of what someone
/// is working on, and the row is the accountability. Treating it as a way "in"
/// would be a misreading with security-shaped consequences.
class SupportContextSwitch {
  const SupportContextSwitch({
    required this.id,
    required this.supportAgentId,
    required this.viewedCompanyId,
    required this.stillActive,
    this.supportAgentName,
    this.viewedCompanyName,
    this.switchedInTime,
    this.switchedOutTime,
    this.purpose,
    this.ipAddress,
    this.userAgent,
  });

  final int id;
  final int supportAgentId;
  final int viewedCompanyId;
  final bool stillActive;
  final String? supportAgentName;
  final String? viewedCompanyName;
  final String? switchedInTime;
  final String? switchedOutTime;
  final String? purpose;

  /// Both derived server-side from the request, never sent by the client —
  /// the record exists to hold someone accountable, so it must not be
  /// something they can write.
  final String? ipAddress;
  final String? userAgent;

  String get companyLabel =>
      viewedCompanyName?.trim().isNotEmpty == true
          ? viewedCompanyName!.trim()
          : 'Company #$viewedCompanyId';

  String get agentLabel => supportAgentName?.trim().isNotEmpty == true
      ? supportAgentName!.trim()
      : 'Agent #$supportAgentId';

  bool get hasPurpose => purpose?.trim().isNotEmpty == true;

  /// How long the switch ran, or has been running. Null when the start stamp
  /// is unreadable — better to show nothing than to invent a duration.
  Duration? get elapsed {
    final start = DateTime.tryParse(switchedInTime ?? '');
    if (start == null) return null;
    final end = stillActive
        ? DateTime.now()
        : DateTime.tryParse(switchedOutTime ?? '');
    if (end == null) return null;
    final span = end.difference(start);
    return span.isNegative ? Duration.zero : span;
  }

  /// Compact and human: `4m`, `2h 10m`, `3d`.
  String? get elapsedLabel {
    final span = elapsed;
    if (span == null) return null;
    if (span.inMinutes < 1) return 'just now';
    if (span.inHours < 1) return '${span.inMinutes}m';
    if (span.inDays < 1) {
      final minutes = span.inMinutes % 60;
      return minutes == 0 ? '${span.inHours}h' : '${span.inHours}h ${minutes}m';
    }
    return '${span.inDays}d';
  }

  /// A switch left open far longer than a shift is almost certainly one
  /// somebody forgot to end rather than work still in progress — and a stale
  /// "currently viewing" row is worse than none, because it is believed.
  bool get looksForgotten {
    final span = elapsed;
    return stillActive && span != null && span.inHours >= 8;
  }

  factory SupportContextSwitch.fromJson(Map<String, dynamic> json) =>
      SupportContextSwitch(
        id: (json['id'] as num?)?.toInt() ?? 0,
        supportAgentId: (json['supportAgentId'] as num?)?.toInt() ?? 0,
        viewedCompanyId: (json['viewedCompanyId'] as num?)?.toInt() ?? 0,
        stillActive: json['stillActive'] as bool? ?? false,
        supportAgentName: json['supportAgentName'] as String?,
        viewedCompanyName: json['viewedCompanyName'] as String?,
        switchedInTime: json['switchedInTime'] as String?,
        switchedOutTime: json['switchedOutTime'] as String?,
        purpose: json['purpose'] as String?,
        ipAddress: json['ipAddress'] as String?,
        userAgent: json['userAgent'] as String?,
      );
}
