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
import 'portal_models.dart';
import 'portal_repository.dart';

class PortalProfileScreen extends ConsumerWidget {
  const PortalProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(clientProfileProvider);
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(title: const Text('Account')),
      body: RefreshIndicator(
        color: bos.brand,
        backgroundColor: bos.bgCard,
        onRefresh: () async => ref.invalidate(clientProfileProvider),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            AppCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  Avatar(
                    initials: async.value?.initials ?? user?.initials ?? '?',
                    size: 58,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    async.value?.headline ?? user?.fullName ?? 'Your account',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: bos.text,
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    user?.email ?? async.value?.email ?? '',
                    style: TextStyle(color: bos.muted, fontSize: 13),
                  ),
                  if (async.value != null) ...[
                    const SizedBox(height: 10),
                    StatusChip(async.value!.status),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            async.when(
              loading: () => const Loader(),
              error: (error, _) => ErrorState(
                message: error is ApiException
                    ? error.message
                    : 'Could not load your account.',
                onRetry: () => ref.invalidate(clientProfileProvider),
              ),
              data: (profile) => _Facts(profile: profile),
            ),
            const SizedBox(height: 22),
            const SectionHeader('Settings', icon: Icons.settings_outlined),
            const _Settings(),
            const SizedBox(height: 22),
            const _SignOut(),
          ],
        ),
      ),
    );
  }
}

class _Facts extends StatelessWidget {
  const _Facts({required this.profile});

  final ClientProfile profile;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    final rows = <({String label, String? value})>[
      (label: 'Contact', value: profile.contactName),
      (label: 'Email', value: profile.email),
      (label: 'Phone', value: profile.phone),
      (label: 'Industry', value: profile.industry),
      (label: 'Website', value: profile.website),
      (label: 'Billing address', value: profile.billingAddress),
      (label: 'Your account manager', value: profile.accountManagerName),
      (
        label: 'Client since',
        value: profile.onboardedAt == null ? null : Fmt.date(profile.onboardedAt)
      ),
      (
        label: 'Requests to date',
        value: profile.totalRequests == null ? null : '${profile.totalRequests}'
      ),
    ].where((row) => row.value != null && row.value!.trim().isNotEmpty).toList();

    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Your details', icon: Icons.badge_outlined),
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
        const SizedBox(height: 10),
        // Editing a client record is the account team's job, not a
        // self-service field — saying so beats an Edit button that 403s.
        Text(
          'To change any of this, message your account team.',
          style: TextStyle(color: bos.muted, fontSize: 12),
        ),
      ],
    );
  }
}

class _Settings extends ConsumerWidget {
  const _Settings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final theme = ref.watch(themeControllerProvider);

    final tiles = <({String label, String? trailing, IconData icon, String path})>[
      (
        label: 'Appearance',
        trailing: '${_modeLabel(theme.mode)} · ${theme.accent.label}',
        icon: Icons.palette_outlined,
        path: Routes.appearance
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

class _SignOut extends ConsumerWidget {
  const _SignOut();

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
