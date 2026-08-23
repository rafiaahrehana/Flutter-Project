import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/permission_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/paged_list_view.dart';
import '../../shared/widgets/primitives.dart';
import 'finance_models.dart';
import 'finance_repository.dart';

class ExpensesTab extends ConsumerWidget {
  const ExpensesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(expensesProvider.notifier);
    final view = ref.watch(expenseViewProvider);

    return Column(
      children: [
        const _ViewFilter(),
        Expanded(
          child: PagedListView<Expense>(
            async: ref.watch(expensesProvider),
            onRefresh: controller.refresh,
            onLoadMore: () => guardListAction(context, controller.loadMore),
            emptyIcon: Icons.receipt_outlined,
            emptyTitle: switch (view) {
              ExpenseView.mine => 'No claims yet',
              ExpenseView.pending => 'Nothing waiting on you',
              ExpenseView.all => 'No expenses recorded',
            },
            emptyMessage: switch (view) {
              ExpenseView.mine =>
                'Anything you claim back appears here with its status.',
              ExpenseView.pending => 'Claims needing a decision land here.',
              ExpenseView.all => 'Company spend appears here once recorded.',
            },
            errorMessage: 'Could not load expenses.',
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
            itemBuilder: (context, expense) => _ExpenseCard(expense: expense),
          ),
        ),
      ],
    );
  }
}

class _ViewFilter extends ConsumerWidget {
  const _ViewFilter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final selected = ref.watch(expenseViewProvider);

    // Approving is a separate entitlement from seeing your own claims, so the
    // queue views only appear for someone who can act on them.
    final canSeeOthers =
        ref.watch(permissionControllerProvider).has(FinancePermissions.expenseView);

    final views = <({ExpenseView view, String label})>[
      (view: ExpenseView.mine, label: 'Mine'),
      if (canSeeOthers) (view: ExpenseView.pending, label: 'Awaiting approval'),
      if (canSeeOthers) (view: ExpenseView.all, label: 'All'),
    ];

    if (views.length == 1) return const SizedBox(height: 8);

    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        itemCount: views.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final entry = views[index];
          final isSelected = selected == entry.view;
          return GestureDetector(
            onTap: () => ref.read(expenseViewProvider.notifier).set(entry.view),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
              decoration: BoxDecoration(
                color: isSelected ? bos.brand : bos.bgCard,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isSelected ? bos.brand : bos.border),
              ),
              child: Text(
                entry.label,
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

class _ExpenseCard extends ConsumerStatefulWidget {
  const _ExpenseCard({required this.expense});

  final Expense expense;

  @override
  ConsumerState<_ExpenseCard> createState() => _ExpenseCardState();
}

class _ExpenseCardState extends ConsumerState<_ExpenseCard> {
  bool _busy = false;

  Future<void> _decide({required bool approved}) async {
    final notes = await _promptForNotes(approved: approved);
    if (notes == null || !mounted) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final warning = await ref.read(expensesProvider.notifier).decide(
            widget.expense.id,
            approved: approved,
            notes: notes,
          );
      // A budget warning is the whole reason the approve response has a body.
      // Swallowing it would let someone approve a category over budget without
      // ever being told.
      messenger.showSnackBar(
        SnackBar(
          content: Text(warning ?? (approved ? 'Approved.' : 'Rejected.')),
          duration: Duration(seconds: warning == null ? 3 : 6),
        ),
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

  /// Both decisions carry a note. A rejection without a reason leaves the
  /// claimant guessing what to fix; an approval note is what an auditor reads.
  Future<String?> _promptForNotes({required bool approved}) {
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
                    approved
                        ? 'Approve ${Fmt.money(widget.expense.amount)}?'
                        : 'Reject this claim?',
                    style: TextStyle(
                      color: bos.text,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: controller,
                    maxLines: 3,
                    autofocus: true,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: approved ? 'Note' : 'Reason',
                      alignLabelWithHint: true,
                      hintText: approved
                          ? 'Anything an auditor should know'
                          : 'What the claimant needs to change',
                    ),
                    validator: (value) => (value == null || value.trim().isEmpty)
                        ? 'This is kept on the record.'
                        : null,
                  ),
                  const SizedBox(height: 18),
                  ElevatedButton(
                    onPressed: () {
                      if (!(formKey.currentState?.validate() ?? false)) return;
                      Navigator.pop(sheetContext, controller.text.trim());
                    },
                    child: Text(approved ? 'Approve' : 'Reject'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ).whenComplete(controller.dispose);
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final expense = widget.expense;
    // Each button carries its own entitlement, because the backend does:
    // someone may hold one of these and not the other.
    final permissions = ref.watch(permissionControllerProvider);
    final canApprove = permissions.has(FinancePermissions.expenseApprove);
    final canReject = permissions.has(FinancePermissions.expenseReject);
    final canDecide = expense.isPending && (canApprove || canReject);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  expense.headline,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: bos.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              StatusChip(expense.status, dense: true),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [
              expense.expenseNumber,
              if (expense.category != null) Fmt.label(expense.category),
              if (expense.vendorName != null) expense.vendorName!,
            ].join('  ·  '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: bos.muted, fontSize: 11.5),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                Fmt.money(expense.amount),
                style: TextStyle(
                  color: bos.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    Fmt.date(expense.expenseDate),
                    style: TextStyle(color: bos.textSecondary, fontSize: 12.5),
                  ),
                  if (expense.submittedByName != null)
                    Text(
                      expense.submittedByName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: bos.muted, fontSize: 11.5),
                    ),
                ],
              ),
            ],
          ),
          if (expense.awaitingReimbursement) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.schedule_rounded, size: 14, color: bos.info),
                const SizedBox(width: 5),
                Text(
                  'Approved — awaiting reimbursement',
                  style: TextStyle(
                    color: bos.info,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
          if (expense.isPaid && expense.reimbursedDate != null) ...[
            const SizedBox(height: 10),
            Text(
              'Reimbursed ${Fmt.date(expense.reimbursedDate)}'
              '${expense.reimbursementMethod != null ? ' by ${Fmt.label(expense.reimbursementMethod)}' : ''}',
              style: TextStyle(color: bos.success, fontSize: 11.5),
            ),
          ],
          if (expense.approvalNotes != null &&
              expense.approvalNotes!.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '“${expense.approvalNotes!}”'
              '${expense.approvedByName != null ? ' — ${expense.approvedByName}' : ''}',
              style: TextStyle(
                color: bos.textSecondary,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ],
          if (canDecide) ...[
            const SizedBox(height: 14),
            if (_busy)
              const Loader(padding: 6)
            else
              Row(
                children: [
                  if (canReject)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _decide(approved: false),
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
                  if (canReject && canApprove) const SizedBox(width: 10),
                  if (canApprove)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _decide(approved: true),
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
