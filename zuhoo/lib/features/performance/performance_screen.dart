import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/permission_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/paged_list_view.dart';
import '../../shared/widgets/primitives.dart';
import 'performance_models.dart';
import 'performance_repository.dart';
import 'review_detail_screen.dart';

/// Performance reviews.
///
/// The personal tab is never gated: the backend lets anyone read their own
/// appraisal whatever permissions they hold, and deliberately so. Only the
/// team tab needs PERFORMANCE_VIEW, which means "may see other people's".
class PerformanceScreen extends ConsumerWidget {
  const PerformanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final canSeeTeam =
        ref.watch(permissionControllerProvider).has(PerformancePermissions.view);

    final tabs = <({String label, Widget view})>[
      (label: 'My reviews', view: const _MyReviewsTab()),
      if (canSeeTeam) (label: 'Team', view: const _TeamTab()),
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(
          title: const Text('Performance'),
          bottom: tabs.length == 1
              ? null
              : TabBar(tabs: [for (final t in tabs) Tab(text: t.label)]),
        ),
        body: tabs.length == 1
            ? tabs.first.view
            : TabBarView(children: [for (final t in tabs) t.view]),
      ),
    );
  }
}

class _MyReviewsTab extends ConsumerWidget {
  const _MyReviewsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(myReviewsProvider);

    return RefreshIndicator(
      color: bos.brand,
      backgroundColor: bos.bgCard,
      onRefresh: () async => ref.invalidate(myReviewsProvider),
      child: async.when(
        loading: () => const Loader(),
        error: (error, _) => ErrorState(
          message: error is ApiException
              ? error.message
              : 'Could not load your reviews.',
          onRetry: () => ref.invalidate(myReviewsProvider),
        ),
        data: (reviews) {
          if (reviews.isEmpty) {
            return ListView(
              children: const [
                SizedBox(height: 70),
                // Covers both "not reviewed yet" and "no employee record",
                // because from the reader's side they look the same: there is
                // nothing of theirs to show.
                EmptyState(
                  icon: Icons.insights_outlined,
                  title: 'No reviews yet',
                  message:
                      'Appraisals written about you appear here once HR '
                      'starts one.',
                ),
              ],
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
            itemCount: reviews.length,
            itemBuilder: (context, i) =>
                _ReviewRow(review: reviews[i], showPerson: false),
          );
        },
      ),
    );
  }
}

class _TeamTab extends ConsumerWidget {
  const _TeamTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PagedListView<PerformanceReview>(
      async: ref.watch(teamReviewsProvider),
      onRefresh: () => ref.read(teamReviewsProvider.notifier).refresh(),
      onLoadMore: () => ref.read(teamReviewsProvider.notifier).loadMore(),
      emptyTitle: 'No reviews',
      emptyMessage: 'Appraisals across the company appear here.',
      emptyIcon: Icons.insights_outlined,
      errorMessage: 'Could not load reviews.',
      itemBuilder: (context, review) => _ReviewRow(review: review),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({required this.review, this.showPerson = true});

  final PerformanceReview review;
  final bool showPerson;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => ReviewDetailScreen.open(context, review: review),
        child: AppCard(
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
                          showPerson
                              ? review.personLabel
                              : (review.period == null
                                  ? 'Review'
                                  : '${Fmt.date(review.reviewPeriodStart)} – '
                                      '${Fmt.date(review.reviewPeriodEnd)}'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: bos.text,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          showPerson && review.period != null
                              ? '${Fmt.date(review.reviewPeriodStart)} – '
                                  '${Fmt.date(review.reviewPeriodEnd)}'
                              : (review.reviewedByName == null
                                  ? review.stageLabel
                                  : 'Reviewed by ${review.reviewedByName}'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: bos.textSecondary,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (review.overallScore != null)
                    _ScorePill(score: review.overallScore!),
                ],
              ),
              const SizedBox(height: 11),
              _StageBar(review: review),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScorePill extends StatelessWidget {
  const _ScorePill({required this.score});

  final double score;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    // Bands rather than a gradient: an appraisal score is read as a verdict,
    // and three tones say more than ten shades.
    final tone = score >= 8
        ? bos.success
        : score >= 5
            ? bos.brandInk
            : bos.warning;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        score.toStringAsFixed(1),
        style: TextStyle(
          color: tone,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Where the review has got to, as five dots rather than a chip — the stage is
/// a position in a sequence, and a chip loses that.
class _StageBar extends StatelessWidget {
  const _StageBar({required this.review});

  final PerformanceReview review;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final reached = review.stageIndex;

    return Row(
      children: [
        for (var i = 0; i < PerformanceStage.ordered.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 2,
                color: i <= reached ? bos.brand : bos.borderLight,
              ),
            ),
          Container(
            height: 9,
            width: 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i <= reached ? bos.brand : bos.borderLight,
            ),
          ),
        ],
        const SizedBox(width: 10),
        Text(
          review.finalised ? 'Finalised' : review.stageLabel,
          style: TextStyle(
            color: review.finalised ? bos.success : bos.textSecondary,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
