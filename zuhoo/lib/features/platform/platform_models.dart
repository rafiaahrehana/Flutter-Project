/// Roles that make someone platform staff rather than a tenant's employee.
/// Mirrors `platformRoles` in the auth models — the same list, from the other
/// side: there it decides who *is* staff, here it is what you assign them.
const assignablePlatformRoles = <String>[
  'SUPER_ADMIN',
  'SYSTEM_ADMIN',
  'SUPPORT_AGENT',
  'SUPPORT_MANAGER',
  'MARKETING_MANAGER',
  'PLATFORM_ACCOUNTANT',
  'SALES_MANAGER',
];

/// Who may read the platform staff directory — `PlatformUserController`'s
/// class-level gate, and much narrower than the console that contains it.
/// Sales, support and accounting reach the console but not this list.
const platformUserRoles = <String>[
  'SUPER_ADMIN',
  'SYSTEM_ADMIN',
];

/// Who may suspend, reactivate or deactivate a tenant.
/// `CompanyController.changeStatus` — note that sales cannot, though they can
/// move a company between plans.
const companyStatusRoles = <String>[
  'SUPER_ADMIN',
  'SYSTEM_ADMIN',
  'PLATFORM_ACCOUNTANT',
];

/// Who may move a tenant onto another plan. `CompanyController.changePlan` —
/// sales can, support cannot. Every one of these lists differs from the next
/// by a role or two, which is exactly why they are written out rather than
/// approximated with a single "is this an admin" check.
const companyPlanRoles = <String>[
  'SUPER_ADMIN',
  'SYSTEM_ADMIN',
  'SALES_MANAGER',
  'PLATFORM_ACCOUNTANT',
];

/// Roles the backend lets start an impersonation session — the class-level
/// `@PreAuthorize` on `ImpersonationController`. Deliberately narrower than
/// platform staff: marketing, accounting and sales have no route into a
/// tenant's live data, so they must not be offered one.
const impersonationRoles = <String>[
  'SUPER_ADMIN',
  'SYSTEM_ADMIN',
  'SUPPORT_AGENT',
  'SUPPORT_MANAGER',
];

/// Who may read the audit trail back. Narrower still — a support agent can
/// open a session but cannot review everybody else's, which is the same
/// "review who did what" restriction the context-switch history uses.
const impersonationHistoryRoles = <String>[
  'SUPER_ADMIN',
  'SYSTEM_ADMIN',
  'SUPPORT_MANAGER',
];

abstract final class CompanyStatus {
  static const pendingVerification = 'PENDING_VERIFICATION';
  static const trial = 'TRIAL';
  static const active = 'ACTIVE';
  static const suspended = 'SUSPENDED';
  static const deactivated = 'DEACTIVATED';

  static const all = [
    pendingVerification,
    trial,
    active,
    suspended,
    deactivated,
  ];

  /// Still transacting. A suspended or deactivated tenant is not.
  static const live = {trial, active};
}

/// A tenant.
class Company {
  const Company({
    required this.id,
    required this.companyName,
    required this.subdomain,
    required this.status,
    required this.subscriptionPlan,
    required this.trialExpired,
    required this.createdAt,
    this.companyEmail,
    this.companyPhone,
    this.website,
    this.tagline,
    this.subscriptionStart,
    this.subscriptionEnd,
    this.ownerName,
    this.ownerEmail,
    this.location,
  });

  final int id;
  final String companyName;

  /// Their slice of the product — `{subdomain}.…`. Unique across the platform.
  final String subdomain;

  final String status;

  /// A free-form plan key, not a fixed enum: plans are defined as data in
  /// subscription management, so new ones appear without a code change.
  final String subscriptionPlan;

  final bool trialExpired;
  final String createdAt;
  final String? companyEmail;
  final String? companyPhone;
  final String? website;
  final String? tagline;
  final String? subscriptionStart;
  final String? subscriptionEnd;
  final String? ownerName;
  final String? ownerEmail;
  final String? location;

  bool get isLive => CompanyStatus.live.contains(status);
  bool get isSuspended => status == CompanyStatus.suspended;
  bool get isDeactivated => status == CompanyStatus.deactivated;

  /// On trial and out of time — the ones sales should be calling.
  bool get needsAttention => status == CompanyStatus.trial && trialExpired;

  /// Days until the subscription lapses. Negative once it has, null when there
  /// is no end date — a perpetual plan has nothing to count down to, and zero
  /// would read as "expires today".
  int? get daysUntilExpiry {
    final end = subscriptionEnd;
    if (end == null) return null;
    final date = DateTime.tryParse(end);
    if (date == null) return null;
    final today = DateTime.now();
    return DateTime(date.year, date.month, date.day)
        .difference(DateTime(today.year, today.month, today.day))
        .inDays;
  }

  /// Live, with the subscription lapsing inside a month.
  bool get expiringSoon {
    final days = daysUntilExpiry;
    return isLive && days != null && days >= 0 && days <= 30;
  }

  factory Company.fromJson(Map<String, dynamic> json) => Company(
        id: (json['id'] as num?)?.toInt() ?? 0,
        companyName: json['companyName'] as String? ?? '',
        subdomain: json['subdomain'] as String? ?? '',
        status: json['status'] as String? ?? CompanyStatus.active,
        subscriptionPlan: json['subscriptionPlan'] as String? ?? '',
        trialExpired: json['trialExpired'] as bool? ?? false,
        createdAt: json['createdAt'] as String? ?? '',
        companyEmail: json['companyEmail'] as String?,
        companyPhone: json['companyPhone'] as String?,
        website: json['website'] as String?,
        tagline: json['tagline'] as String?,
        subscriptionStart: json['subscriptionStart'] as String?,
        subscriptionEnd: json['subscriptionEnd'] as String?,
        ownerName: json['ownerName'] as String?,
        ownerEmail: json['ownerEmail'] as String?,
        location: json['location'] as String?,
      );
}

/// A switch that turns part of the product on or off platform-wide.
class FeatureFlag {
  const FeatureFlag({
    required this.id,
    required this.flagKey,
    required this.enabled,
    this.description,
    this.updatedAt,
  });

  final int id;
  final String flagKey;
  final bool enabled;
  final String? description;
  final String? updatedAt;

  /// `AI_ASSISTANT_ENABLED` → `AI assistant enabled`.
  ///
  /// Sentence case, not Title Case: a column of Capitalised Words is harder to
  /// read than a column of sentences. Short segments are left in capitals so
  /// acronyms survive — `AI`, `SMS`, `API`, `PDF` all become nonsense words
  /// otherwise, and "Ai assistant" is the kind of thing that looks like a typo
  /// in the product rather than a formatting rule.
  String get label {
    final words = flagKey.split('_').where((word) => word.isNotEmpty).toList();
    if (words.isEmpty) return flagKey;

    String render(String word) =>
        word.length <= 3 ? word.toUpperCase() : word.toLowerCase();

    final first = render(words.first);
    return [
      // Only capitalise the opener when it is not already an acronym.
      first.length <= 3 ? first : first[0].toUpperCase() + first.substring(1),
      ...words.skip(1).map(render),
    ].join(' ');
  }

  FeatureFlag toggled() => FeatureFlag(
        id: id,
        flagKey: flagKey,
        enabled: !enabled,
        description: description,
        updatedAt: updatedAt,
      );

  factory FeatureFlag.fromJson(Map<String, dynamic> json) => FeatureFlag(
        id: (json['id'] as num?)?.toInt() ?? 0,
        flagKey: json['flagKey'] as String? ?? '',
        enabled: json['enabled'] as bool? ?? false,
        description: json['description'] as String?,
        updatedAt: json['updatedAt'] as String?,
      );
}

class PlatformUser {
  const PlatformUser({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.role,
    required this.active,
    required this.emailVerified,
    required this.createdAt,
    this.phone,
  });

  final int id;
  final String firstName;
  final String lastName;
  final String email;
  final String role;
  final bool active;
  final bool emailVerified;
  final String createdAt;
  final String? phone;

  String get fullName => '$firstName $lastName'.trim();

  String get initials {
    final f = firstName.trim();
    final l = lastName.trim();
    if (f.isEmpty && l.isEmpty) {
      return email.isEmpty ? '?' : email[0].toUpperCase();
    }
    if (l.isEmpty) return f[0].toUpperCase();
    if (f.isEmpty) return l[0].toUpperCase();
    return (f[0] + l[0]).toUpperCase();
  }

  /// An account that exists but cannot be used yet — worth flagging, because
  /// it looks identical to a working one in a list otherwise.
  bool get isUnusable => !active || !emailVerified;

  factory PlatformUser.fromJson(Map<String, dynamic> json) => PlatformUser(
        id: (json['id'] as num?)?.toInt() ?? 0,
        firstName: json['firstName'] as String? ?? '',
        lastName: json['lastName'] as String? ?? '',
        email: json['email'] as String? ?? '',
        role: json['role'] as String? ?? '',
        active: json['active'] as bool? ?? true,
        emailVerified: json['emailVerified'] as bool? ?? false,
        createdAt: json['createdAt'] as String? ?? '',
        phone: json['phone'] as String?,
      );
}

/// A plan a company can be moved onto. Defined as data, so the list comes from
/// the server rather than a constant here.
class SubscriptionPlanOption {
  const SubscriptionPlanOption({
    required this.key,
    required this.name,
    this.price,
    this.billingCycle,
  });

  final String key;
  final String name;
  final double? price;
  final String? billingCycle;

  factory SubscriptionPlanOption.fromJson(Map<String, dynamic> json) {
    // The definition endpoint has used a couple of spellings for the key;
    // accept either rather than silently offering a blank plan.
    final key = json['planKey'] as String? ??
        json['key'] as String? ??
        json['name'] as String? ??
        '';
    return SubscriptionPlanOption(
      key: key,
      name: json['name'] as String? ?? key,
      price: (json['price'] as num?)?.toDouble(),
      billingCycle: json['billingCycle'] as String?,
    );
  }
}
