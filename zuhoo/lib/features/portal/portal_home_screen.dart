import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/stat_card.dart';
import '../requests/request_card.dart';
import '../requests/request_controllers.dart';
import '../requests/request_detail_screen.dart';
import 'portal_models.dart';
import 'portal_repository.dart';

/// What a client sees when they open the app.
///
/// Deliberately not the employee dashboard with things hidden. A client and an
/// employee want different questions answered — "where are my jobs up to and
/// what do I owe" versus "am I checked in and how much leave is left" — and
/// one screen trying to serve both ends up serving neither.
class PortalHomeScreen extends ConsumerWidget {
  const PortalHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final profile = ref.watch(clientProfileProvider).value;
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: bos.bgPage,
      body: RefreshIndicator(
        color: bos.brand,
        backgroundColor: bos.bgCard,
        onRefresh: () async {
          ref.invalidate(clientSummaryProvider);
          ref.invalidate(clientProfileProvider);
          ref.invalidate(clientSubscriptionsProvider);
          await ref.read(myRequestsProvider.notifier).refresh();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            _Greeting(
              name: profile?.headline ?? user?.displayFirstName ?? '',
              initials: profile?.initials ?? user?.initials ?? '?',
              manager: profile?.accountManagerName,
            ),
            const SizedBox(height: 18),
            const _Summary(),
            const SizedBox(height: 22),
            const _Subscriptions(),
            const _RecentRequests(),
          ],
        ),
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({
    required this.name,
    required this.initials,
    required this.manager,
  });

  final String name;
  final String initials;
  final String? manager;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(greeting, style: TextStyle(color: bos.muted, fontSize: 13.5)),
              const SizedBox(height: 2),
              Text(
                name.isEmpty ? 'Welcome back' : name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: bos.text,
                  fontSize: 23,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              if (manager != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Your contact: $manager',
                  style: TextStyle(
                    color: bos.brandInk,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        Avatar(initials: initials, size: 46),
      ],
    );
  }
}

class _Summary extends ConsumerWidget {
  const _Summary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final summary = ref.watch(clientSummaryProvider).value;

    final cards = [
      StatCard(
        label: 'Open requests',
        value: summary?.openRequests.toString(),
        icon: Icons.assignment_outlined,
        tone: bos.brandInk,
        onTap: () => context.go(PortalRoutes.requests),
      ),
      StatCard(
        label: 'Completed',
        value: summary?.completedRequests.toString(),
        icon: Icons.task_alt_rounded,
        tone: bos.success,
      ),
      StatCard(
        label: 'Unpaid invoices',
        value: summary?.unpaidInvoices.toString(),
        icon: Icons.receipt_long_outlined,
        tone: summary?.owesMoney ?? false ? bos.warning : bos.muted,
        onTap: () => context.go(PortalRoutes.billing),
      ),
      StatCard(
        label: 'Outstanding',
        value: summary == null
            ? null
            : Fmt.money(summary.outstandingInvoiceAmount),
        icon: Icons.account_balance_wallet_outlined,
        tone: summary?.owesMoney ?? false ? bos.danger : bos.muted,
        onTap: () => context.go(PortalRoutes.billing),
      ),
    ];

    final scale = MediaQuery.textScalerOf(context).scale(1);
    final extent = 134 + (scale - 1).clamp(0.0, 1.5) * 48;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: cards.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        mainAxisExtent: extent,
      ),
      itemBuilder: (context, index) => cards[index],
    );
  }
}

class _Subscriptions extends ConsumerWidget {
  const _Subscriptions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subscriptions = ref.watch(clientSubscriptionsProvider).value;

    // A client who buys work one job at a time has no plan. That is normal,
    // so the panel simply is not there.
    if (subscriptions == null || subscriptions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Your plan', icon: Icons.card_membership_outlined),
        for (var i = 0; i < subscriptions.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _SubscriptionCard(subscription: subscriptions[i]),
        ],
        const SizedBox(height: 22),
      ],
    );
  }
}

class _SubscriptionCard extends StatelessWidget {
  const _SubscriptionCard({required this.subscription});

  final PackageSubscription subscription;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final used = subscription.quotaUsedFraction;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  subscription.packageName ?? 'Plan #${subscription.packageId}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: bos.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              StatusChip(subscription.status, dense: true),
            ],
          ),
          if (subscription.billingCycle != null) ...[
            const SizedBox(height: 3),
            Text(
              Fmt.label(subscription.billingCycle),
              style: TextStyle(color: bos.muted, fontSize: 12.5),
            ),
          ],
          if (used != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  'Requests used',
                  style: TextStyle(color: bos.textSecondary, fontSize: 12.5),
                ),
                const Spacer(),
                Text(
                  '${subscription.requestsUsed} of ${subscription.requestQuota}',
                  style: TextStyle(color: bos.muted, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: used,
                minHeight: 6,
                backgroundColor: bos.neutralSoft,
                valueColor: AlwaysStoppedAnimation(
                  used >= 1 ? bos.danger : bos.brand,
                ),
              ),
            ),
          ],
          if (subscription.nextBillingDate != null) ...[
            const SizedBox(height: 10),
            Text(
              'Renews ${Fmt.date(subscription.nextBillingDate)}'
              '${subscription.autoRenew ? '' : ' — auto-renew is off'}',
              style: TextStyle(color: bos.muted, fontSize: 11.5),
            ),
          ],
        ],
      ),
    );
  }
}

class _RecentRequests extends ConsumerWidget {
  const _RecentRequests();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(myRequestsProvider).value?.items;
    if (requests == null || requests.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Recent requests',
          icon: Icons.assignment_outlined,
          trailing: TextButton(
            onPressed: () => context.go(PortalRoutes.requests),
            child: const Text('See all'),
          ),
        ),
        for (var i = 0; i < requests.length && i < 3; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          RequestCard(
            request: requests[i],
            onTap: () => openRequestDetail(context, requests[i].id),
          ),
        ],
      ],
    );
  }
}
