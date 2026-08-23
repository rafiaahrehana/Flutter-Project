import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/paged_list_view.dart';
import '../../shared/widgets/primitives.dart';
import 'crm_controllers.dart';
import 'crm_models.dart';
import 'crm_repository.dart';
import 'lead_detail_screen.dart';

class LeadsTab extends ConsumerWidget {
  const LeadsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(leadsProvider.notifier);

    return Column(
      children: [
        const _ViewFilter(),
        Expanded(
          child: PagedListView<Lead>(
            async: ref.watch(leadsProvider),
            onRefresh: controller.refresh,
            onLoadMore: () => guardListAction(context, controller.loadMore),
            emptyIcon: Icons.person_search_rounded,
            emptyTitle: 'No leads here',
            emptyMessage: _emptyMessageFor(ref.watch(leadViewProvider)),
            errorMessage: 'Could not load your leads.',
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
            itemBuilder: (context, lead) => _LeadCard(
              lead: lead,
              onTap: () => openLead(context, lead.id),
            ),
          ),
        ),
      ],
    );
  }

  /// Each view is empty for a different reason, and "nothing to show" reads
  /// very differently when it means "you have no leads" versus "nothing has
  /// gone stale".
  static String _emptyMessageFor(LeadView view) => switch (view) {
        LeadView.mine => 'Leads assigned to you will appear here.',
        LeadView.all => 'Leads captured from any source will appear here.',
        LeadView.highPriority => 'Nothing is flagged high priority right now.',
        LeadView.neverContacted =>
          'Every lead has been contacted at least once — good.',
        LeadView.stale => 'Nothing has gone quiet. Nothing to chase.',
        LeadView.unassigned => 'Every lead has an owner.',
      };
}

class _ViewFilter extends ConsumerWidget {
  const _ViewFilter();

  static const _views = <({LeadView view, String label})>[
    (view: LeadView.mine, label: 'Mine'),
    (view: LeadView.all, label: 'All'),
    (view: LeadView.highPriority, label: 'High priority'),
    (view: LeadView.neverContacted, label: 'Never contacted'),
    (view: LeadView.stale, label: 'Stale'),
    (view: LeadView.unassigned, label: 'Unassigned'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final selected = ref.watch(leadViewProvider);

    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        itemCount: _views.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final entry = _views[index];
          final isSelected = selected == entry.view;

          return GestureDetector(
            onTap: () => ref.read(leadViewProvider.notifier).set(entry.view),
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

class _LeadCard extends StatelessWidget {
  const _LeadCard({required this.lead, this.onTap});

  final Lead lead;
  final VoidCallback? onTap;

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
                  lead.headline,
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
              StatusChip(lead.status, dense: true),
            ],
          ),
          if (lead.subline != null) ...[
            const SizedBox(height: 3),
            Text(
              lead.subline!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: bos.muted, fontSize: 12.5),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              if (lead.priority != null) ...[
                _PriorityDot(priority: lead.priority!),
                const SizedBox(width: 6),
                Text(
                  Fmt.label(lead.priority),
                  style: TextStyle(
                    color: bos.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 12),
              ],
              if (lead.estimatedValue != null) ...[
                Text(
                  Fmt.money(lead.estimatedValue),
                  style: TextStyle(
                    color: bos.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 12),
              ],
              const Spacer(),
              Text(
                lead.neverContacted
                    ? 'Never contacted'
                    : Fmt.relative(lead.lastActivityAt ?? lead.lastContactDate),
                style: TextStyle(
                  color: lead.neverContacted ? bos.warning : bos.muted,
                  fontSize: 11.5,
                  fontWeight:
                      lead.neverContacted ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
          if (lead.converted || lead.isUnassigned || lead.tags.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (lead.converted)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_outline_rounded,
                          size: 14, color: bos.success),
                      const SizedBox(width: 4),
                      Text(
                        lead.convertedClientName == null
                            ? 'Converted'
                            : 'Converted → ${lead.convertedClientName}',
                        style: TextStyle(
                          color: bos.success,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                if (lead.isUnassigned && !lead.converted)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.person_off_outlined,
                          size: 14, color: bos.muted),
                      const SizedBox(width: 4),
                      Text(
                        'Unassigned',
                        style: TextStyle(
                          color: bos.muted,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                for (final tag in lead.tags.take(3)) TagChip(tag: tag),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// A CRM tag, in the colour the user picked for it.
class TagChip extends StatelessWidget {
  const TagChip({super.key, required this.tag});

  final Tag tag;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final argb = tag.argb;
    // A tag whose stored colour will not parse still has to render — falling
    // back to the neutral token beats dropping the tag or throwing.
    final colour = argb == null ? bos.muted : Color(argb);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colour.withValues(alpha: 0.4)),
      ),
      child: Text(
        tag.name,
        style: TextStyle(
          color: bos.isDark ? bos.text : colour,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
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
