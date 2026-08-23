import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/primitives.dart';
import 'request_controllers.dart';
import 'request_models.dart';
import 'request_repository.dart';

/// Opens one request. Pushed rather than routed by path so the list it came
/// from stays exactly where it was, scroll position included.
void openRequestDetail(BuildContext context, int id) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => RequestDetailScreen(id: id)),
  );
}

class RequestDetailScreen extends ConsumerWidget {
  const RequestDetailScreen({super.key, required this.id});

  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(requestDetailProvider(id));

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(
        title: const Text('Request'),
        actions: [
          if (async.value?.canCancel ?? false)
            IconButton(
              tooltip: 'Withdraw',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () => _withdraw(context, ref, async.value!),
            ),
        ],
      ),
      body: async.when(
        loading: () => const Loader(),
        error: (error, _) => ErrorState(
          message: error is ApiException
              ? error.message
              : 'Could not load that request.',
          onRetry: () => ref.invalidate(requestDetailProvider(id)),
        ),
        data: (request) => RefreshIndicator(
          color: bos.brand,
          backgroundColor: bos.bgCard,
          onRefresh: () async {
            ref.invalidate(requestDetailProvider(id));
            ref.invalidate(requestCommentsProvider(id));
            ref.invalidate(requestHistoryProvider(id));
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              _Header(request: request),
              const SizedBox(height: 20),
              _Facts(request: request),
              if (request.description != null &&
                  request.description!.trim().isNotEmpty) ...[
                const SizedBox(height: 20),
                const SectionHeader('Description', icon: Icons.notes_rounded),
                AppCard(
                  child: Text(
                    request.description!,
                    style: TextStyle(
                      color: bos.textSecondary,
                      fontSize: 14,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
              if (request.hasQuotation) ...[
                const SizedBox(height: 20),
                _Quotation(request: request),
              ],
              const SizedBox(height: 20),
              _Comments(id: id),
              const SizedBox(height: 20),
              _Timeline(id: id),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _withdraw(
    BuildContext context,
    WidgetRef ref,
    ServiceRequest request,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Withdraw this request?'),
        content: Text('"${request.title}" will be cancelled.'),
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
    final navigator = Navigator.of(context);
    try {
      await ref.read(myRequestsProvider.notifier).cancel(request.id);
      ref.invalidate(requestDetailProvider(request.id));
      messenger.showSnackBar(
        const SnackBar(content: Text('Request withdrawn.')),
      );
      navigator.pop();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.request});

  final ServiceRequest request;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final progress = request.taskProgress;

    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  request.title,
                  style: TextStyle(
                    color: bos.text,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              StatusChip(request.status),
            ],
          ),
          if (request.hubServiceName != null) ...[
            const SizedBox(height: 6),
            Text(
              request.hubServiceName!,
              style: TextStyle(color: bos.muted, fontSize: 13),
            ),
          ],
          if (request.slaBreach) ...[
            const SizedBox(height: 14),
            MessageBanner.error('This request is past its SLA deadline.'),
          ],
          if (progress != null) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  'Tasks',
                  style: TextStyle(
                    color: bos.textSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  '${request.completedTaskCount} of ${request.taskCount} done',
                  style: TextStyle(color: bos.muted, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: bos.neutralSoft,
                valueColor: AlwaysStoppedAnimation(bos.brand),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Facts extends StatelessWidget {
  const _Facts({required this.request});

  final ServiceRequest request;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    final rows = <({String label, String? value})>[
      (label: 'Priority', value: Fmt.label(request.priority)),
      (label: 'Raised', value: Fmt.date(request.createdAt)),
      (
        label: 'SLA deadline',
        value: request.slaDeadline == null ? null : Fmt.date(request.slaDeadline)
      ),
      (label: 'Assigned to', value: request.assignedEmployeeName),
      (
        label: 'Assigned',
        value: request.assignedAt == null ? null : Fmt.date(request.assignedAt)
      ),
      (label: 'Client', value: request.clientName),
      (label: 'Package', value: request.packageName),
      (
        label: 'Agreed price',
        value: request.agreedPrice == null ? null : Fmt.money(request.agreedPrice)
      ),
      (
        label: 'Filing reference',
        value: request.govRefNumber == null
            ? null
            : '${request.govRefNumber}'
                '${request.govRefType != null ? ' (${Fmt.label(request.govRefType)})' : ''}'
      ),
      (
        label: 'Completed',
        value: request.completedAt == null ? null : Fmt.date(request.completedAt)
      ),
      (
        label: 'Resubmitted',
        value: request.resubmitCount > 0 ? '${request.resubmitCount}×' : null
      ),
    ].where((row) => row.value != null && row.value!.isNotEmpty).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Details', icon: Icons.info_outline_rounded),
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
      ],
    );
  }
}

/// The quotation lives on the request itself. Read-only here: accepting or
/// rejecting one creates an invoice and starts a payment, which belongs with
/// the billing flow rather than bolted onto a detail screen.
class _Quotation extends StatelessWidget {
  const _Quotation({required this.request});

  final ServiceRequest request;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Quotation', icon: Icons.request_quote_outlined),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    Fmt.money(request.quotationAmount),
                    style: TextStyle(
                      color: bos.text,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const Spacer(),
                  StatusChip(request.quotationStatus ?? 'PENDING', dense: true),
                ],
              ),
              if (request.quotationValidUntil != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Valid until ${Fmt.date(request.quotationValidUntil)}',
                  style: TextStyle(color: bos.muted, fontSize: 12.5),
                ),
              ],
              if (request.quotationNotes != null &&
                  request.quotationNotes!.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  request.quotationNotes!,
                  style: TextStyle(
                    color: bos.textSecondary,
                    fontSize: 13.5,
                    height: 1.4,
                  ),
                ),
              ],
              if (request.quotationAwaitsDecision) ...[
                const SizedBox(height: 12),
                MessageBanner.info(
                  'Accepting or declining this quotation raises an invoice, so '
                  'it is done from the web app for now.',
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Comments extends ConsumerStatefulWidget {
  const _Comments({required this.id});

  final int id;

  @override
  ConsumerState<_Comments> createState() => _CommentsState();
}

class _CommentsState extends ConsumerState<_Comments> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(requestRepositoryProvider).addComment(widget.id, text);
      _controller.clear();
      ref.invalidate(requestCommentsProvider(widget.id));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not post that comment.')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(requestCommentsProvider(widget.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Comments', icon: Icons.forum_outlined),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              async.when(
                loading: () => const Loader(padding: 12),
                error: (_, _) => Text(
                  'Could not load the conversation.',
                  style: TextStyle(color: bos.muted, fontSize: 13),
                ),
                data: (comments) {
                  if (comments.isEmpty) {
                    return Text(
                      'No comments yet.',
                      style: TextStyle(color: bos.muted, fontSize: 13.5),
                    );
                  }
                  return Column(
                    children: [
                      for (var i = 0; i < comments.length; i++) ...[
                        if (i > 0) const SizedBox(height: 14),
                        _Comment(comment: comments[i]),
                      ],
                    ],
                  );
                },
              ),
              const SizedBox(height: 14),
              Divider(height: 1, color: bos.borderLight),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      maxLines: 4,
                      minLines: 1,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Write a comment',
                        isDense: true,
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    style: IconButton.styleFrom(backgroundColor: bos.brand),
                    icon: _sending
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send_rounded,
                            size: 18, color: Colors.white),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Comment extends StatelessWidget {
  const _Comment({required this.comment});

  final RequestComment comment;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Avatar(
          initials: _initials(comment.authorName),
          size: 30,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      comment.authorName ?? 'Someone',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: bos.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    Fmt.relative(comment.createdAt),
                    style: TextStyle(color: bos.muted, fontSize: 11),
                  ),
                  // An internal note is staff-only. Labelling it is what stops
                  // someone reading it aloud to a client on a call.
                  if (comment.isInternal) ...[
                    const SizedBox(width: 8),
                    const StatusChip('INTERNAL', label: 'Internal', dense: true),
                  ],
                ],
              ),
              const SizedBox(height: 3),
              Text(
                comment.content,
                style: TextStyle(
                  color: bos.textSecondary,
                  fontSize: 13.5,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _initials(String? name) {
    final parts =
        (name ?? '').trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}

class _Timeline extends ConsumerWidget {
  const _Timeline({required this.id});

  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(requestHistoryProvider(id));
    final history = async.value;

    // Absent history is not an error worth a panel: an employee without the
    // permission to read it simply does not get this section.
    if (history == null || history.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('History', icon: Icons.history_rounded),
        AppCard(
          child: Column(
            children: [
              for (var i = 0; i < history.length; i++)
                _TimelineRow(
                  change: history[i],
                  isFirst: i == 0,
                  isLast: i == history.length - 1,
                  railColor: bos.border,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.change,
    required this.isFirst,
    required this.isLast,
    required this.railColor,
  });

  final RequestStatusChange change;
  final bool isFirst;
  final bool isLast;
  final Color railColor;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final colors = bos.statusColors(change.newStatus);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A rail rather than a plain list: the order of status changes is the
          // information here, and a column of rows does not convey sequence.
          SizedBox(
            width: 22,
            child: Column(
              children: [
                Container(
                  width: 2,
                  height: 6,
                  color: isFirst ? Colors.transparent : railColor,
                ),
                Container(
                  height: 10,
                  width: 10,
                  decoration: BoxDecoration(
                    color: colors.fg,
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: Container(
                    width: 2,
                    color: isLast ? Colors.transparent : railColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          change.oldStatus == null
                              ? Fmt.label(change.newStatus)
                              : '${Fmt.label(change.oldStatus)} → ${Fmt.label(change.newStatus)}',
                          style: TextStyle(
                            color: bos.text,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        Fmt.relative(change.changedAt),
                        style: TextStyle(color: bos.muted, fontSize: 11),
                      ),
                    ],
                  ),
                  if (change.changedByName != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'by ${change.changedByName}',
                      style: TextStyle(color: bos.muted, fontSize: 11.5),
                    ),
                  ],
                  if (change.reason != null && change.reason!.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      change.reason!,
                      style: TextStyle(
                        color: bos.textSecondary,
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
