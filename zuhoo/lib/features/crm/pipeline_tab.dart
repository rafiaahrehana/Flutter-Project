import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/paged_list_view.dart';
import '../../shared/widgets/primitives.dart';
import 'crm_controllers.dart';
import 'crm_models.dart';
import 'opportunity_detail_screen.dart';

/// The pipeline.
///
/// Not a kanban board. Dragging cards between columns is the right interaction
/// on a desk and the wrong one on a phone — the columns are too narrow to read
/// and the drag target is too small to hit. The same information works better
/// as a summary you can scan plus a list you can filter by stage, and moving a
/// deal becomes an explicit action on the deal itself.
class PipelineTab extends ConsumerWidget {
  const PipelineTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(opportunitiesProvider.notifier);

    return Column(
      children: [
        const _SummaryStrip(),
        const _StageFilter(),
        Expanded(
          child: PagedListView<Opportunity>(
            async: ref.watch(opportunitiesProvider),
            onRefresh: () async {
              ref.invalidate(pipelineSummaryProvider);
              await controller.refresh();
            },
            onLoadMore: () => guardListAction(context, controller.loadMore),
            emptyIcon: Icons.trending_up_rounded,
            emptyTitle: 'No deals here',
            emptyMessage: 'Opportunities in this stage will show up here.',
            errorMessage: 'Could not load your pipeline.',
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
            itemBuilder: (context, opportunity) => _OpportunityCard(
              opportunity: opportunity,
              onTap: () => openOpportunity(context, opportunity.id),
            ),
          ),
        ),
      ],
    );
  }
}

class _SummaryStrip extends ConsumerWidget {
  const _SummaryStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final summary = ref.watch(pipelineSummaryProvider).value;

    // Absent until it lands; a strip of dashes would be noisier than nothing.
    if (summary == null) return const SizedBox.shrink();

    final figures = <({String label, String value, Color tone})>[
      (
        label: 'Open pipeline',
        value: Fmt.money(summary.openPipelineValue),
        tone: bos.brandInk
      ),
      (
        label: 'Weighted',
        value: Fmt.money(summary.weightedForecast),
        tone: bos.info
      ),
      (label: 'Won', value: Fmt.money(summary.wonValue), tone: bos.success),
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bos.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: bos.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              for (var i = 0; i < figures.length; i++) ...[
                if (i > 0)
                  Container(width: 1, height: 30, color: bos.borderLight),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        figures[i].value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: figures[i].tone,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        figures[i].label,
                        style: TextStyle(color: bos.muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${summary.totalOpenDeals} open deal'
            '${summary.totalOpenDeals == 1 ? '' : 's'}',
            style: TextStyle(color: bos.muted, fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}

class _StageFilter extends ConsumerWidget {
  const _StageFilter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final selected = ref.watch(pipelineStageProvider);
    final summary = ref.watch(pipelineSummaryProvider).value;

    // Won and Lost are reachable here but not on the default view: the
    // pipeline is what is still in play, and a rep scrolling past a year of
    // closed deals to find an open one is the failure this avoids.
    const stages = <String?>[null, ...Stage.open, Stage.won, Stage.lost];

    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        itemCount: stages.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final stage = stages[index];
          final isSelected = selected == stage;
          final count = stage == null
              ? summary?.totalOpenDeals
              : summary?.forStage(stage)?.dealCount;

          return GestureDetector(
            onTap: () => ref.read(pipelineStageProvider.notifier).set(stage),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
              decoration: BoxDecoration(
                color: isSelected ? bos.brand : bos.bgCard,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? bos.brand : bos.border,
                ),
              ),
              child: Row(
                children: [
                  Text(
                    stage == null ? 'All open' : Fmt.label(stage),
                    style: TextStyle(
                      color: isSelected ? Colors.white : bos.textSecondary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (count != null && count > 0) ...[
                    const SizedBox(width: 6),
                    Text(
                      '$count',
                      style: TextStyle(
                        color: isSelected
                            ? Colors.white.withValues(alpha: 0.85)
                            : bos.muted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _OpportunityCard extends StatelessWidget {
  const _OpportunityCard({required this.opportunity, this.onTap});

  final Opportunity opportunity;
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
                  opportunity.name,
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
              StatusChip(opportunity.stage, dense: true),
            ],
          ),
          if (opportunity.clientCompanyName != null ||
              opportunity.contactName != null) ...[
            const SizedBox(height: 4),
            Text(
              opportunity.clientCompanyName ?? opportunity.contactName!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: bos.muted, fontSize: 12.5),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    Fmt.money(opportunity.amount),
                    style: TextStyle(
                      color: bos.text,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                  ),
                  if (opportunity.weightedAmount != null)
                    Text(
                      '${Fmt.money(opportunity.weightedAmount)} weighted',
                      style: TextStyle(color: bos.muted, fontSize: 11.5),
                    ),
                ],
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${opportunity.probability}%',
                    style: TextStyle(
                      color: bos.brandInk,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (opportunity.expectedCloseDate != null)
                    Text(
                      Fmt.dateShort(opportunity.expectedCloseDate),
                      style: TextStyle(
                        color: opportunity.isOverdue ? bos.danger : bos.muted,
                        fontSize: 11.5,
                        fontWeight: opportunity.isOverdue
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                    ),
                ],
              ),
            ],
          ),
          if (opportunity.isOverdue) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.event_busy_rounded, size: 14, color: bos.danger),
                const SizedBox(width: 5),
                Text(
                  'Past its expected close date',
                  style: TextStyle(
                    color: bos.danger,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
          if (opportunity.nextStep != null &&
              opportunity.nextStep!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.arrow_forward_rounded, size: 14, color: bos.muted),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    opportunity.nextStep!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: bos.muted, fontSize: 12),
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
