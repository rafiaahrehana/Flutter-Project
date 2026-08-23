import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/bos_tokens.dart';
import '../features/alerts/notification_repository.dart';

/// The signed-in frame: five tabs, each keeping its own navigation state.
///
/// Five destinations is the ceiling for a bottom bar — beyond that the labels
/// stop fitting and the targets get too small to hit reliably. The web app's
/// twelve nav groups do not translate; what does is the handful of things an
/// employee opens daily, with everything else reached from inside them.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final unread = ref.watch(unreadCountProvider);

    return Scaffold(
      backgroundColor: bos.bgPage,
      body: navigationShell,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: bos.border)),
        ),
        child: NavigationBar(
          selectedIndex: navigationShell.currentIndex,
          onDestinationSelected: _onTap,
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            const NavigationDestination(
              icon: Icon(Icons.access_time_rounded),
              selectedIcon: Icon(Icons.access_time_filled_rounded),
              label: 'Attendance',
            ),
            const NavigationDestination(
              icon: Icon(Icons.event_available_outlined),
              selectedIcon: Icon(Icons.event_available_rounded),
              label: 'Leave',
            ),
            NavigationDestination(
              icon: Badge.count(
                count: unread,
                isLabelVisible: unread > 0,
                backgroundColor: bos.danger,
                child: const Icon(Icons.notifications_outlined),
              ),
              selectedIcon: Badge.count(
                count: unread,
                isLabelVisible: unread > 0,
                backgroundColor: bos.danger,
                child: const Icon(Icons.notifications_rounded),
              ),
              label: 'Alerts',
            ),
            const NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Me',
            ),
          ],
        ),
      ),
    );
  }

  void _onTap(int index) {
    // Tapping the tab you are already on pops back to that branch's root,
    // which is the standard escape hatch out of a stack you drilled into.
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }
}
