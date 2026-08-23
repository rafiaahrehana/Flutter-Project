import 'package:flutter_test/flutter_test.dart';
import 'package:zuhoo/core/auth/auth_models.dart';
import 'package:zuhoo/features/platform/platform_models.dart';

/// The operator console acts across tenants: a wrong status transition cuts a
/// paying customer off, and a wrong role check hands the tenant list to someone
/// who works for one of them.
void main() {
  Company company({
    String status = CompanyStatus.active,
    bool trialExpired = false,
    String? end,
  }) =>
      Company(
        id: 1,
        companyName: 'Dhrubotara Ltd',
        subdomain: 'dhrubotara',
        status: status,
        subscriptionPlan: 'PRO',
        trialExpired: trialExpired,
        createdAt: '2026-01-01T00:00:00',
        subscriptionEnd: end,
      );

  String iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  group('Company', () {
    test('live means trialing or active, nothing else', () {
      expect(company(status: CompanyStatus.active).isLive, isTrue);
      expect(company(status: CompanyStatus.trial).isLive, isTrue);
      expect(company(status: CompanyStatus.suspended).isLive, isFalse);
      expect(company(status: CompanyStatus.deactivated).isLive, isFalse);
      expect(company(status: CompanyStatus.pendingVerification).isLive, isFalse);
    });

    test('needs attention only while still on an expired trial', () {
      // Someone who has since paid is not a sales lead.
      expect(
        company(status: CompanyStatus.trial, trialExpired: true).needsAttention,
        isTrue,
      );
      expect(
        company(status: CompanyStatus.trial).needsAttention,
        isFalse,
      );
      expect(
        company(status: CompanyStatus.active, trialExpired: true).needsAttention,
        isFalse,
      );
    });

    test('a perpetual plan has no countdown', () {
      // Null, not zero — zero would render as "ends today".
      expect(company().daysUntilExpiry, isNull);
      expect(company().expiringSoon, isFalse);
    });

    test('expiring soon is a live subscription inside a month', () {
      final soon = iso(DateTime.now().add(const Duration(days: 10)));
      final later = iso(DateTime.now().add(const Duration(days: 90)));
      final gone = iso(DateTime.now().subtract(const Duration(days: 5)));

      expect(company(end: soon).expiringSoon, isTrue);
      expect(company(end: later).expiringSoon, isFalse);
      expect(company(end: gone).expiringSoon, isFalse,
          reason: 'already lapsed is a different problem from lapsing');
      expect(company(status: CompanyStatus.suspended, end: soon).expiringSoon,
          isFalse,
          reason: 'a suspended tenant is not counting down to anything');
    });

    test('parses a tenant row', () {
      final parsed = Company.fromJson(const {
        'id': 11,
        'companyName': 'Dhrubotara Ltd',
        'subdomain': 'dhrubotara',
        'status': 'TRIAL',
        'subscriptionPlan': 'STARTER',
        'trialExpired': true,
        'ownerName': 'Tanvir Ahmed',
      });
      expect(parsed.subdomain, 'dhrubotara');
      expect(parsed.needsAttention, isTrue);
      expect(parsed.ownerName, 'Tanvir Ahmed');
    });
  });

  group('FeatureFlag', () {
    const flag = FeatureFlag(id: 1, flagKey: 'AI_ASSISTANT_ENABLED', enabled: false);

    test('the key is made readable, and acronyms survive', () {
      // Sentence case reads better in a column than Title Case, and short
      // segments stay capitalised so AI/SMS/API do not become words.
      expect(flag.label, 'AI assistant enabled');
      expect(
        const FeatureFlag(id: 1, flagKey: 'CLIENT_PORTAL_ENABLED', enabled: true)
            .label,
        'Client portal enabled',
      );
      expect(
        const FeatureFlag(id: 1, flagKey: 'SMS_NOTIFICATIONS', enabled: true).label,
        'SMS notifications',
      );
    });

    test('toggling flips only the value', () {
      final flipped = flag.toggled();
      expect(flipped.enabled, isTrue);
      expect(flipped.flagKey, flag.flagKey);
      expect(flipped.id, flag.id);
      expect(flipped.toggled().enabled, isFalse);
    });
  });

  group('PlatformUser', () {
    PlatformUser user({bool active = true, bool verified = true}) => PlatformUser(
          id: 1,
          firstName: 'Rehana',
          lastName: 'Akter',
          email: 'r@zuhoo.example',
          role: 'SUPPORT_AGENT',
          active: active,
          emailVerified: verified,
          createdAt: '2026-01-01T00:00:00',
        );

    test('an account is unusable if deactivated or unverified', () {
      // Both look identical to a working account in a list otherwise.
      expect(user().isUnusable, isFalse);
      expect(user(active: false).isUnusable, isTrue);
      expect(user(verified: false).isUnusable, isTrue);
    });

    test('initials fall back to the email when there is no name', () {
      final nameless = PlatformUser.fromJson(const {
        'id': 1,
        'email': 'ops@zuhoo.example',
      });
      expect(nameless.initials, 'O');
    });
  });

  group('SubscriptionPlanOption', () {
    test('accepts either spelling of the key', () {
      // The definition endpoint has used more than one; a blank key would put
      // an unselectable plan in the picker.
      expect(SubscriptionPlanOption.fromJson(const {'planKey': 'PRO'}).key, 'PRO');
      expect(SubscriptionPlanOption.fromJson(const {'key': 'PRO'}).key, 'PRO');
      expect(SubscriptionPlanOption.fromJson(const {'name': 'Pro'}).key, 'Pro');
      expect(SubscriptionPlanOption.fromJson(const {}).key, '');
    });
  });

  group('assignablePlatformRoles', () {
    test('contains only platform roles, never tenant ones', () {
      // Offering COMPANY_OWNER or EMPLOYEE here would create a platform staff
      // account with a tenant's role — a category error the backend would then
      // have to sort out.
      expect(assignablePlatformRoles, contains('SUPER_ADMIN'));
      expect(assignablePlatformRoles, contains('SUPPORT_AGENT'));
      expect(assignablePlatformRoles, isNot(contains('COMPANY_OWNER')));
      expect(assignablePlatformRoles, isNot(contains('EMPLOYEE')));
      expect(assignablePlatformRoles, isNot(contains('CLIENT')));
    });
  });

  _roleGateTests();
}

/// Every console action has its own backend gate, and they genuinely differ —
/// by one or two roles each. The bug this guards against is the tempting
/// simplification: one "is this an admin" check standing in for six lists,
/// which either hides an action from someone entitled to it or offers one the
/// server will refuse.
///
/// Transcribed from the `@PreAuthorize` annotations on `CompanyController`,
/// `PlatformUserController` and `ImpersonationController`.
void _roleGateTests() {
  group('console role gates', () {
    test('the staff directory is narrower than the console around it', () {
      expect(platformUserRoles, ['SUPER_ADMIN', 'SYSTEM_ADMIN']);
      for (final role in platformUserRoles) {
        expect(platformRoles, contains(role));
      }
      expect(
        platformUserRoles,
        isNot(contains('SUPPORT_MANAGER')),
        reason: 'support reaches the console but not the staff list',
      );
    });

    test('sales may change a plan but never a status', () {
      expect(companyPlanRoles, contains('SALES_MANAGER'));
      expect(
        companyStatusRoles,
        isNot(contains('SALES_MANAGER')),
        reason: 'suspending a customer is not a sales action',
      );
    });

    test('support may impersonate but may not change plan or status', () {
      expect(impersonationRoles, contains('SUPPORT_AGENT'));
      expect(companyPlanRoles, isNot(contains('SUPPORT_AGENT')));
      expect(companyStatusRoles, isNot(contains('SUPPORT_AGENT')));
    });

    test('accounting may change plan and status but not impersonate', () {
      expect(companyPlanRoles, contains('PLATFORM_ACCOUNTANT'));
      expect(companyStatusRoles, contains('PLATFORM_ACCOUNTANT'));
      expect(
        impersonationRoles,
        isNot(contains('PLATFORM_ACCOUNTANT')),
        reason: 'accounting has no route into a tenant account',
      );
    });

    test('marketing reaches the console and can do nothing in it', () {
      // Not a mistake to fix in the app — the backend grants MARKETING_MANAGER
      // the company list and nothing else. The card must therefore render with
      // no action row rather than with buttons that 403.
      const marketing = 'MARKETING_MANAGER';
      expect(platformRoles, contains(marketing));
      expect(companyPlanRoles, isNot(contains(marketing)));
      expect(companyStatusRoles, isNot(contains(marketing)));
      expect(impersonationRoles, isNot(contains(marketing)));
      expect(platformUserRoles, isNot(contains(marketing)));
    });

    test('every gate is a subset of platform staff', () {
      for (final list in [
        platformUserRoles,
        companyStatusRoles,
        companyPlanRoles,
        impersonationRoles,
        impersonationHistoryRoles,
      ]) {
        for (final role in list) {
          expect(
            platformRoles,
            contains(role),
            reason: '$role would be gated out of the console entirely',
          );
        }
      }
    });
  });
}
