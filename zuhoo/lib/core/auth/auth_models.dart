import 'dart:convert';

import '../config/env.dart';

/// SaaS-provider staff roles, distinct from the company-scoped ones
/// (COMPANY_OWNER, EMPLOYEE, CLIENT). Mirrors the backend's
/// `User.isPlatformUser()` and the same list in Angular's AuthService.
const platformRoles = <String>{
  'SUPER_ADMIN',
  'SYSTEM_ADMIN',
  'SUPPORT_AGENT',
  'SUPPORT_MANAGER',
  'MARKETING_MANAGER',
  'PLATFORM_ACCOUNTANT',
  'SALES_MANAGER',
};

class LoginRequest {
  const LoginRequest({required this.email, required this.password});

  final String email;
  final String password;

  Map<String, dynamic> toJson() => {'email': email, 'password': password};
}

/// POST /api/auth/login response.
class LoginResponse {
  const LoginResponse({
    required this.userId,
    required this.firstName,
    required this.email,
    required this.role,
    required this.companyId,
    required this.accessToken,
    required this.refreshToken,
  });

  final int userId;
  final String firstName;
  final String email;
  final String role;
  final int? companyId;
  final String accessToken;
  final String? refreshToken;

  factory LoginResponse.fromJson(Map<String, dynamic> json) => LoginResponse(
        userId: (json['userId'] as num?)?.toInt() ?? 0,
        firstName: json['firstName'] as String? ?? '',
        email: json['email'] as String? ?? '',
        role: json['role'] as String? ?? '',
        companyId: (json['companyId'] as num?)?.toInt(),
        accessToken: json['accessToken'] as String? ?? '',
        refreshToken: json['refreshToken'] as String?,
      );
}

/// The signed-in user as the app holds it. Mirrors Angular's `User`.
class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.fullName,
    required this.roles,
    this.companyId,
    this.profileImageUrl,
  });

  final int id;
  final String email;
  final String fullName;
  final List<String> roles;
  final int? companyId;
  final String? profileImageUrl;

  bool get isPlatformStaff => roles.any(platformRoles.contains);
  bool get isClient => roles.contains('CLIENT');
  bool get isCompanyOwner => roles.contains('COMPANY_OWNER');

  bool hasRole(String role) => roles.contains(role);
  bool hasAnyRole(Iterable<String> candidates) => candidates.any(roles.contains);

  /// First name only, for greetings. `fullName` holds just the first name
  /// until the profile call lands and fills in the surname.
  String get displayFirstName {
    final trimmed = fullName.trim();
    if (trimmed.isEmpty) return email.split('@').first;
    return trimmed.split(RegExp(r'\s+')).first;
  }

  String get initials {
    final parts =
        fullName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return email.isEmpty ? '?' : email[0].toUpperCase();
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  AppUser copyWith({
    String? fullName,
    List<String>? roles,
    String? profileImageUrl,
    bool clearImage = false,
  }) =>
      AppUser(
        id: id,
        email: email,
        fullName: fullName ?? this.fullName,
        roles: roles ?? this.roles,
        companyId: companyId,
        profileImageUrl:
            clearImage ? null : (profileImageUrl ?? this.profileImageUrl),
      );

  factory AppUser.fromLogin(LoginResponse res) => AppUser(
        id: res.userId,
        email: res.email,
        fullName: res.firstName,
        roles: [res.role],
        companyId: res.companyId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'fullName': fullName,
        'roles': roles,
        'companyId': companyId,
        'profileImageUrl': profileImageUrl,
      };

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: (json['id'] as num?)?.toInt() ?? 0,
        email: json['email'] as String? ?? '',
        fullName: json['fullName'] as String? ?? '',
        roles:
            (json['roles'] as List?)?.whereType<String>().toList() ?? const [],
        companyId: (json['companyId'] as num?)?.toInt(),
        profileImageUrl: json['profileImageUrl'] as String?,
      );
}

/// The user's own account record from GET /api/users/profile.
class UserProfile {
  const UserProfile({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    this.phone,
    this.role,
    this.image,
  });

  final int id;
  final String firstName;
  final String lastName;
  final String email;
  final String? phone;
  final String? role;
  final String? image;

  String get fullName => '$firstName $lastName'.trim();
  String? get imageUrl => Env.resolveImageUrl(image);

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        id: (json['id'] as num?)?.toInt() ?? 0,
        firstName: json['firstName'] as String? ?? '',
        lastName: json['lastName'] as String? ?? '',
        email: json['email'] as String? ?? '',
        phone: json['phone'] as String?,
        role: json['role'] as String?,
        image: json['image'] as String?,
      );
}

class ForgotPasswordRequest {
  const ForgotPasswordRequest(this.email);
  final String email;
  Map<String, dynamic> toJson() => {'email': email};
}

class VerifyResetCodeRequest {
  const VerifyResetCodeRequest({required this.email, required this.code});
  final String email;
  final String code;
  Map<String, dynamic> toJson() => {'email': email, 'code': code};
}

/// Two mutually-exclusive ways to authorise a reset, matching the backend:
/// email + code from the "forgot password" mail, or the long-lived `token`
/// from a client-portal invite link. Send only the one you have.
class ResetPasswordRequest {
  const ResetPasswordRequest({
    this.email,
    this.code,
    this.token,
    required this.newPassword,
    required this.confirmPassword,
  });

  final String? email;
  final String? code;
  final String? token;
  final String newPassword;
  final String confirmPassword;

  Map<String, dynamic> toJson() => {
        if (email != null) 'email': email,
        if (code != null) 'code': code,
        if (token != null) 'token': token,
        'newPassword': newPassword,
        'confirmPassword': confirmPassword,
      };
}

class ChangePasswordRequest {
  const ChangePasswordRequest({
    required this.currentPassword,
    required this.newPassword,
    required this.confirmPassword,
  });

  final String currentPassword;
  final String newPassword;
  final String confirmPassword;

  Map<String, dynamic> toJson() => {
        'currentPassword': currentPassword,
        'newPassword': newPassword,
        'confirmPassword': confirmPassword,
      };
}

/// Reads `exp` out of a JWT without verifying it.
///
/// Verification is the server's job — this only answers "is it worth sending?",
/// so a session restored from storage with a long-dead token goes straight to
/// the login screen instead of flashing a dashboard that then 401s.
class JwtPayload {
  const JwtPayload({
    required this.expiresAt,
    this.role,
    this.companyId,
    this.impersonatedBy,
    this.impersonationSessionId,
  });

  final DateTime expiresAt;
  final String? role;
  final int? companyId;

  /// The real admin behind an impersonation token. Present only on one,
  /// so it doubles as the answer to "is this a tenant token?" — taken from
  /// the token itself rather than from the app's own bookkeeping, which is
  /// what makes it usable as a cross-check on that bookkeeping.
  final int? impersonatedBy;
  final String? impersonationSessionId;

  bool get isImpersonation => impersonatedBy != null;

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  static JwtPayload? tryParse(String? token) {
    if (token == null || token.isEmpty) return null;
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final normalised = base64Url.normalize(parts[1]);
      final decoded = jsonDecode(utf8.decode(base64Url.decode(normalised)));
      if (decoded is! Map<String, dynamic>) return null;
      final exp = decoded['exp'];
      if (exp is! num) return null;
      return JwtPayload(
        expiresAt: DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000),
        role: decoded['role'] as String?,
        impersonatedBy: (decoded['impersonatedBy'] as num?)?.toInt(),
        impersonationSessionId:
            decoded['impersonationSessionId'] as String?,
        companyId: (decoded['companyId'] as num?)?.toInt(),
      );
    } catch (_) {
      return null;
    }
  }
}

/// POST /api/platform-admin/companies/{id}/impersonate response.
///
/// Note what is *not* here: a refresh token. An impersonated session lasts
/// exactly as long as this one token (30 minutes by default,
/// `jwt.impersonation-expiration-ms`) and then it is over.
class ImpersonationStart {
  const ImpersonationStart({
    required this.accessToken,
    required this.companyId,
    required this.companyName,
    required this.impersonationSessionId,
    required this.expiresInSeconds,
  });

  final String accessToken;
  final int companyId;
  final String companyName;
  final String impersonationSessionId;
  final int expiresInSeconds;

  factory ImpersonationStart.fromJson(Map<String, dynamic> json) =>
      ImpersonationStart(
        accessToken: json['accessToken'] as String? ?? '',
        companyId: (json['companyId'] as num?)?.toInt() ?? 0,
        companyName: json['companyName'] as String? ?? '',
        impersonationSessionId: json['impersonationSessionId'] as String? ?? '',
        // Falls back to the backend's own default rather than to zero: a
        // missing figure would otherwise read as "already expired" and end the
        // session on the first tick.
        expiresInSeconds: (json['expiresInSeconds'] as num?)?.toInt() ?? 1800,
      );
}

/// An impersonation session as the app tracks it while it is running.
class ImpersonationSession {
  const ImpersonationSession({
    required this.companyId,
    required this.companyName,
    required this.impersonationSessionId,
    required this.expiresAt,
    required this.adminEmail,
    this.reason,
  });

  final int companyId;
  final String companyName;
  final String impersonationSessionId;
  final DateTime expiresAt;

  /// Who is really behind the session. Kept so the banner can name them —
  /// the signed-in user has been replaced by the tenant identity by then.
  final String adminEmail;

  final String? reason;

  Duration get remaining {
    final left = expiresAt.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  bool get hasExpired => remaining == Duration.zero;

  /// mm:ss, for the countdown in the banner.
  ///
  /// Rounded up rather than truncated: a session with 4m05.9s left reads
  /// 04:06, and one just opened reads 30:00 instead of 29:59. Truncating
  /// shows a second less than there actually is, every second.
  String get remainingLabel {
    final total = (remaining.inMilliseconds / 1000).ceil();
    final minutes = (total ~/ 60).toString().padLeft(2, '0');
    final seconds = (total % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  factory ImpersonationSession.fromStart(
    ImpersonationStart start, {
    required String adminEmail,
    String? reason,
  }) =>
      ImpersonationSession(
        companyId: start.companyId,
        companyName: start.companyName,
        impersonationSessionId: start.impersonationSessionId,
        expiresAt:
            DateTime.now().add(Duration(seconds: start.expiresInSeconds)),
        adminEmail: adminEmail,
        reason: reason,
      );

  Map<String, dynamic> toJson() => {
        'companyId': companyId,
        'companyName': companyName,
        'impersonationSessionId': impersonationSessionId,
        'expiresAt': expiresAt.toIso8601String(),
        'adminEmail': adminEmail,
        'reason': reason,
      };

  static ImpersonationSession? tryFromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final expiresAt = DateTime.tryParse(json['expiresAt'] as String? ?? '');
    final sessionId = json['impersonationSessionId'] as String?;
    if (expiresAt == null || sessionId == null || sessionId.isEmpty) return null;
    return ImpersonationSession(
      companyId: (json['companyId'] as num?)?.toInt() ?? 0,
      companyName: json['companyName'] as String? ?? 'this company',
      impersonationSessionId: sessionId,
      expiresAt: expiresAt,
      adminEmail: json['adminEmail'] as String? ?? '',
      reason: json['reason'] as String?,
    );
  }
}

/// A row from GET /api/platform-admin/impersonate/history.
class ImpersonationAuditEntry {
  const ImpersonationAuditEntry({
    required this.id,
    required this.companyName,
    required this.adminName,
    required this.startedAt,
    this.reason,
    this.endedAt,
    this.companyId,
  });

  final int id;
  final String companyName;
  final String adminName;
  final String startedAt;
  final String? reason;
  final String? endedAt;
  final int? companyId;

  /// No end stamp. Either still running, or ended in a way that never reported
  /// it — the app was killed, the token simply expired. Both look the same in
  /// this table, so the label says "not ended" rather than "active".
  bool get openEnded => endedAt == null || endedAt!.isEmpty;

  factory ImpersonationAuditEntry.fromJson(Map<String, dynamic> json) =>
      ImpersonationAuditEntry(
        id: (json['id'] as num?)?.toInt() ?? 0,
        companyName: json['companyName'] as String? ?? 'Unknown company',
        adminName: json['adminName'] as String? ?? 'Unknown admin',
        startedAt: json['startedAt'] as String? ?? '',
        reason: json['reason'] as String?,
        endedAt: json['endedAt'] as String?,
        companyId: (json['companyId'] as num?)?.toInt(),
      );
}
