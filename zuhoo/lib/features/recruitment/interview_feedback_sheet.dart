import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/permission_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/primitives.dart';
import 'recruitment_models.dart';
import 'recruitment_repository.dart';

/// One interview, with the two things you do to it between meetings: leave
/// feedback, or call it off.
class InterviewCard extends ConsumerStatefulWidget {
  const InterviewCard({
    super.key,
    required this.interview,
    this.showApplicant = false,
    this.onChanged,
  });

  final Interview interview;

  /// The upcoming list needs to say who the interview is with; the list inside
  /// an application already knows.
  final bool showApplicant;

  final void Function(Interview updated)? onChanged;

  @override
  ConsumerState<InterviewCard> createState() => _InterviewCardState();
}

class _InterviewCardState extends ConsumerState<InterviewCard> {
  bool _busy = false;

  Future<void> _feedback() async {
    final result = await showModalBottomSheet<_FeedbackResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FeedbackSheet(interview: widget.interview),
    );
    if (result == null || !mounted) return;

    await _run(
      () => ref.read(recruitmentRepositoryProvider).submitFeedback(
            widget.interview.id,
            rating: result.rating,
            strengths: result.strengths,
            concerns: result.concerns,
            recommendation: result.recommendation,
            noShow: result.noShow,
          ),
      result.noShow ? 'Recorded as a no-show.' : 'Feedback saved.',
    );
  }

  Future<void> _cancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this interview?'),
        content: const Text(
          'The slot is released. Nobody is notified by the app — tell the '
          'candidate yourself.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel interview'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await _run(
      () => ref
          .read(recruitmentRepositoryProvider)
          .cancelInterview(widget.interview.id),
      'Interview cancelled.',
    );
  }

  Future<void> _run(Future<Interview> Function() action, String success) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final updated = await action();
      ref.read(upcomingInterviewsProvider.notifier).apply(updated);
      widget.onChanged?.call(updated);
      messenger.showSnackBar(SnackBar(content: Text(success)));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not update that interview.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final interview = widget.interview;
    final canUpdate = ref
        .watch(permissionControllerProvider)
        .has(RecruitmentPermissions.applicationUpdate);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
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
                        widget.showApplicant
                            ? (interview.applicantName ?? 'Interview')
                            : Fmt.label(interview.round ?? 'Interview'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: bos.text,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        widget.showApplicant
                            ? [
                                if (interview.round != null)
                                  Fmt.label(interview.round),
                                if (interview.jobTitle != null)
                                  interview.jobTitle!,
                              ].join(' · ')
                            : (interview.interviewerName ?? ''),
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
                if (interview.isToday && interview.isScheduled)
                  const StatusChip('IN_PROGRESS', label: 'Today', dense: true)
                else
                  StatusChip(interview.status, dense: true),
              ],
            ),
            const SizedBox(height: 9),
            Row(
              children: [
                Icon(Icons.event_outlined, size: 13, color: bos.muted),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    [
                      Fmt.dateTime(interview.scheduledAt),
                      if (interview.durationMinutes != null)
                        '${interview.durationMinutes} min',
                      if (interview.mode != null) Fmt.label(interview.mode),
                    ].join(' · '),
                    style: TextStyle(color: bos.muted, fontSize: 11.5),
                  ),
                ),
              ],
            ),
            if (interview.awaitingFeedback) ...[
              const SizedBox(height: 10),
              const MessageBanner.warning(
                'This slot has passed and no feedback has been left yet.',
              ),
            ],
            if (interview.hasFeedback) ...[
              const SizedBox(height: 10),
              _FeedbackSummary(interview: interview),
            ],
            if (canUpdate && interview.isScheduled) ...[
              const SizedBox(height: 12),
              if (_busy)
                const Loader(padding: 6)
              else
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _feedback,
                        icon: const Icon(Icons.rate_review_outlined, size: 16),
                        label: const Text('Feedback'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 38),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: _cancel,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: bos.danger,
                        side: BorderSide(
                          color: bos.danger.withValues(alpha: 0.4),
                        ),
                        minimumSize: const Size(0, 38),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FeedbackSummary extends StatelessWidget {
  const _FeedbackSummary({required this.interview});

  final Interview interview;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: bos.bgSubtle,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (interview.rating != null) ...[
                Icon(Icons.star_rounded, size: 15, color: bos.warning),
                const SizedBox(width: 4),
                Text(
                  '${interview.rating}',
                  style: TextStyle(
                    color: bos.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              if (interview.recommendation != null)
                Text(
                  Fmt.label(interview.recommendation),
                  style: TextStyle(
                    color: bos.textSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          if (interview.strengths?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 6),
            Text(
              interview.strengths!.trim(),
              style: TextStyle(color: bos.text, fontSize: 12.5, height: 1.35),
            ),
          ],
          if (interview.concerns?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 4),
            Text(
              interview.concerns!.trim(),
              style: TextStyle(
                color: bos.textSecondary,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FeedbackResult {
  const _FeedbackResult({
    this.rating,
    this.strengths,
    this.concerns,
    this.recommendation,
    this.noShow = false,
  });

  final int? rating;
  final String? strengths;
  final String? concerns;
  final String? recommendation;
  final bool noShow;
}

/// The recommendations the backend accepts, strongest first.
const _recommendations = [
  'STRONG_HIRE',
  'HIRE',
  'NEUTRAL',
  'NO_HIRE',
  'STRONG_NO_HIRE',
];

class _FeedbackSheet extends StatefulWidget {
  const _FeedbackSheet({required this.interview});

  final Interview interview;

  @override
  State<_FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends State<_FeedbackSheet> {
  final _strengths = TextEditingController();
  final _concerns = TextEditingController();
  int? _rating;
  String? _recommendation;
  bool _noShow = false;

  @override
  void dispose() {
    _strengths.dispose();
    _concerns.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (context, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          children: [
            Center(
              child: Container(
                height: 4,
                width: 38,
                decoration: BoxDecoration(
                  color: bos.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Interview feedback',
              style: TextStyle(
                color: bos.text,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (widget.interview.applicantName != null)
              Text(
                widget.interview.applicantName!,
                style: TextStyle(color: bos.textSecondary, fontSize: 13),
              ),
            const SizedBox(height: 18),

            // A no-show is not a bad interview, it is an absent one, so it
            // hides the scoring rather than asking for a rating of nothing.
            SwitchListTile(
              value: _noShow,
              onChanged: (v) => setState(() => _noShow = v),
              title: const Text('They did not turn up'),
              contentPadding: EdgeInsets.zero,
            ),

            if (!_noShow) ...[
              const SizedBox(height: 8),
              Text(
                'Rating',
                style: TextStyle(
                  color: bos.textSecondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (var i = 1; i <= 5; i++)
                    IconButton(
                      onPressed: () => setState(() => _rating = i),
                      icon: Icon(
                        (_rating ?? 0) >= i
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        color: (_rating ?? 0) >= i ? bos.warning : bos.border,
                        size: 30,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 44),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Recommendation',
                style: TextStyle(
                  color: bos.textSecondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in _recommendations)
                    ChoiceChip(
                      label: Text(Fmt.label(option)),
                      selected: _recommendation == option,
                      onSelected: (_) => setState(
                        () => _recommendation =
                            _recommendation == option ? null : option,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _strengths,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Strengths',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _concerns,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Concerns',
                  alignLabelWithHint: true,
                ),
              ),
            ],

            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(
                  context,
                  _FeedbackResult(
                    rating: _noShow ? null : _rating,
                    strengths: _noShow ? null : _strengths.text,
                    concerns: _noShow ? null : _concerns.text,
                    recommendation: _noShow ? null : _recommendation,
                    noShow: _noShow,
                  ),
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: Text(_noShow ? 'Record no-show' : 'Save feedback'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
