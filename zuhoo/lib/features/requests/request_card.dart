import 'package:flutter/material.dart';

import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/primitives.dart';
import 'request_models.dart';

/// One row in any of the request lists.
class RequestCard extends StatelessWidget {
  const RequestCard({super.key, required this.request, this.onTap});

  final ServiceRequest request;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final progress = request.taskProgress;

    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  request.title,
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
              StatusChip(request.status, dense: true),
            ],
          ),
          if (request.hubServiceName != null) ...[
            const SizedBox(height: 4),
            Text(
              request.hubServiceName!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: bos.muted, fontSize: 12.5),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              _PriorityDot(priority: request.priority),
              const SizedBox(width: 6),
              Text(
                Fmt.label(request.priority),
                style: TextStyle(
                  color: bos.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 12),
              Icon(Icons.schedule_rounded, size: 13, color: bos.muted),
              const SizedBox(width: 4),
              Text(
                Fmt.relative(request.createdAt),
                style: TextStyle(color: bos.muted, fontSize: 12),
              ),
              const Spacer(),
              if (request.assignedEmployeeName != null)
                Flexible(
                  child: Text(
                    request.assignedEmployeeName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(color: bos.muted, fontSize: 12),
                  ),
                ),
            ],
          ),
          // The server decides whether an SLA is breached; it knows the working
          // calendar, so this is shown rather than recomputed from the deadline.
          if (request.slaBreach) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 15, color: bos.danger),
                const SizedBox(width: 6),
                Text(
                  'Past its SLA deadline',
                  style: TextStyle(
                    color: bos.danger,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
          if (progress != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 5,
                      backgroundColor: bos.neutralSoft,
                      valueColor: AlwaysStoppedAnimation(bos.brand),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${request.completedTaskCount}/${request.taskCount} tasks',
                  style: TextStyle(color: bos.muted, fontSize: 11.5),
                ),
              ],
            ),
          ],
          if (request.quotationAwaitsDecision) ...[
            const SizedBox(height: 10),
            MessageBanner.info(
              'Quotation of ${Fmt.money(request.quotationAmount)} is awaiting a decision.',
            ),
          ],
        ],
      ),
    );
  }
}

/// Priority as a coloured dot rather than another pill — the status chip is
/// already the loudest thing on the row, and two competing badges make neither
/// readable at a glance.
class _PriorityDot extends StatelessWidget {
  const _PriorityDot({required this.priority});

  final String priority;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final color = switch (priority) {
      'URGENT' => bos.danger,
      'HIGH' => bos.warning,
      'NORMAL' => bos.info,
      _ => bos.muted,
    };

    return Container(
      height: 8,
      width: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
