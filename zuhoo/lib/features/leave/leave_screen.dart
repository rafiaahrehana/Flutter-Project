import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/permission_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/primitives.dart';
import 'apply_leave_sheet.dart';
import 'leave_approvals_tab.dart';
import 'leave_models.dart';
import 'leave_repository.dart';

class LeaveScreen extends ConsumerWidget {
  const LeaveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(leaveControllerProvider);
    final permissions = ref.watch(permissionControllerProvider);

    // Either code gets someone into the queue, matching the web app: a
    // reviewer who may only reject still needs to see what is waiting. Whether
    // the buttons appear is decided per-card, because the review endpoint
    // itself only accepts LEAVE_APPROVE.
    final isReviewer = permissions.hasAny(const [
      LeavePermissions.approve,
      LeavePermissions.reject,
    ]);

    // Each tab loads its own data. The queue must not go down with the
    // personal list: a reviewer whose own leave fails to load — or who has no
    // employee record at all — still has other people's requests to decide.
    final tabs = <({String label, Widget view})>[
      (label: 'My requests', view: const _MyRequestsTab()),
      (label: 'Balances', view: const _BalancesTab()),
      if (isReviewer) (label: 'To approve', view: const LeaveApprovalsTab()),
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(
          title: const Text('Leave'),
          bottom: TabBar(
            tabs: [for (final tab in tabs) Tab(text: tab.label)],
          ),
        ),
        // Hidden rather than disabled when there is no employee record: the
        // request would be rejected server-side, and a button that only ever
        // produces an error is worse than no button.
        floatingActionButton: (async.value?.hasEmployeeRecord ?? false)
            ? FloatingActionButton.extended(
                onPressed: () => showApplyLeaveSheet(context, ref),
                backgroundColor: bos.brand,
                foregroundColor: Colors.white,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Apply'),
              )
            : null,
        body: TabBarView(children: [for (final tab in tabs) tab.view]),
      ),
    );
  }
}

/// The signed-in user's own requests.
class _MyRequestsTab extends ConsumerWidget {
  const _MyRequestsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(leaveControllerProvider).when(
          loading: () => const Loader(),
          error: (error, _) => ErrorState(
            message: error is ApiException
                ? error.message
                : 'Could not load your leave.',
            onRetry: () => ref.read(leaveControllerProvider.notifier).refresh(),
          ),
          data: (state) => _Requests(state: state),
        );
  }
}

class _BalancesTab extends ConsumerWidget {
  const _BalancesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(leaveControllerProvider).when(
          loading: () => const Loader(),
          error: (error, _) => ErrorState(
            message: error is ApiException
                ? error.message
                : 'Could not load your balances.',
            onRetry: () => ref.read(leaveControllerProvider.notifier).refresh(),
          ),
          data: (state) => _Balances(balances: state.balances),
        );
  }
}

class _Requests extends ConsumerWidget {
  const _Requests({required this.state});

  final LeaveState state;

  Future<void> _cancel(
    BuildContext context,
    WidgetRef ref,
    LeaveRequest request,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Withdraw this request?'),
        content: Text(
          '${Fmt.label(request.leaveType)} leave from '
          '${Fmt.date(request.startDate)} to ${Fmt.date(request.endDate)} '
          'will be withdrawn.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(leaveControllerProvider.notifier).cancel(request.id);
      messenger.showSnackBar(
        const SnackBar(content: Text('Request withdrawn.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;

    if (state.requests.isEmpty) {
      return RefreshIndicator(
        color: bos.brand,
        onRefresh: () => ref.read(leaveControllerProvider.notifier).refresh(),
        child: ListView(
          children: [
            const SizedBox(height: 60),
            if (state.hasEmployeeRecord)
              const EmptyState(
                icon: Icons.event_note_outlined,
                title: 'No leave requests',
                message:
                    'Requests you submit will show up here with their status.',
              )
            else
              const EmptyState(
                icon: Icons.badge_outlined,
                title: 'No employee record',
                message:
                    'Leave is recorded against an employee, and this account '
                    'is not linked to one. Ask your HR team to add you as an '
                    'employee.',
              ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: bos.brand,
      backgroundColor: bos.bgCard,
      onRefresh: () => ref.read(leaveControllerProvider.notifier).refresh(),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
        itemCount: state.requests.length + (state.hasMore ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index >= state.requests.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: state.loadingMore
                  ? const Loader(padding: 8)
                  : OutlinedButton(
                      onPressed: () =>
                          ref.read(leaveControllerProvider.notifier).loadMore(),
                      child: const Text('Load older requests'),
                    ),
            );
          }
          final request = state.requests[index];
          return _RequestCard(
            request: request,
            onCancel: request.canCancel
                ? () => _cancel(context, ref, request)
                : null,
          );
        },
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.request, this.onCancel});

  final LeaveRequest request;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final days = request.totalDays;
    final dayLabel = days == days.roundToDouble()
        ? '${days.round()} day${days == 1 ? '' : 's'}'
        : '${days.toStringAsFixed(1)} days';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${Fmt.label(request.leaveType)} leave',
                  style: TextStyle(
                    color: bos.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              StatusChip(request.status, dense: true),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.date_range_rounded, size: 14, color: bos.muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${Fmt.date(request.startDate)} — ${Fmt.date(request.endDate)}'
                  '  ·  $dayLabel',
                  style: TextStyle(color: bos.textSecondary, fontSize: 13),
                ),
              ),
            ],
          ),
          if (request.reason != null && request.reason!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              request.reason!,
              style: TextStyle(color: bos.muted, fontSize: 13, height: 1.35),
            ),
          ],
          if (request.status == LeaveStatus.rejected &&
              request.rejectionReason != null &&
              request.rejectionReason!.isNotEmpty) ...[
            const SizedBox(height: 10),
            MessageBanner.error(request.rejectionReason!),
          ],
          if (request.reviewedByName != null) ...[
            const SizedBox(height: 8),
            Text(
              'Reviewed by ${request.reviewedByName}'
              '${request.reviewedAt != null ? ' · ${Fmt.relative(request.reviewedAt)}' : ''}',
              style: TextStyle(color: bos.muted, fontSize: 11.5),
            ),
          ],
          if (onCancel != null) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onCancel,
                icon: const Icon(Icons.undo_rounded, size: 17),
                label: const Text('Withdraw'),
                style: TextButton.styleFrom(foregroundColor: bos.danger),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Balances extends ConsumerWidget {
  const _Balances({required this.balances});

  final List<LeaveBalance> balances;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;

    if (balances.isEmpty) {
      return const EmptyState(
        icon: Icons.beach_access_outlined,
        title: 'No balances configured',
        message:
            'Your HR team has not set up leave entitlements for you yet. '
            'You can still submit a request.',
      );
    }

    return RefreshIndicator(
      color: bos.brand,
      backgroundColor: bos.bgCard,
      onRefresh: () => ref.read(leaveControllerProvider.notifier).refresh(),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
        itemCount: balances.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) => _BalanceCard(balance: balances[index]),
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.balance});

  final LeaveBalance balance;

  static String _n(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${Fmt.label(balance.leaveType)} leave',
                      style: TextStyle(
                        color: bos.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${balance.year}',
                      style: TextStyle(color: bos.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _n(balance.remainingDays),
                    style: TextStyle(
                      color: bos.brandInk,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                  Text(
                    'days left',
                    style: TextStyle(color: bos.muted, fontSize: 11.5),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: balance.consumedFraction,
              minHeight: 7,
              backgroundColor: bos.neutralSoft,
              valueColor: AlwaysStoppedAnimation(bos.brand),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _Figure(label: 'Entitled', value: _n(balance.entitledDays)),
              _Figure(label: 'Used', value: _n(balance.usedDays)),
              _Figure(label: 'Pending', value: _n(balance.pendingDays)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              color: bos.text,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(label, style: TextStyle(color: bos.muted, fontSize: 11.5)),
        ],
      ),
    );
  }
}
