import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/permission_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/paged_list_view.dart';
import '../../shared/widgets/primitives.dart';
import 'application_detail_screen.dart';
import 'interview_feedback_sheet.dart';
import 'recruitment_models.dart';
import 'recruitment_repository.dart';

/// Hiring.
///
/// Postings and applications are separate entitlements — somebody may manage
/// job adverts without reviewing candidates, or the reverse — so each tab is
/// gated on its own and disappears rather than erroring.
class RecruitmentScreen extends ConsumerWidget {
  const RecruitmentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final permissions = ref.watch(permissionControllerProvider);

    if (!permissions.loaded && permissions.codes.isEmpty) {
      return Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(title: const Text('Hiring')),
        body: const Loader(),
      );
    }

    final canJobs = permissions.has(RecruitmentPermissions.jobView);
    final canApplications =
        permissions.has(RecruitmentPermissions.applicationView);

    final tabs = <({String label, Widget view})>[
      if (canJobs) (label: 'Jobs', view: const _JobsTab()),
      if (canApplications) ...[
        (label: 'Applicants', view: const _ApplicationsTab()),
        // Interviews are gated on the application permissions, not their own.
        (label: 'Interviews', view: const _InterviewsTab()),
      ],
    ];

    if (tabs.isEmpty) {
      return Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(title: const Text('Hiring')),
        body: const EmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Not available to you',
          message:
              'Job postings and applications each need their own permission. '
              'Your HR team can grant them.',
        ),
      );
    }

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(
          title: const Text('Hiring'),
          bottom: TabBar(tabs: [for (final t in tabs) Tab(text: t.label)]),
        ),
        body: TabBarView(children: [for (final t in tabs) t.view]),
      ),
    );
  }
}

// ── Jobs ──────────────────────────────────────────────────────

class _JobsTab extends ConsumerWidget {
  const _JobsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PagedListView<JobPosting>(
      async: ref.watch(jobsProvider),
      onRefresh: () => ref.read(jobsProvider.notifier).refresh(),
      onLoadMore: () => ref.read(jobsProvider.notifier).loadMore(),
      emptyTitle: 'No job postings',
      emptyMessage: 'Roles your team is hiring for appear here.',
      emptyIcon: Icons.work_outline_rounded,
      errorMessage: 'Could not load job postings.',
      itemBuilder: (context, job) => _JobCard(job: job),
    );
  }
}

class _JobCard extends ConsumerStatefulWidget {
  const _JobCard({required this.job});

  final JobPosting job;

  @override
  ConsumerState<_JobCard> createState() => _JobCardState();
}

class _JobCardState extends ConsumerState<_JobCard> {
  bool _busy = false;

  Future<void> _run(Future<JobPosting> Function() action, String success) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final updated = await action();
      ref.read(jobsProvider.notifier).apply(updated);
      messenger.showSnackBar(SnackBar(content: Text(success)));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not change that posting.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _close() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Close ${widget.job.title}?'),
        content: const Text(
          'It stops accepting applications and comes off the careers page. '
          'Applications already in the pipeline are unaffected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Close posting'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(
      () => ref.read(recruitmentRepositoryProvider).closeJob(widget.job.id),
      '${widget.job.title} is closed.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final job = widget.job;
    final canUpdate = ref
        .watch(permissionControllerProvider)
        .has(RecruitmentPermissions.jobUpdate);

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
                        job.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: bos.text,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (job.departmentName != null)
                        Text(
                          job.departmentName!,
                          style: TextStyle(
                            color: bos.textSecondary,
                            fontSize: 12.5,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                StatusChip(job.status, dense: true),
              ],
            ),
            const SizedBox(height: 9),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                if (job.whereLabel != null)
                  _Meta(icon: Icons.place_outlined, text: job.whereLabel!),
                if (job.employmentType != null)
                  _Meta(
                    icon: Icons.schedule_outlined,
                    text: Fmt.label(job.employmentType),
                  ),
                _Meta(
                  icon: Icons.groups_outlined,
                  text: job.vacancies == 1
                      ? '1 vacancy'
                      : '${job.vacancies} vacancies',
                ),
              ],
            ),
            if (job.deadlinePassed) ...[
              const SizedBox(height: 10),
              MessageBanner.warning(
                'The deadline passed on ${Fmt.date(job.deadline)} but this '
                'posting is still open.',
              ),
            ],
            if (canUpdate && (job.canPublish || job.canClose)) ...[
              const SizedBox(height: 12),
              if (_busy)
                const Loader(padding: 6)
              else
                Wrap(
                  spacing: 8,
                  children: [
                    if (job.canPublish)
                      FilledButton.icon(
                        onPressed: () => _run(
                          () => ref
                              .read(recruitmentRepositoryProvider)
                              .publishJob(job.id),
                          '${job.title} is live.',
                        ),
                        icon: const Icon(Icons.publish_rounded, size: 16),
                        label: Text(job.isDraft ? 'Publish' : 'Reopen'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 36),
                        ),
                      ),
                    if (job.canClose)
                      OutlinedButton.icon(
                        onPressed: _close,
                        icon: const Icon(Icons.block_rounded, size: 16),
                        label: const Text('Close'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: bos.danger,
                          side: BorderSide(
                            color: bos.danger.withValues(alpha: 0.4),
                          ),
                          minimumSize: const Size(0, 36),
                        ),
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

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: bos.muted),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(color: bos.muted, fontSize: 11.5)),
      ],
    );
  }
}

// ── Applications ──────────────────────────────────────────────

class _ApplicationsTab extends ConsumerWidget {
  const _ApplicationsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        const _StageFilter(),
        Expanded(
          child: PagedListView<JobApplication>(
            async: ref.watch(applicationsProvider),
            onRefresh: () => ref.read(applicationsProvider.notifier).refresh(),
            onLoadMore: () => ref.read(applicationsProvider.notifier).loadMore(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            emptyTitle: 'No applicants',
            emptyMessage: 'Nobody has applied at this stage yet.',
            emptyIcon: Icons.person_search_outlined,
            errorMessage: 'Could not load applications.',
            itemBuilder: (context, application) =>
                _ApplicationRow(application: application),
          ),
        ),
      ],
    );
  }
}

class _StageFilter extends ConsumerWidget {
  const _StageFilter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(applicationFilterProvider);
    const stages = ApplicationStatus.pipeline;

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        itemCount: stages.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final status = i == 0 ? null : stages[i - 1];
          return _FilterChip(
            label: status == null ? 'All' : Fmt.label(status),
            active: selected == status,
            onTap: () => ref
                .read(applicationFilterProvider.notifier)
                .set(selected == status ? null : status),
          );
        },
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
        decoration: BoxDecoration(
          color: active ? bos.brand : bos.bgCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? bos.brand : bos.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : bos.textSecondary,
            fontSize: 12,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _ApplicationRow extends StatelessWidget {
  const _ApplicationRow({required this.application});

  final JobApplication application;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => ApplicationDetailScreen.open(context, id: application.id),
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
                          application.personLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: bos.text,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (application.jobPostingTitle != null)
                          Text(
                            application.jobPostingTitle!,
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
                  StatusChip(application.status, dense: true),
                ],
              ),
              if (application.overallScore != null ||
                  application.atsScore != null) ...[
                const SizedBox(height: 9),
                Row(
                  children: [
                    if (application.overallScore != null)
                      _Meta(
                        icon: Icons.star_outline_rounded,
                        text:
                            'Scored ${application.overallScore!.toStringAsFixed(1)}',
                      ),
                    if (application.overallScore != null &&
                        application.atsScore != null)
                      const SizedBox(width: 12),
                    if (application.atsScore != null)
                      _Meta(
                        icon: Icons.auto_awesome_outlined,
                        text: 'CV match ${application.atsScore}',
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Interviews ────────────────────────────────────────────────

class _InterviewsTab extends ConsumerWidget {
  const _InterviewsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PagedListView<Interview>(
      async: ref.watch(upcomingInterviewsProvider),
      onRefresh: () => ref.read(upcomingInterviewsProvider.notifier).refresh(),
      onLoadMore: () => ref.read(upcomingInterviewsProvider.notifier).loadMore(),
      emptyTitle: 'Nothing scheduled',
      emptyMessage: 'Interviews still to happen appear here, soonest first.',
      emptyIcon: Icons.event_available_outlined,
      errorMessage: 'Could not load interviews.',
      itemBuilder: (context, interview) =>
          InterviewCard(interview: interview, showApplicant: true),
    );
  }
}
