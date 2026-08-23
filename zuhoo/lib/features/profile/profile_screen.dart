import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../core/theme/theme_controller.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/primitives.dart';
import 'employee_models.dart';
import 'employee_repository.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final user = ref.watch(currentUserProvider);
    final employee = ref.watch(myEmployeeProvider);

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(title: const Text('Me')),
      body: RefreshIndicator(
        color: bos.brand,
        backgroundColor: bos.bgCard,
        onRefresh: () async {
          ref.invalidate(myEmployeeProvider);
          await ref.read(authControllerProvider.notifier).refreshProfile();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            AppCard(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Avatar(
                    initials: employee.value?.initials ??
                        user?.initials ??
                        '?',
                    imageUrl: employee.value?.imageUrl ??
                        user?.profileImageUrl,
                    size: 58,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          employee.value?.fullName ??
                              user?.fullName ??
                              'Your profile',
                          style: TextStyle(
                            color: bos.text,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          user?.email ?? employee.value?.email ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: bos.muted, fontSize: 13),
                        ),
                        if (employee.value != null) ...[
                          const SizedBox(height: 8),
                          StatusChip(
                            employee.value!.employmentStatus ?? 'ACTIVE',
                            label: employee.value!.roleLabel,
                            dense: true,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            employee.when(
              loading: () => const Loader(),
              error: (error, _) => ErrorState(
                message: error is ApiException
                    ? error.message
                    : 'Could not load your employee record.',
                onRetry: () => ref.invalidate(myEmployeeProvider),
              ),
              data: (record) => record == null
                  ? const _NoEmployeeRecord()
                  : _Details(employee: record),
            ),
            const SizedBox(height: 22),
            const SectionHeader('Settings', icon: Icons.settings_outlined),
            const _SettingsList(),
            const SizedBox(height: 22),
            const _SignOutButton(),
          ],
        ),
      ),
    );
  }
}

/// Shown when the signed-in account has no row in the employees table.
///
/// Typically a company owner: they own the tenant but were never hired into it,
/// so there is nothing to show under Employment and nothing to edit. Saying that
/// plainly beats a "Not found." error, which reads as a bug in an app the person
/// running the company just installed.
class _NoEmployeeRecord extends StatelessWidget {
  const _NoEmployeeRecord();

  @override
  Widget build(BuildContext context) {
    return const AppCard(
      child: MessageBanner.info(
        'This account is not linked to an employee record, so attendance, '
        'leave and payslips do not apply to it. Ask your HR team to add you '
        'as an employee if you need them.',
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.employee});

  final Employee employee;

  @override
  Widget build(BuildContext context) {
    final rows = <({String label, String? value, IconData icon})>[
      (
        label: 'Employee number',
        value: employee.employeeNumber,
        icon: Icons.badge_outlined
      ),
      (
        label: 'Department',
        value: employee.departmentName,
        icon: Icons.account_tree_outlined
      ),
      (
        label: 'Designation',
        value: employee.designationName,
        icon: Icons.workspace_premium_outlined
      ),
      (
        label: 'Reporting to',
        value: employee.reportingManagerName,
        icon: Icons.supervisor_account_outlined
      ),
      (label: 'Shift', value: employee.shiftName, icon: Icons.schedule_outlined),
      (
        label: 'Joined',
        value: employee.hireDate == null ? null : Fmt.date(employee.hireDate),
        icon: Icons.event_outlined
      ),
      (
        label: 'Work phone',
        value: employee.workPhone,
        icon: Icons.phone_outlined
      ),
      (
        label: 'Personal phone',
        value: employee.phone,
        icon: Icons.smartphone_outlined
      ),
      (
        label: 'Emergency contact',
        value: employee.emergencyContactName == null
            ? null
            : '${employee.emergencyContactName}'
                '${employee.emergencyContactPhone != null ? ' · ${employee.emergencyContactPhone}' : ''}',
        icon: Icons.emergency_outlined
      ),
    ].where((r) => r.value != null && r.value!.isNotEmpty).toList();

    if (rows.isEmpty) return const SizedBox.shrink();

    final bos = Theme.of(context).bos;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Employment',
          icon: Icons.work_outline_rounded,
          trailing: TextButton(
            onPressed: () => context.push(Routes.editProfile),
            child: const Text('Edit'),
          ),
        ),
        AppCard(
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) ...[
                  const SizedBox(height: 10),
                  Divider(height: 1, color: bos.borderLight),
                  const SizedBox(height: 10),
                ],
                Row(
                  children: [
                    Icon(rows[i].icon, size: 17, color: bos.muted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        rows[i].label,
                        style: TextStyle(color: bos.muted, fontSize: 13),
                      ),
                    ),
                    Flexible(
                      child: Text(
                        rows[i].value!,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: bos.text,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingsList extends ConsumerWidget {
  const _SettingsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final theme = ref.watch(themeControllerProvider);

    // The operator console is for Zuhoo's own staff. A tenant's employee has
    // no business seeing the entry point, let alone the tenant list behind it.
    final isPlatformStaff =
        ref.watch(currentUserProvider)?.isPlatformStaff ?? false;

    final tiles = <({String label, String? trailing, IconData icon, String path})>[
      if (isPlatformStaff)
        (
          label: 'Platform console',
          trailing: null,
          icon: Icons.admin_panel_settings_outlined,
          path: Routes.platform
        ),
      (
        label: 'Performance',
        trailing: null,
        icon: Icons.insights_outlined,
        path: Routes.performance
      ),
      (
        label: 'Hiring',
        trailing: null,
        icon: Icons.work_outline_rounded,
        path: Routes.recruitment
      ),
      (
        label: 'IT assets',
        trailing: null,
        icon: Icons.devices_outlined,
        path: Routes.itam
      ),
      (
        label: 'People',
        trailing: null,
        icon: Icons.groups_2_outlined,
        path: Routes.directory
      ),
      (
        label: 'Appearance',
        trailing: '${_modeLabel(theme.mode)} · ${theme.accent.label}',
        icon: Icons.palette_outlined,
        path: Routes.appearance
      ),
      (
        label: 'My payslips',
        trailing: null,
        icon: Icons.receipt_long_outlined,
        path: Routes.payslips
      ),
      (
        label: 'Service requests',
        trailing: null,
        icon: Icons.assignment_outlined,
        path: Routes.requests
      ),
      (
        label: 'CRM',
        trailing: null,
        icon: Icons.trending_up_rounded,
        path: Routes.crm
      ),
      (
        label: 'Finance',
        trailing: null,
        icon: Icons.account_balance_wallet_outlined,
        path: Routes.finance
      ),
      (
        label: 'Support',
        trailing: null,
        icon: Icons.support_agent_rounded,
        path: Routes.support
      ),
      (
        label: 'Change password',
        trailing: null,
        icon: Icons.key_outlined,
        path: Routes.changePassword
      ),
    ];

    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) Divider(height: 1, indent: 54, color: bos.borderLight),
            ListTile(
              leading: Container(
                height: 34,
                width: 34,
                decoration: BoxDecoration(
                  color: bos.neutralSoft,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(tiles[i].icon, size: 18, color: bos.textSecondary),
              ),
              title: Text(tiles[i].label),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (tiles[i].trailing != null)
                    Text(
                      tiles[i].trailing!,
                      style: TextStyle(color: bos.muted, fontSize: 12.5),
                    ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right_rounded, size: 20, color: bos.muted),
                ],
              ),
              onTap: () => context.push(tiles[i].path),
            ),
          ],
        ],
      ),
    );
  }

  static String _modeLabel(ThemeMode mode) => switch (mode) {
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
        ThemeMode.system => 'System',
      };
}

class _SignOutButton extends ConsumerWidget {
  const _SignOutButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;

    return OutlinedButton.icon(
      onPressed: () async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Sign out?'),
            content: const Text(
              'You will need your email and password to sign back in.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Stay'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Sign out'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        // No navigation here — clearing the session flips the router's
        // redirect, which is the single place that decides where to land.
        await ref.read(authControllerProvider.notifier).logout();
      },
      icon: const Icon(Icons.logout_rounded, size: 18),
      label: const Text('Sign out'),
      style: OutlinedButton.styleFrom(
        foregroundColor: bos.danger,
        side: BorderSide(color: bos.danger.withValues(alpha: 0.4)),
      ),
    );
  }
}
