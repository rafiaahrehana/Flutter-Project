import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/auth/auth_models.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/paged_list_view.dart';
import '../../shared/widgets/primitives.dart';
import 'context_models.dart';
import 'context_screen.dart';
import 'platform_models.dart';
import 'platform_repository.dart';

/// The operator's console.
///
/// Gated on role, not permission: everything here reaches across tenants, and
/// only platform staff have any business in it. The backend re-checks the same
/// thing on every call, so this is a courtesy rather than the security.
class PlatformScreen extends ConsumerWidget {
  const PlatformScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final user = ref.watch(currentUserProvider);

    if (user != null && !user.isPlatformStaff) {
      return Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(title: const Text('Platform')),
        body: const EmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Not available to you',
          message:
              'The operator console is for Zuhoo platform staff. Your account '
              'belongs to a company, not to the platform.',
        ),
      );
    }

    // The audit tab appears only for the roles the backend lets read it —
    // a support agent can open a session but not review everyone else's.
    final canAudit = user?.hasAnyRole(impersonationHistoryRoles) ?? false;

    // Support staff get the context tab. The review roles are a subset of
    // these, so this one check covers both who may start a switch and who
    // may only read the board. It is not the same set as the audit tab:
    // a support agent has this and not that, a system admin the reverse.
    final canContext = user?.hasAnyRole(contextSwitchRoles) ?? false;

    // The staff directory is a narrower gate than the console around it:
    // GET /platform/users is SUPER_ADMIN and SYSTEM_ADMIN only, so showing
    // the tab to every platform role hands four of them a 403 on open.
    final canStaff = user?.hasAnyRole(platformUserRoles) ?? false;

    return DefaultTabController(
      length: 2 +
          (canStaff ? 1 : 0) +
          (canContext ? 1 : 0) +
          (canAudit ? 1 : 0),
      child: Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(
          title: const Text('Platform'),
          bottom: TabBar(
            // Five tabs do not fit a phone width evenly; scrolling beats
            // three-letter truncations of "Companies".
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              const Tab(text: 'Companies'),
              const Tab(text: 'Flags'),
              if (canStaff) const Tab(text: 'Staff'),
              if (canContext) const Tab(text: 'Context'),
              if (canAudit) const Tab(text: 'Audit'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            const _CompaniesTab(),
            const _FlagsTab(),
            if (canStaff) const _StaffTab(),
            if (canContext) const ContextSwitchTab(),
            if (canAudit) const _AuditTab(),
          ],
        ),
      ),
    );
  }
}

class _CompaniesTab extends ConsumerWidget {
  const _CompaniesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(companiesProvider.notifier);

    return Column(
      children: [
        const _CompanySearch(),
        const _StatusFilter(),
        Expanded(
          child: PagedListView<Company>(
            async: ref.watch(companiesProvider),
            onRefresh: controller.refresh,
            onLoadMore: () => guardListAction(context, controller.loadMore),
            emptyIcon: Icons.business_outlined,
            emptyTitle: 'No companies',
            emptyMessage: 'No tenants match that filter.',
            errorMessage: 'Could not load the tenant list.',
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            itemBuilder: (context, company) => _CompanyCard(company: company),
          ),
        ),
      ],
    );
  }
}

class _CompanySearch extends ConsumerStatefulWidget {
  const _CompanySearch();

  @override
  ConsumerState<_CompanySearch> createState() => _CompanySearchState();
}

class _CompanySearchState extends ConsumerState<_CompanySearch> {
  final _controller = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Debounced, because every keystroke would otherwise refetch the whole
  /// tenant list — the search is server-side.
  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      ref.read(companySearchProvider.notifier).set(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: TextField(
        controller: _controller,
        onChanged: _onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search companies',
          isDense: true,
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _controller.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () {
                    _controller.clear();
                    _debounce?.cancel();
                    ref.read(companySearchProvider.notifier).set('');
                    setState(() {});
                  },
                ),
        ),
      ),
    );
  }
}

class _StatusFilter extends ConsumerWidget {
  const _StatusFilter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final selected = ref.watch(companyFilterProvider);

    const statuses = <String?>[null, ...CompanyStatus.all];

    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        itemCount: statuses.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final status = statuses[index];
          final isSelected = selected == status;
          return GestureDetector(
            onTap: () => ref.read(companyFilterProvider.notifier).set(status),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
              decoration: BoxDecoration(
                color: isSelected ? bos.brand : bos.bgCard,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isSelected ? bos.brand : bos.border),
              ),
              child: Text(
                status == null ? 'All' : Fmt.label(status),
                style: TextStyle(
                  color: isSelected ? Colors.white : bos.textSecondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CompanyCard extends ConsumerStatefulWidget {
  const _CompanyCard({required this.company});

  final Company company;

  @override
  ConsumerState<_CompanyCard> createState() => _CompanyCardState();
}

class _CompanyCardState extends ConsumerState<_CompanyCard> {
  bool _busy = false;

  Future<void> _setStatus(String status) async {
    final company = widget.company;

    // Suspending or deactivating cuts a paying customer off. Worth a beat.
    if (status == CompanyStatus.suspended ||
        status == CompanyStatus.deactivated) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${Fmt.label(status)} ${company.companyName}?'),
          content: Text(
            status == CompanyStatus.deactivated
                ? 'Everyone at this company loses access immediately. This is '
                      'not a soft change.'
                : 'Everyone at this company loses access until it is '
                      'reactivated.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(Fmt.label(status)),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(companiesProvider.notifier).setStatus(company.id, status);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${company.companyName} is now ${Fmt.label(status).toLowerCase()}.',
          ),
        ),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not change that status.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Opens a session inside this tenant.
  ///
  /// The reason is not a formality: it is written to the impersonation audit
  /// log, which is the only record of why a member of staff was inside a
  /// customer's account. Collected before the call rather than after, because
  /// afterwards nobody ever writes one.
  Future<void> _accessCompany() async {
    final company = widget.company;
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => _ReasonDialog(companyName: company.companyName),
    );
    if (reason == null || !mounted) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      await ref.read(authControllerProvider.notifier).startImpersonation(
            companyId: company.id,
            reason: reason,
          );
      if (!mounted) return;
      // This screen is gated on being platform staff and the app is no longer
      // acting as any — leaving it mounted would drop the admin onto its own
      // "not available to you" state the moment it rebuilt.
      router.go(Routes.home);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not open that company.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changePlan() async {
    final plans = ref.read(subscriptionPlansProvider).value ?? const [];
    if (plans.isEmpty) return;

    final chosen = await showModalBottomSheet<SubscriptionPlanOption>(
      context: context,
      builder: (sheetContext) {
        final bos = Theme.of(sheetContext).bos;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Move to which plan?',
                      style: TextStyle(
                        color: bos.text,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Said plainly: a change made here without a payment
                    // reference is invisible to the revenue figures, which are
                    // built from subscription history.
                    Text(
                      'Recorded without a payment reference, so it will not '
                      'appear in platform revenue.',
                      style: TextStyle(color: bos.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              for (final plan in plans)
                ListTile(
                  title: Text(plan.name),
                  subtitle: plan.price == null
                      ? null
                      : Text(
                          '${Fmt.money(plan.price)}'
                          '${plan.billingCycle != null ? ' · ${Fmt.label(plan.billingCycle)}' : ''}',
                        ),
                  trailing: plan.key == widget.company.subscriptionPlan
                      ? Icon(Icons.check_rounded, color: bos.brand)
                      : null,
                  onTap: () => Navigator.pop(sheetContext, plan),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (chosen == null || !mounted) return;
    if (chosen.key == widget.company.subscriptionPlan) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(companiesProvider.notifier)
          .setPlan(widget.company.id, chosen.key);
      messenger.showSnackBar(
        SnackBar(content: Text('Moved to ${chosen.name}.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not change that plan.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final company = widget.company;
    final hasPlans =
        (ref.watch(subscriptionPlansProvider).value ?? const []).isNotEmpty;
    final days = company.daysUntilExpiry;
    // Three separate gates, because the backend uses three: status changes
    // exclude sales, plan changes include them, and impersonation excludes
    // accounting. Offering an action the caller cannot perform turns a
    // permission boundary into a mystery error.
    final user = ref.watch(currentUserProvider);
    final canImpersonate = user?.hasAnyRole(impersonationRoles) ?? false;
    final canSetStatus = user?.hasAnyRole(companyStatusRoles) ?? false;
    final canSetPlan = user?.hasAnyRole(companyPlanRoles) ?? false;

    // Marketing reaches the console and the company list but can act on
    // neither, so their cards carry no action row at all rather than an
    // empty strip of padding where one would be.
    final hasActions =
        canImpersonate || canSetStatus || (canSetPlan && hasPlans);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      company.companyName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: bos.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      company.subdomain,
                      style: TextStyle(
                        color: bos.muted,
                        fontSize: 12,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusChip(company.status, dense: true),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                Icons.workspace_premium_outlined,
                size: 14,
                color: bos.muted,
              ),
              const SizedBox(width: 5),
              Text(
                company.subscriptionPlan.isEmpty
                    ? 'No plan'
                    : Fmt.label(company.subscriptionPlan),
                style: TextStyle(
                  color: bos.textSecondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (company.ownerName != null)
                Flexible(
                  child: Text(
                    company.ownerName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(color: bos.muted, fontSize: 12),
                  ),
                ),
            ],
          ),
          if (company.needsAttention) ...[
            const SizedBox(height: 10),
            MessageBanner.info('Trial has expired — still on a trial plan.'),
          ] else if (company.expiringSoon && days != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.schedule_rounded, size: 14, color: bos.warning),
                const SizedBox(width: 5),
                Text(
                  days == 0
                      ? 'Subscription ends today'
                      : 'Subscription ends in $days day${days == 1 ? '' : 's'}',
                  style: TextStyle(
                    color: bos.warning,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
          if (hasActions) const SizedBox(height: 12),
          if (hasActions && _busy)
            const Loader(padding: 6)
          else if (hasActions)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // Listed first and in the brand tone: it is the action support
                // staff actually come here for. Hidden outright for platform
                // roles the backend would refuse, rather than shown and 403ing.
                if (canImpersonate)
                  _Action(
                    label: 'Access company',
                    icon: Icons.login_rounded,
                    tone: bos.brand,
                    onTap: _accessCompany,
                  ),
                // Only the transitions that make sense from where it is.
                if (canSetStatus && company.isLive)
                  _Action(
                    label: 'Suspend',
                    icon: Icons.pause_rounded,
                    tone: bos.warning,
                    onTap: () => _setStatus(CompanyStatus.suspended),
                  ),
                if (canSetStatus && !company.isLive)
                  _Action(
                    label: 'Reactivate',
                    icon: Icons.play_arrow_rounded,
                    tone: bos.success,
                    onTap: () => _setStatus(CompanyStatus.active),
                  ),
                if (canSetStatus && !company.isDeactivated)
                  _Action(
                    label: 'Deactivate',
                    icon: Icons.block_rounded,
                    tone: bos.danger,
                    onTap: () => _setStatus(CompanyStatus.deactivated),
                  ),
                if (canSetPlan && hasPlans)
                  _Action(
                    label: 'Change plan',
                    icon: Icons.swap_horiz_rounded,
                    tone: bos.brandInk,
                    onTap: _changePlan,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Collects the mandatory reason before a session starts.
///
/// Stateful and validated locally because the backend's only rule is
/// `@NotBlank` — which a single space satisfies. An audit log full of blank
/// reasons is the same as no audit log, so this asks for something a person
/// could actually read back later.
class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.companyName});

  final String companyName;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _controller = TextEditingController();
  static const _minLength = 8;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final reason = _controller.text.trim();
    final valid = reason.length >= _minLength;

    return AlertDialog(
      title: Text('Access ${widget.companyName}?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MessageBanner.warning(
            'You will be signed in as this company, with owner-level access to '
            'their real data. Your name, the reason below and the time are '
            'recorded.',
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLines: 2,
            maxLength: 200,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Reason',
              hintText: 'e.g. Ticket #482 — invoices not generating',
            ),
          ),
          if (reason.isNotEmpty && !valid)
            Text(
              'A few more words — this is what an auditor reads.',
              style: TextStyle(color: bos.muted, fontSize: 12),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: valid ? () => Navigator.pop(context, reason) : null,
          child: const Text('Access company'),
        ),
      ],
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.label,
    required this.icon,
    required this.tone,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12.5)),
      style: OutlinedButton.styleFrom(
        foregroundColor: tone,
        side: BorderSide(color: tone.withValues(alpha: 0.4)),
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
    );
  }
}

class _FlagsTab extends ConsumerWidget {
  const _FlagsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(featureFlagsProvider);

    return async.when(
      loading: () => const Loader(),
      error: (error, _) => ErrorState(
        message: error is ApiException
            ? error.message
            : 'Could not load the feature flags.',
        onRetry: () => ref.read(featureFlagsProvider.notifier).refresh(),
      ),
      data: (flags) {
        if (flags.isEmpty) {
          return const EmptyState(
            icon: Icons.toggle_off_outlined,
            title: 'No feature flags',
            message: 'Nothing has been defined for this platform yet.',
          );
        }
        // Flipping a flag is narrower than reaching this console: the backend
        // allows it for SUPER_ADMIN and SYSTEM_ADMIN only, while a support
        // agent or accountant is platform staff too. Showing them live-looking
        // switches that all 403 on tap would be the worst of both.
        final canToggle =
            ref.watch(currentUserProvider)?.hasAnyRole(const [
              'SUPER_ADMIN',
              'SYSTEM_ADMIN',
            ]) ??
            false;

        return RefreshIndicator(
          color: bos.brand,
          backgroundColor: bos.bgCard,
          onRefresh: () => ref.read(featureFlagsProvider.notifier).refresh(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              if (canToggle)
                // A flag here changes the product for every tenant at once.
                // Not a warning banner, just a plain statement of scope.
                MessageBanner.info(
                  'These switch features on and off for every company on the '
                  'platform, immediately.',
                )
              else
                MessageBanner.info(
                  'Read-only. Only a super admin or system admin can change '
                  'platform flags.',
                ),
              const SizedBox(height: 16),
              AppCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    for (var i = 0; i < flags.length; i++) ...[
                      if (i > 0)
                        Divider(height: 1, color: bos.borderLight, indent: 16),
                      _FlagRow(flag: flags[i], canToggle: canToggle),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FlagRow extends ConsumerWidget {
  const _FlagRow({required this.flag, required this.canToggle});

  final FeatureFlag flag;
  final bool canToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;

    return SwitchListTile(
      value: flag.enabled,
      // A null handler renders the switch visibly disabled, which is the
      // honest state for someone who may read flags but not flip them.
      onChanged: !canToggle
          ? null
          : (_) async {
              final messenger = ScaffoldMessenger.of(context);
              try {
                await ref
                    .read(featureFlagsProvider.notifier)
                    .toggle(flag.flagKey);
              } on ApiException catch (e) {
                messenger.showSnackBar(SnackBar(content: Text(e.message)));
              } catch (_) {
                messenger.showSnackBar(
                  const SnackBar(content: Text('Could not change that flag.')),
                );
              }
            },
      title: Text(
        flag.label,
        style: TextStyle(
          color: bos.text,
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        flag.description?.trim().isNotEmpty == true
            ? flag.description!
            : flag.flagKey,
        style: TextStyle(color: bos.muted, fontSize: 12),
      ),
      activeThumbColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
    );
  }
}

class _StaffTab extends ConsumerWidget {
  const _StaffTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final controller = ref.read(platformUsersProvider.notifier);

    return PagedListView<PlatformUser>(
      async: ref.watch(platformUsersProvider),
      onRefresh: controller.refresh,
      onLoadMore: () => guardListAction(context, controller.loadMore),
      emptyIcon: Icons.badge_outlined,
      emptyTitle: 'No platform staff',
      emptyMessage: 'Zuhoo staff accounts appear here.',
      errorMessage: 'Could not load platform staff.',
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      itemBuilder: (context, user) => AppCard(
        child: Row(
          children: [
            Avatar(initials: user.initials, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.fullName.isEmpty ? user.email : user.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: bos.text,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    user.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: bos.muted, fontSize: 12),
                  ),
                  // An account that exists but cannot be used looks identical
                  // to a working one otherwise.
                  if (user.isUnusable) ...[
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Icon(
                          user.active
                              ? Icons.mark_email_unread_outlined
                              : Icons.person_off_outlined,
                          size: 13,
                          color: bos.warning,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          user.active ? 'Email not verified' : 'Deactivated',
                          style: TextStyle(
                            color: bos.warning,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            StatusChip(user.role, label: Fmt.label(user.role), dense: true),
          ],
        ),
      ),
    );
  }
}

/// The impersonation audit trail.
///
/// Its own tab rather than a buried screen, because a record nobody looks at
/// deters nobody. Visible only to the roles the backend lets read it.
class _AuditTab extends ConsumerWidget {
  const _AuditTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PagedListView<ImpersonationAuditEntry>(
      async: ref.watch(impersonationHistoryProvider),
      onRefresh: () => ref.read(impersonationHistoryProvider.notifier).refresh(),
      onLoadMore: () =>
          ref.read(impersonationHistoryProvider.notifier).loadMore(),
      emptyTitle: 'No sessions yet',
      emptyMessage:
          'Every time platform staff open a company, it is recorded here.',
      emptyIcon: Icons.history_rounded,
      itemBuilder: (context, entry) => _AuditRow(entry: entry),
    );
  }
}

class _AuditRow extends StatelessWidget {
  const _AuditRow({required this.entry});

  final ImpersonationAuditEntry entry;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  entry.companyName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: bos.text,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (entry.openEnded)
                StatusChip('PENDING', label: 'Not ended', dense: true),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            entry.adminName,
            style: TextStyle(color: bos.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: 8),
          Text(
            // The reason is the whole point of the record; it gets the
            // readable treatment, not a grey footnote.
            entry.reason?.trim().isNotEmpty == true
                ? entry.reason!.trim()
                : 'No reason recorded.',
            style: TextStyle(
              color: entry.reason?.trim().isNotEmpty == true
                  ? bos.text
                  : bos.muted,
              fontSize: 13,
              height: 1.3,
              fontStyle: entry.reason?.trim().isNotEmpty == true
                  ? FontStyle.normal
                  : FontStyle.italic,
            ),
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Icon(Icons.schedule_rounded, size: 13, color: bos.muted),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  entry.openEnded
                      ? Fmt.dateTime(entry.startedAt)
                      : '${Fmt.dateTime(entry.startedAt)} → '
                          '${Fmt.time(entry.endedAt)}',
                  style: TextStyle(color: bos.muted, fontSize: 11.5),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
