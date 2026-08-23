import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/permission_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/paged_list_view.dart';
import '../../shared/widgets/primitives.dart';
import 'leave_models.dart';
import 'leave_repository.dart';

/// The reviewer's queue.
///
/// Lives inside the leave screen rather than in an admin section of its own,
/// because approving someone's holiday is the same subject as booking your
/// own — and a manager checking the queue is usually already looking at leave.
class LeaveApprovalsTab extends ConsumerWidget {
  const LeaveApprovalsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(leaveQueueProvider.notifier);
    final filter = ref.watch(leaveQueueFilterProvider);

    return Column(
      children: [
        const _StatusFilter(),
        Expanded(
          child: PagedListView<LeaveRequest>(
            async: ref.watch(leaveQueueProvider),
            onRefresh: controller.refresh,
            onLoadMore: () => guardListAction(context, controller.loadMore),
            emptyIcon: Icons.task_alt_rounded,
            emptyTitle: filter == LeaveStatus.pending
                ? 'Nothing waiting on you'
                : 'Nothing here',
            emptyMessage: filter == LeaveStatus.pending
                ? 'Requests needing a decision appear here.'
                : 'No requests with that status.',
            errorMessage: 'Could not load the leave queue.',
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
            itemBuilder: (context, request) => _QueueCard(request: request),
          ),
        ),
      ],
    );
  }
}

class _StatusFilter extends ConsumerWidget {
  const _StatusFilter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final selected = ref.watch(leaveQueueFilterProvider);

    // Pending leads: it is the only status anyone can act on, and it is what a
    // reviewer opens this for.
    const statuses = <String?>[
      LeaveStatus.pending,
      LeaveStatus.approved,
      LeaveStatus.rejected,
      LeaveStatus.cancelled,
      null,
    ];

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
            onTap: () => ref.read(leaveQueueFilterProvider.notifier).set(status),
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

class _QueueCard extends ConsumerStatefulWidget {
  const _QueueCard({required this.request});

  final LeaveRequest request;

  @override
  ConsumerState<_QueueCard> createState() => _QueueCardState();
}

class _QueueCardState extends ConsumerState<_QueueCard> {
  bool _busy = false;

  Future<void> _decide({required bool approve}) async {
    ReviewLeaveRequest review;

    if (approve) {
      final confirmed = await _confirmApproval();
      if (confirmed != true) return;
      review = const ReviewLeaveRequest.approve();
    } else {
      final reason = await _askRejectionReason();
      if (reason == null) return;
      review = ReviewLeaveRequest.reject(reason);
    }

    if (!mounted) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(leaveQueueProvider.notifier).review(widget.request.id, review);
      messenger.showSnackBar(
        SnackBar(content: Text(approve ? 'Leave approved.' : 'Leave rejected.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not record that decision.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Confirming an approval shows what the employee has left.
  ///
  /// This is the question a reviewer actually has — "can they afford these
  /// days?" — and it is the one piece of context the list itself cannot carry.
  Future<bool?> _confirmApproval() {
    final request = widget.request;

    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final bos = Theme.of(sheetContext).bos;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Approve this leave?',
                style: TextStyle(
                  color: bos.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${request.employeeName ?? 'This employee'} · '
                '${_dayLabel(request.totalDays)} of '
                '${Fmt.label(request.leaveType)} leave',
                style: TextStyle(color: bos.textSecondary, fontSize: 13.5),
              ),
              Text(
                '${Fmt.date(request.startDate)} — ${Fmt.date(request.endDate)}',
                style: TextStyle(color: bos.muted, fontSize: 12.5),
              ),
              const SizedBox(height: 16),
              _BalanceContext(
                employeeId: request.employeeId,
                leaveType: request.leaveType,
                requestedDays: request.totalDays,
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(sheetContext, true),
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('Approve'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<String?> _askRejectionReason() {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final bos = Theme.of(sheetContext).bos;
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Why are you turning this down?',
                    style: TextStyle(
                      color: bos.text,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${widget.request.employeeName ?? 'The employee'} will see this.',
                    style: TextStyle(color: bos.muted, fontSize: 12.5),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: controller,
                    maxLines: 3,
                    autofocus: true,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Reason',
                      hintText: 'Whether they should ask again, and when',
                      alignLabelWithHint: true,
                    ),
                    // The backend refuses a blank reason outright; catching it
                    // here saves a round trip and a raw error message.
                    validator: (value) => (value == null || value.trim().isEmpty)
                        ? 'A refusal with no reason leaves them guessing.'
                        : null,
                  ),
                  const SizedBox(height: 18),
                  ElevatedButton(
                    onPressed: () {
                      if (!(formKey.currentState?.validate() ?? false)) return;
                      Navigator.pop(sheetContext, controller.text.trim());
                    },
                    child: const Text('Reject'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ).whenComplete(controller.dispose);
  }

  static String _dayLabel(double days) => days == days.roundToDouble()
      ? '${days.round()} day${days == 1 ? '' : 's'}'
      : '${days.toStringAsFixed(1)} days';

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final request = widget.request;

    // Two different codes on purpose. Seeing the queue and acting on it are
    // separate entitlements, and the backend only lets LEAVE_APPROVE through
    // the review endpoint — for either decision.
    final canDecide = request.canCancel &&
        ref.watch(permissionControllerProvider).has(LeavePermissions.approve);

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
                      request.employeeName ?? 'Employee #${request.employeeId}',
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
                      '${Fmt.label(request.leaveType)} · '
                      '${_dayLabel(request.totalDays)}',
                      style: TextStyle(color: bos.muted, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusChip(request.status, dense: true),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.date_range_rounded, size: 14, color: bos.muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${Fmt.date(request.startDate)} — ${Fmt.date(request.endDate)}',
                  style: TextStyle(color: bos.textSecondary, fontSize: 13),
                ),
              ),
              Text(
                Fmt.relative(request.createdAt),
                style: TextStyle(color: bos.muted, fontSize: 11.5),
              ),
            ],
          ),
          if (request.reason != null && request.reason!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              request.reason!,
              style: TextStyle(color: bos.muted, fontSize: 13, height: 1.35),
            ),
          ],
          if (request.status == LeaveStatus.rejected &&
              request.rejectionReason != null &&
              request.rejectionReason!.trim().isNotEmpty) ...[
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
          if (canDecide) ...[
            const SizedBox(height: 14),
            if (_busy)
              const Loader(padding: 6)
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _decide(approve: false),
                      icon: const Icon(Icons.close_rounded, size: 17),
                      label: const Text('Reject'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: bos.danger,
                        side:
                            BorderSide(color: bos.danger.withValues(alpha: 0.4)),
                        minimumSize: const Size.fromHeight(42),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _decide(approve: true),
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Approve'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(42),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}

/// What this employee has left of the type they are asking for.
class _BalanceContext extends ConsumerWidget {
  const _BalanceContext({
    required this.employeeId,
    required this.leaveType,
    required this.requestedDays,
  });

  final int employeeId;
  final String leaveType;
  final double requestedDays;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(employeeBalancesProvider(employeeId));

    return async.when(
      loading: () => const Loader(padding: 10),
      // Missing context is not a reason to block a decision — the reviewer
      // may well know the answer without the app's help.
      error: (_, _) => const SizedBox.shrink(),
      data: (balances) {
        LeaveBalance? match;
        for (final balance in balances) {
          if (balance.leaveType == leaveType) match = balance;
        }
        if (match == null) return const SizedBox.shrink();

        final remaining = match.remainingDays;
        // The pending days already include this request, so approving it does
        // not subtract again — what matters is whether the entitlement covers
        // it at all.
        final short = remaining < requestedDays;

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: short ? bos.warningSoft : bos.bgSubtle,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: short ? bos.warning.withValues(alpha: 0.35) : bos.borderLight,
            ),
          ),
          child: Row(
            children: [
              Icon(
                short ? Icons.warning_amber_rounded : Icons.info_outline_rounded,
                size: 16,
                color: short ? bos.warning : bos.muted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  short
                      ? 'Only ${_n(remaining)} of ${_n(match.entitledDays)} days '
                          'remain — this request is for ${_n(requestedDays)}.'
                      : '${_n(remaining)} of ${_n(match.entitledDays)} '
                          '${Fmt.label(leaveType).toLowerCase()} days remaining.',
                  style: TextStyle(
                    color: short ? bos.warning : bos.textSecondary,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _n(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
}
