import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/permission_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/primitives.dart';
import 'interview_feedback_sheet.dart';
import 'recruitment_models.dart';
import 'recruitment_repository.dart';

/// One applicant: who they are, where they are in the pipeline, and what has
/// happened to them so far.
///
/// The hub for the module — interviews and offers both hang off an application
/// rather than standing alone, so this is where they are shown and acted on.
class ApplicationDetailScreen extends ConsumerStatefulWidget {
  const ApplicationDetailScreen({super.key, required this.id});

  final int id;

  static void open(BuildContext context, {required int id}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ApplicationDetailScreen(id: id)),
    );
  }

  @override
  ConsumerState<ApplicationDetailScreen> createState() =>
      _ApplicationDetailScreenState();
}

class _ApplicationDetailScreenState
    extends ConsumerState<ApplicationDetailScreen> {
  JobApplication? _application;
  Object? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final application =
          await ref.read(recruitmentRepositoryProvider).application(widget.id);
      if (!mounted) return;
      setState(() {
        _application = application;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  Future<void> _run(
    Future<JobApplication> Function() action,
    String success,
  ) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final updated = await action();
      ref.read(applicationsProvider.notifier).apply(updated);
      if (!mounted) return;
      setState(() => _application = updated);
      messenger.showSnackBar(SnackBar(content: Text(success)));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not update this application.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _moveStage() async {
    final application = _application;
    if (application == null) return;

    final chosen = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => _StagePicker(application: application),
    );
    if (chosen == null || !mounted) return;

    await _run(
      () => ref
          .read(recruitmentRepositoryProvider)
          .setApplicationStatus(application.id, chosen),
      'Moved to ${Fmt.label(chosen).toLowerCase()}.',
    );
  }

  Future<void> _score() async {
    final application = _application;
    if (application == null) return;

    final scores = await showModalBottomSheet<Map<String, int>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ScoreSheet(application: application),
    );
    if (scores == null || !mounted) return;

    await _run(
      () => ref.read(recruitmentRepositoryProvider).evaluate(
            application.id,
            education: scores['education'],
            experience: scores['experience'],
            technicalSkills: scores['technical'],
            interview: scores['interview'],
            communication: scores['communication'],
          ),
      'Scores saved.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final application = _application;
    final canUpdate = ref
        .watch(permissionControllerProvider)
        .has(RecruitmentPermissions.applicationUpdate);

    if (_error != null && application == null) {
      return Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(title: const Text('Applicant')),
        body: ErrorState(
          message: _error is ApiException
              ? (_error! as ApiException).message
              : 'Could not load this application.',
          onRetry: _load,
        ),
      );
    }

    if (application == null) {
      return Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(title: const Text('Applicant')),
        body: const Loader(),
      );
    }

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(title: Text(application.personLabel)),
      body: RefreshIndicator(
        color: bos.brand,
        backgroundColor: bos.bgCard,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _Header(application: application),
            const SizedBox(height: 14),
            _Contact(application: application),
            if (canUpdate && !application.isTerminal) ...[
              const SizedBox(height: 16),
              if (_busy)
                const Loader(padding: 8)
              else
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _moveStage,
                        icon: const Icon(Icons.arrow_forward_rounded, size: 17),
                        label: const Text('Move stage'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(44),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _score,
                        icon: const Icon(Icons.star_outline_rounded, size: 17),
                        label: const Text('Score'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(44),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
            if (application.isHired) ...[
              const SizedBox(height: 14),
              const MessageBanner.success(
                'This applicant has been hired and now has an employee record.',
              ),
            ],
            if (application.hasScores) ...[
              const SizedBox(height: 20),
              _Scores(application: application),
            ],
            const SizedBox(height: 20),
            _Interviews(applicationId: application.id),
            const SizedBox(height: 20),
            _Offers(applicationId: application.id),
            if (application.notes?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 20),
              const SectionHeader('Notes', icon: Icons.sticky_note_2_outlined),
              AppCard(
                child: Text(
                  application.notes!.trim(),
                  style: TextStyle(color: bos.text, fontSize: 13, height: 1.4),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.application});

  final JobApplication application;

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
                      application.personLabel,
                      style: TextStyle(
                        color: bos.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (application.jobPostingTitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'for ${application.jobPostingTitle}',
                        style: TextStyle(
                          color: bos.textSecondary,
                          fontSize: 13.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusChip(application.status),
            ],
          ),
          if (application.source != null || application.atsScore != null) ...[
            const SizedBox(height: 12),
            Divider(height: 1, color: bos.borderLight),
            const SizedBox(height: 12),
            Row(
              children: [
                if (application.source != null) ...[
                  Icon(Icons.input_rounded, size: 14, color: bos.muted),
                  const SizedBox(width: 5),
                  Text(
                    'Via ${Fmt.label(application.source).toLowerCase()}',
                    style: TextStyle(color: bos.muted, fontSize: 12),
                  ),
                ],
                if (application.atsScore != null) ...[
                  const Spacer(),
                  Icon(Icons.auto_awesome_outlined, size: 14, color: bos.muted),
                  const SizedBox(width: 5),
                  Text(
                    'CV match ${application.atsScore}',
                    style: TextStyle(color: bos.muted, fontSize: 12),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Contact extends StatelessWidget {
  const _Contact({required this.application});

  final JobApplication application;

  Future<void> _open(BuildContext context, Uri uri, String failure) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        messenger.showSnackBar(SnackBar(content: Text(failure)));
      }
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(failure)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = application.candidateEmail?.trim();
    final phone = application.candidatePhone?.trim();
    final resume = application.resumeUrl?.trim();

    final actions = <Widget>[
      if (phone != null && phone.isNotEmpty)
        _Action(
          icon: Icons.call_rounded,
          label: 'Call',
          onTap: () => _open(
            context,
            Uri(scheme: 'tel', path: phone),
            'No app on this device can place a call.',
          ),
        ),
      if (email != null && email.isNotEmpty)
        _Action(
          icon: Icons.mail_outline_rounded,
          label: 'Email',
          onTap: () => _open(
            context,
            Uri(scheme: 'mailto', path: email),
            'No mail app is set up on this device.',
          ),
        ),
      if (resume != null && resume.isNotEmpty)
        _Action(
          icon: Icons.description_outlined,
          label: 'CV',
          onTap: () => _open(
            context,
            Uri.parse(resume),
            'Could not open that CV.',
          ),
        ),
    ];

    if (actions.isEmpty) {
      return const AppCard(
        child: MessageBanner.info('No contact details on this application.'),
      );
    }

    return Row(
      children: [
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: actions[i]),
        ],
      ],
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 17),
      label: Text(label),
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
    );
  }
}

class _Scores extends StatelessWidget {
  const _Scores({required this.application});

  final JobApplication application;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    final rows = <({String label, int? value})>[
      (label: 'Education', value: application.scoreEducation),
      (label: 'Experience', value: application.scoreExperience),
      (label: 'Technical skills', value: application.scoreTechnicalSkills),
      (label: 'Interview', value: application.scoreInterview),
      (label: 'Communication', value: application.scoreCommunication),
    ].where((r) => r.value != null).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Scores',
          icon: Icons.star_outline_rounded,
          trailing: application.overallScore == null
              ? null
              : Text(
                  application.overallScore!.toStringAsFixed(1),
                  style: TextStyle(
                    color: bos.brand,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
        AppCard(
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        rows[i].label,
                        style: TextStyle(color: bos.textSecondary, fontSize: 13),
                      ),
                    ),
                    Text(
                      '${rows[i].value}',
                      style: TextStyle(
                        color: bos.text,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
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

class _Interviews extends ConsumerWidget {
  const _Interviews({required this.applicationId});

  final int applicationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(applicationInterviewsProvider(applicationId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Interviews', icon: Icons.event_outlined),
        async.when(
          loading: () => const Loader(padding: 8),
          error: (_, _) => const AppCard(
            child: MessageBanner.info('Could not load interviews.'),
          ),
          data: (interviews) {
            if (interviews.isEmpty) {
              return const AppCard(
                child: MessageBanner.info(
                  'No interviews yet. Scheduling one is done on the web.',
                ),
              );
            }
            return Column(
              children: [
                for (final interview in interviews)
                  InterviewCard(
                    interview: interview,
                    onChanged: (_) => ref.invalidate(
                      applicationInterviewsProvider(applicationId),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Offers extends ConsumerStatefulWidget {
  const _Offers({required this.applicationId});

  final int applicationId;

  @override
  ConsumerState<_Offers> createState() => _OffersState();
}

class _OffersState extends ConsumerState<_Offers> {
  int? _busyOffer;

  Future<void> _transition(JobOffer offer, String action, String success) async {
    setState(() => _busyOffer = offer.id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(recruitmentRepositoryProvider)
          .offerTransition(offer.id, action);
      ref.invalidate(applicationOffersProvider(widget.applicationId));
      messenger.showSnackBar(SnackBar(content: Text(success)));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not update that offer.')),
      );
    } finally {
      if (mounted) setState(() => _busyOffer = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(applicationOffersProvider(widget.applicationId));
    final canUpdate = ref
        .watch(permissionControllerProvider)
        .has(RecruitmentPermissions.applicationUpdate);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Offers', icon: Icons.description_outlined),
        async.when(
          loading: () => const Loader(padding: 8),
          error: (_, _) =>
              const AppCard(child: MessageBanner.info('Could not load offers.')),
          data: (offers) {
            if (offers.isEmpty) {
              return const AppCard(
                child: MessageBanner.info(
                  'No offer yet. Writing one — with its salary breakdown — is '
                  'done on the web.',
                ),
              );
            }
            return Column(
              children: [
                for (final offer in offers)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  offer.offeredJobTitle ?? 'Offer',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: bos.text,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              StatusChip(offer.displayStatus, dense: true),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (offer.grossSalary != null)
                            Text(
                              '${Fmt.money(offer.grossSalary)} gross',
                              style: TextStyle(
                                color: bos.text,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          if (offer.joiningDate != null)
                            Text(
                              'Starting ${Fmt.date(offer.joiningDate)}',
                              style: TextStyle(color: bos.muted, fontSize: 12),
                            ),
                          if (offer.expired && offer.isSent) ...[
                            const SizedBox(height: 9),
                            MessageBanner.warning(
                              'This offer lapsed on ${Fmt.date(offer.expiryDate)} '
                              'without an answer.',
                            ),
                          ],
                          if (offer.declineReason?.trim().isNotEmpty ==
                              true) ...[
                            const SizedBox(height: 8),
                            Text(
                              offer.declineReason!.trim(),
                              style: TextStyle(
                                color: bos.textSecondary,
                                fontSize: 12.5,
                                height: 1.35,
                              ),
                            ),
                          ],
                          if (canUpdate && !offer.isSettled) ...[
                            const SizedBox(height: 12),
                            if (_busyOffer == offer.id)
                              const Loader(padding: 6)
                            else
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  if (offer.isDraft)
                                    FilledButton.icon(
                                      onPressed: () => _transition(
                                        offer,
                                        'send',
                                        'Offer sent.',
                                      ),
                                      icon: const Icon(Icons.send_rounded,
                                          size: 15),
                                      label: const Text('Send'),
                                      style: FilledButton.styleFrom(
                                        minimumSize: const Size(0, 36),
                                      ),
                                    ),
                                  // Accept and decline record what the
                                  // candidate said, so they only make sense
                                  // once the offer has actually gone out.
                                  if (offer.isSent) ...[
                                    FilledButton.icon(
                                      onPressed: () => _transition(
                                        offer,
                                        'accept',
                                        'Recorded as accepted.',
                                      ),
                                      icon: const Icon(Icons.check_rounded,
                                          size: 15),
                                      label: const Text('Accepted'),
                                      style: FilledButton.styleFrom(
                                        minimumSize: const Size(0, 36),
                                      ),
                                    ),
                                    OutlinedButton.icon(
                                      onPressed: () => _transition(
                                        offer,
                                        'decline',
                                        'Recorded as declined.',
                                      ),
                                      icon: const Icon(Icons.close_rounded,
                                          size: 15),
                                      label: const Text('Declined'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: bos.danger,
                                        side: BorderSide(
                                          color: bos.danger
                                              .withValues(alpha: 0.4),
                                        ),
                                        minimumSize: const Size(0, 36),
                                      ),
                                    ),
                                  ],
                                  OutlinedButton(
                                    onPressed: () => _transition(
                                      offer,
                                      'withdraw',
                                      'Offer withdrawn.',
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: bos.muted,
                                      minimumSize: const Size(0, 36),
                                    ),
                                    child: const Text('Withdraw'),
                                  ),
                                ],
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Where to move an application next.
class _StagePicker extends StatelessWidget {
  const _StagePicker({required this.application});

  final JobApplication application;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final options = application.nextStatuses;

    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 10),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Text(
              'Move to',
              style: TextStyle(
                color: bos.text,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          for (final status in options)
            ListTile(
              leading: StatusChip(status, dense: true),
              title: Text(Fmt.label(status)),
              onTap: () => Navigator.pop(context, status),
            ),
        ],
      ),
    );
  }
}

/// The five manual scores. All optional — the backend averages whichever are
/// present, so a half-filled sheet is a valid submission.
class _ScoreSheet extends StatefulWidget {
  const _ScoreSheet({required this.application});

  final JobApplication application;

  @override
  State<_ScoreSheet> createState() => _ScoreSheetState();
}

class _ScoreSheetState extends State<_ScoreSheet> {
  late final Map<String, int?> _scores = {
    'education': widget.application.scoreEducation,
    'experience': widget.application.scoreExperience,
    'technical': widget.application.scoreTechnicalSkills,
    'interview': widget.application.scoreInterview,
    'communication': widget.application.scoreCommunication,
  };

  static const _labels = {
    'education': 'Education',
    'experience': 'Experience',
    'technical': 'Technical skills',
    'interview': 'Interview',
    'communication': 'Communication',
  };

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
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
            'Score ${widget.application.personLabel}',
            style: TextStyle(
              color: bos.text,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            'Out of 10. Leave any blank that you cannot judge.',
            style: TextStyle(color: bos.muted, fontSize: 12.5),
          ),
          const SizedBox(height: 18),
          for (final entry in _labels.entries) ...[
            Text(
              entry.value,
              style: TextStyle(
                color: bos.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: (_scores[entry.key] ?? 0).toDouble(),
                    min: 0,
                    max: 10,
                    divisions: 10,
                    label: '${_scores[entry.key] ?? 0}',
                    onChanged: (v) => setState(
                      () => _scores[entry.key] = v.round() == 0 ? null : v.round(),
                    ),
                  ),
                ),
                SizedBox(
                  width: 28,
                  child: Text(
                    _scores[entry.key]?.toString() ?? '—',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: bos.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(context, <String, int>{
                for (final entry in _scores.entries)
                  if (entry.value != null) entry.key: entry.value!,
              }),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text('Save scores'),
            ),
          ),
        ],
      ),
    );
  }
}
