import 'package:flutter/material.dart';

import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/primitives.dart';
import 'support_models.dart';

class TicketCard extends StatelessWidget {
  const TicketCard({
    super.key,
    required this.ticket,
    this.onTap,
    this.showRaisedBy = false,
  });

  final SupportTicket ticket;
  final VoidCallback? onTap;

  /// The client-chat inbox cares who raised it; the "my tickets" list does not,
  /// because the answer is always the person reading.
  final bool showRaisedBy;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

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
                  ticket.title,
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
              StatusChip(ticket.status, dense: true),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                ticket.ticketNumber,
                style: TextStyle(
                  color: bos.muted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
              if (ticket.categoryName != null) ...[
                Text(
                  '  ·  ${ticket.categoryName}',
                  style: TextStyle(color: bos.muted, fontSize: 11.5),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _PriorityDot(priority: ticket.priority),
              const SizedBox(width: 6),
              Text(
                Fmt.label(ticket.priority),
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
                Fmt.relative(ticket.createdAt),
                style: TextStyle(color: bos.muted, fontSize: 12),
              ),
              const Spacer(),
              if (showRaisedBy && ticket.createdByName != null)
                Flexible(
                  child: Text(
                    ticket.createdByName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(color: bos.muted, fontSize: 12),
                  ),
                )
              else if (ticket.handlerName != null)
                Flexible(
                  child: Text(
                    ticket.handlerName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(color: bos.muted, fontSize: 12),
                  ),
                ),
            ],
          ),
          if (ticket.slaBreached || ticket.isEscalated || ticket.isUnassigned) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (ticket.slaBreached)
                  _Flag(
                    icon: Icons.warning_amber_rounded,
                    label: 'SLA breached',
                    colour: bos.danger,
                  ),
                if (ticket.isEscalated)
                  _Flag(
                    icon: Icons.trending_up_rounded,
                    label: 'Escalated L${ticket.escalationLevel}',
                    colour: bos.warning,
                  ),
                // Only worth flagging while there is still something to do
                // about it — an unassigned closed ticket needs nobody.
                if (ticket.isUnassigned && ticket.isOpen)
                  _Flag(
                    icon: Icons.person_off_outlined,
                    label: 'Unassigned',
                    colour: bos.muted,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Flag extends StatelessWidget {
  const _Flag({required this.icon, required this.label, required this.colour});

  final IconData icon;
  final String label;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: colour),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: colour,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _PriorityDot extends StatelessWidget {
  const _PriorityDot({required this.priority});

  final String priority;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final color = switch (priority) {
      'CRITICAL' => bos.danger,
      'HIGH' => bos.warning,
      'MEDIUM' => bos.info,
      _ => bos.muted,
    };

    return Container(
      height: 8,
      width: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
