import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/paged_list_view.dart';
import '../../shared/widgets/primitives.dart';
import 'request_controllers.dart';
import 'request_detail_screen.dart';
import 'request_models.dart';

class ApprovalsTab extends ConsumerWidget {
  const ApprovalsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(approvalsProvider.notifier);

    return PagedListView<StageApproval>(
      async: ref.watch(approvalsProvider),
      onRefresh: controller.refresh,
      onLoadMore: () => guardListAction(context, controller.loadMore),
      emptyIcon: Icons.task_alt_rounded,
      emptyTitle: 'Nothing waiting on you',
      emptyMessage: 'Workflow stages needing your decision appear here.',
      errorMessage: 'Could not load your approvals.',
      itemBuilder: (context, approval) => _ApprovalCard(approval: approval),
    );
  }
}

class _ApprovalCard extends ConsumerStatefulWidget {
  const _ApprovalCard({required this.approval});

  final StageApproval approval;

  @override
  ConsumerState<_ApprovalCard> createState() => _ApprovalCardState();
}

class _ApprovalCardState extends ConsumerState<_ApprovalCard> {
  bool _busy = false;

  Future<void> _decide({required bool approved}) async {
    // A rejection has to say why: the backend requires the notes, and an
    // unexplained rejection tells whoever picks this up next nothing about
    // what to change. An approval may be silent.
    String? notes;
    if (!approved) {
      notes = await _askForReason();
      if (notes == null) return;
    } else {
      notes = await _askForOptionalNote();
      // A dismissed sheet cancels the whole action rather than approving with
      // no note — the two are easy to confuse at a glance.
      if (notes == null) return;
    }

    if (!mounted) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await ref.read(approvalsProvider.notifier).decide(
            widget.approval.id,
            approved: approved,
            notes: notes.isEmpty ? null : notes,
          );
      messenger.showSnackBar(
        SnackBar(content: Text(approved ? 'Approved.' : 'Rejected.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not record that decision.')),
      );
    } finally {
      // On success this card has already been removed from the list and is
      // disposed, so the guard matters: without it a card that somehow stays
      // on screen would keep its spinner forever with no way back.
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askForReason() => _promptForNotes(
        title: 'Why are you rejecting this?',
        hint: 'What needs to change before this can go ahead',
        confirmLabel: 'Reject',
        required: true,
      );

  Future<String?> _askForOptionalNote() => _promptForNotes(
        title: 'Approve this stage?',
        hint: 'Add a note (optional)',
        confirmLabel: 'Approve',
        required: false,
      );

  Future<String?> _promptForNotes({
    required String title,
    required String hint,
    required String confirmLabel,
    required bool required,
  }) {
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
                    title,
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
                      labelText: required ? 'Reason' : 'Note',
                      hintText: hint,
                      alignLabelWithHint: true,
                    ),
                    validator: (value) {
                      if (!required) return null;
                      return (value == null || value.trim().isEmpty)
                          ? 'Say why, so this can be acted on.'
                          : null;
                    },
                  ),
                  const SizedBox(height: 18),
                  ElevatedButton(
                    onPressed: () {
                      if (!(formKey.currentState?.validate() ?? false)) return;
                      Navigator.pop(sheetContext, controller.text.trim());
                    },
                    child: Text(confirmLabel),
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
    final approval = widget.approval;

    return AppCard(
      onTap: () => openRequestDetail(context, approval.serviceRequestId),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  approval.serviceRequestTitle ??
                      'Request #${approval.serviceRequestId}',
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
              StatusChip(approval.status, dense: true),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.route_rounded, size: 14, color: bos.muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  [
                    if (approval.stageOrder != null)
                      'Stage ${approval.stageOrder}',
                    if (approval.workflowStageName != null)
                      approval.workflowStageName!,
                    if (approval.approverRole != null)
                      'as ${Fmt.label(approval.approverRole)}',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: bos.textSecondary, fontSize: 12.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [
              if (approval.requestedByName != null)
                'Raised by ${approval.requestedByName}',
              Fmt.relative(approval.createdAt),
            ].join(' · '),
            style: TextStyle(color: bos.muted, fontSize: 11.5),
          ),
          const SizedBox(height: 14),
          if (_busy)
            const Loader(padding: 6)
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _decide(approved: false),
                    icon: const Icon(Icons.close_rounded, size: 17),
                    label: const Text('Reject'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: bos.danger,
                      side: BorderSide(color: bos.danger.withValues(alpha: 0.4)),
                      minimumSize: const Size.fromHeight(42),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
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
      ),
    );
  }
}
