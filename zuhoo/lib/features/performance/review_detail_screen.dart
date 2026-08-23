import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/permission_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/primitives.dart';
import 'performance_models.dart';
import 'performance_repository.dart';

/// One appraisal in full.
class ReviewDetailScreen extends ConsumerStatefulWidget {
  const ReviewDetailScreen({super.key, required this.review});

  final PerformanceReview review;

  static void open(BuildContext context, {required PerformanceReview review}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ReviewDetailScreen(review: review)),
    );
  }

  @override
  ConsumerState<ReviewDetailScreen> createState() => _ReviewDetailScreenState();
}

class _ReviewDetailScreenState extends ConsumerState<ReviewDetailScreen> {
  late PerformanceReview _review = widget.review;
  bool _busy = false;

  Future<void> _run(
    Future<PerformanceReview> Function() action,
    String success,
  ) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final updated = await action();
      ref.read(teamReviewsProvider.notifier).apply(updated);
      ref.invalidate(myReviewsProvider);
      if (!mounted) return;
      setState(() => _review = updated);
      messenger.showSnackBar(SnackBar(content: Text(success)));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not update this review.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finalise() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Finalise this review?'),
        content: Text(
          'It becomes a signed record for ${_review.personLabel} and cannot be '
          'changed or reopened afterwards.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not yet'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Finalise'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await _run(
      () => ref.read(performanceRepositoryProvider).finalise(_review.id),
      'Review finalised.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final review = _review;
    final canUpdate = ref
        .watch(permissionControllerProvider)
        .has(PerformancePermissions.update);

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(title: Text(review.personLabel)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _Header(review: review),
          if (canUpdate && (review.canAdvance || review.canFinalise)) ...[
            const SizedBox(height: 16),
            if (_busy)
              const Loader(padding: 8)
            else
              Row(
                children: [
                  if (review.canAdvance)
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _run(
                          () => ref
                              .read(performanceRepositoryProvider)
                              .advance(review.id),
                          'Moved on.',
                        ),
                        icon: const Icon(Icons.arrow_forward_rounded, size: 17),
                        label: const Text('Advance stage'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(44),
                        ),
                      ),
                    ),
                  if (review.canFinalise)
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _finalise,
                        icon: const Icon(Icons.lock_outline_rounded, size: 17),
                        label: const Text('Finalise'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(44),
                        ),
                      ),
                    ),
                ],
              ),
          ],
          if (review.hasScores) ...[
            const SizedBox(height: 20),
            _Scores(review: review),
          ],
          if (review.goalCompletionPercent != null) ...[
            const SizedBox(height: 16),
            _Goals(percent: review.goalCompletionPercent!),
          ],
          for (final section in review.narrative) ...[
            const SizedBox(height: 18),
            SectionHeader(section.title, icon: Icons.notes_rounded),
            AppCard(
              child: Text(
                section.body,
                style: TextStyle(color: bos.text, fontSize: 13.5, height: 1.45),
              ),
            ),
          ],
          if (review.aiSummary?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 18),
            const SectionHeader(
              'Summary',
              icon: Icons.auto_awesome_outlined,
            ),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Labelled every time it is shown. A machine's précis of
                  // somebody's year must never be mistaken for their manager's
                  // words.
                  Text(
                    'Written by the assistant, not by a person.',
                    style: TextStyle(
                      color: bos.muted,
                      fontSize: 11.5,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    review.aiSummary!.trim(),
                    style: TextStyle(
                      color: bos.text,
                      fontSize: 13.5,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          _Trail(review: review),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.review});

  final PerformanceReview review;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return AppCard(
      padding: const EdgeInsets.all(18),
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
                      review.period == null
                          ? 'Review'
                          : '${Fmt.date(review.reviewPeriodStart)} – '
                              '${Fmt.date(review.reviewPeriodEnd)}',
                      style: TextStyle(
                        color: bos.text,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (review.reviewedByName != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Reviewed by ${review.reviewedByName}',
                        style: TextStyle(
                          color: bos.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (review.overallScore != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      review.overallScore!.toStringAsFixed(1),
                      style: TextStyle(
                        color: bos.brand,
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        height: 1,
                      ),
                    ),
                    Text(
                      'overall',
                      style: TextStyle(color: bos.muted, fontSize: 11),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              StatusChip(
                review.finalised ? 'COMPLETED' : review.stage,
                label: review.finalised ? 'Finalised' : review.stageLabel,
                dense: true,
              ),
              if (review.performanceLevel != null) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    Fmt.label(review.performanceLevel),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: bos.textSecondary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (review.promotionRecommendation != null ||
              review.promotionReadiness != null) ...[
            const SizedBox(height: 12),
            Divider(height: 1, color: bos.borderLight),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.trending_up_rounded, size: 15, color: bos.muted),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    [
                      if (review.promotionRecommendation != null)
                        Fmt.label(review.promotionRecommendation),
                      if (review.promotionReadiness != null)
                        Fmt.label(review.promotionReadiness),
                    ].join(' · '),
                    style: TextStyle(color: bos.textSecondary, fontSize: 12.5),
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

class _Scores extends StatelessWidget {
  const _Scores({required this.review});

  final PerformanceReview review;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final scores = review.filledScores;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Scores', icon: Icons.equalizer_rounded),
        AppCard(
          child: Column(
            children: [
              for (var i = 0; i < scores.length; i++) ...[
                if (i > 0) const SizedBox(height: 13),
                Row(
                  children: [
                    SizedBox(
                      width: 118,
                      child: Text(
                        scores[i].label,
                        style: TextStyle(
                          color: bos.textSecondary,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          // Scores are out of 10 throughout the appraisal form.
                          value: (scores[i].value! / 10).clamp(0, 1).toDouble(),
                          minHeight: 5,
                          backgroundColor: bos.neutralSoft,
                          valueColor: AlwaysStoppedAnimation(bos.brand),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 26,
                      child: Text(
                        '${scores[i].value}',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: bos.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
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

class _Goals extends StatelessWidget {
  const _Goals({required this.percent});

  final int percent;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return AppCard(
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Goals completed',
              style: TextStyle(color: bos.textSecondary, fontSize: 13),
            ),
          ),
          Text(
            '$percent%',
            style: TextStyle(
              color: percent >= 80
                  ? bos.success
                  : percent >= 50
                      ? bos.brandInk
                      : bos.warning,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Who signed off which stage and when. The five timestamps in the payload are
/// the audit trail of an appraisal, so they get shown rather than dropped.
class _Trail extends StatelessWidget {
  const _Trail({required this.review});

  final PerformanceReview review;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    if (review.createdAt == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('History', icon: Icons.history_rounded),
        AppCard(
          child: Row(
            children: [
              Icon(Icons.schedule_rounded, size: 14, color: bos.muted),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Started ${Fmt.dateTime(review.createdAt)}',
                  style: TextStyle(color: bos.muted, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
