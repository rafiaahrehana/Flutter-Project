import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/auth_controller.dart';
import '../features/alerts/alerts_screen.dart';
import '../features/attendance/attendance_screen.dart';
import '../features/auth/forgot_password_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/home/home_screen.dart';
import '../features/leave/leave_screen.dart';
import '../features/payslips/payslips_screen.dart';
import '../features/requests/requests_screen.dart';
import '../features/crm/crm_screen.dart';
import '../features/directory/directory_screen.dart';
import '../features/finance/finance_screen.dart';
import '../features/itam/itam_screen.dart';
import '../features/performance/performance_screen.dart';
import '../features/search/search_screen.dart';
import '../features/recruitment/recruitment_screen.dart';
import '../features/platform/platform_screen.dart';
import '../features/support/support_screen.dart';
import '../features/profile/appearance_screen.dart';
import '../features/profile/change_password_screen.dart';
import '../features/profile/edit_profile_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/portal/portal_billing_screen.dart';
import '../features/portal/portal_home_screen.dart';
import '../features/portal/portal_profile_screen.dart';
import '../features/portal/portal_requests_screen.dart';
import '../features/portal/portal_tickets_screen.dart';
import 'portal_shell.dart';
import 'shell.dart';
import 'splash_screen.dart';

/// Route names, so no screen has to spell a path out.
abstract final class Routes {
  static const splash = '/splash';
  static const login = '/login';
  static const forgotPassword = '/forgot-password';

  static const home = '/';
  static const attendance = '/attendance';
  static const leave = '/leave';
  static const alerts = '/alerts';
  static const profile = '/me';

  static const payslips = '/payslips';
  static const requests = '/requests';
  static const support = '/support';
  static const crm = '/crm';
  static const finance = '/finance';
  static const platform = '/platform';
  static const directory = '/people';
  static const itam = '/assets';
  static const recruitment = '/hiring';
  static const performance = '/performance';
  static const search = '/search';
  static const appearance = '/me/appearance';
  static const editProfile = '/me/edit';
  static const changePassword = '/me/password';
}

/// The client portal's own routes.
///
/// Kept under one prefix so the redirect can tell the two apps apart by path
/// alone: everything under `/client` belongs to a portal client, everything
/// else to staff.
abstract final class PortalRoutes {
  static const prefix = '/client';

  static const home = '/client';
  static const requests = '/client/requests';
  static const billing = '/client/billing';
  static const help = '/client/help';
  static const account = '/client/account';
}

/// Bridges the auth provider to GoRouter, which wants a [Listenable].
class _AuthRefresh extends ChangeNotifier {
  void ping() => notifyListeners();
}

final _routerRefreshProvider = Provider<_AuthRefresh>((ref) {
  final refresh = _AuthRefresh();
  ref.onDispose(refresh.dispose);
  return refresh;
});

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ref.watch(_routerRefreshProvider);

  // Signing in or out has to re-run the redirect below, otherwise the user
  // stays on the login screen after a successful sign-in.
  ref.listen(authControllerProvider, (_, _) => refresh.ping());

  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final location = state.matchedLocation;

      final atSplash = location == Routes.splash;
      final atAuth = location == Routes.login ||
          location.startsWith(Routes.forgotPassword);

      // Still reading the stored session. Anything else would flash a screen
      // the user may not be entitled to and then yank it away.
      if (auth.isLoading) return atSplash ? null : Routes.splash;

      final user = auth.value;
      if (user == null) return atAuth ? null : Routes.login;

      // Two apps, one binary. A CLIENT gets the portal, everyone else the
      // staff shell, and neither can wander into the other's half — a client
      // landing on the attendance tab would be shown a check-in button the
      // backend would refuse, and a staff account in the portal would hit the
      // client-scoped endpoints that 400 for them.
      final wantsPortal = user.isClient;
      final inPortal = location.startsWith(PortalRoutes.prefix);

      if (atAuth || atSplash) {
        return wantsPortal ? PortalRoutes.home : Routes.home;
      }
      if (wantsPortal && !inPortal) return PortalRoutes.home;
      if (!wantsPortal && inPortal) return Routes.home;
      return null;
    },
    routes: [
      GoRoute(
        path: Routes.splash,
        builder: (_, _) => const SplashScreen(),
      ),
      GoRoute(
        path: Routes.login,
        builder: (_, _) => const LoginScreen(),
      ),
      GoRoute(
        path: Routes.forgotPassword,
        builder: (_, _) => const ForgotPasswordScreen(),
      ),

      // Full-screen pushes that sit above the tab bar, because each is a task
      // you finish and back out of rather than a place you dwell in.
      GoRoute(
        path: Routes.payslips,
        builder: (_, _) => const PayslipsScreen(),
      ),
      GoRoute(
        path: Routes.requests,
        builder: (_, _) => const RequestsScreen(),
      ),
      GoRoute(
        path: Routes.support,
        builder: (_, _) => const SupportScreen(),
      ),
      GoRoute(
        path: Routes.crm,
        builder: (_, _) => const CrmScreen(),
      ),
      GoRoute(
        path: Routes.finance,
        builder: (_, _) => const FinanceScreen(),
      ),
      GoRoute(
        path: Routes.search,
        builder: (_, _) => const SearchScreen(),
      ),
      GoRoute(
        path: Routes.performance,
        builder: (_, _) => const PerformanceScreen(),
      ),
      GoRoute(
        path: Routes.recruitment,
        builder: (_, _) => const RecruitmentScreen(),
      ),
      GoRoute(
        path: Routes.itam,
        builder: (_, _) => const ItamScreen(),
      ),
      GoRoute(
        path: Routes.directory,
        builder: (_, _) => const DirectoryScreen(),
      ),
      GoRoute(
        path: Routes.platform,
        builder: (_, _) => const PlatformScreen(),
      ),
      GoRoute(
        path: Routes.appearance,
        builder: (_, _) => const AppearanceScreen(),
      ),
      GoRoute(
        path: Routes.editProfile,
        builder: (_, _) => const EditProfileScreen(),
      ),
      GoRoute(
        path: Routes.changePassword,
        builder: (_, _) => const ChangePasswordScreen(),
      ),

      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: Routes.home, builder: (_, _) => const HomeScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.attendance,
                builder: (_, _) => const AttendanceScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.leave,
                builder: (_, _) => const LeaveScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.alerts,
                builder: (_, _) => const AlertsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.profile,
                builder: (_, _) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),

      // The client portal: its own shell, its own five tabs, reached only by a
      // CLIENT. Kept as a sibling of the staff shell rather than a mode inside
      // it, so neither app's navigation has to know the other exists.
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            PortalShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: PortalRoutes.home,
                builder: (_, _) => const PortalHomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: PortalRoutes.requests,
                builder: (_, _) => const PortalRequestsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: PortalRoutes.billing,
                builder: (_, _) => const PortalBillingScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: PortalRoutes.help,
                builder: (_, _) => const PortalTicketsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: PortalRoutes.account,
                builder: (_, _) => const PortalProfileScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
