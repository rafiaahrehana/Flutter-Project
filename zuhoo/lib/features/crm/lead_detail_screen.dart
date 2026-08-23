import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/primitives.dart';
import 'crm_controllers.dart';
import 'crm_models.dart';
import 'crm_repository.dart';
import 'leads_tab.dart' show TagChip;
import 'opportunity_detail_screen.dart';

void openLead(BuildContext context, int id) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => LeadDetailScreen(id: id)),
  );
}

class LeadDetailScreen extends ConsumerStatefulWidget {
  const LeadDetailScreen({super.key, required this.id});

  final int id;

  @override
  ConsumerState<LeadDetailScreen> createState() => _LeadDetailScreenState();
}

class _LeadDetailScreenState extends ConsumerState<LeadDetailScreen> {
  bool _busy = false;

  Future<void> _logActivity() async {
    final entry = await showModalBottomSheet<LogActivityRequest>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _LogActivitySheet(),
    );
    if (entry == null || !mounted) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(crmRepositoryProvider).logActivity(widget.id, entry);
      ref.invalidate(leadActivitiesProvider(widget.id));
      // The lead's own "last contacted" moves with it, so the header and the
      // list card behind this screen are both stale now.
      ref.invalidate(leadDetailProvider(widget.id));
      ref.read(leadsProvider.notifier).refresh();
      messenger.showSnackBar(const SnackBar(content: Text('Activity logged.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not log that activity.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _convert(Lead lead) async {
    final request = await showModalBottomSheet<ConvertLeadRequest>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ConvertLeadSheet(lead: lead),
    );
    if (request == null || !mounted) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final opportunity =
          await ref.read(crmRepositoryProvider).convertLead(lead.id, request);
      ref.invalidate(leadDetailProvider(widget.id));
      ref.read(leadsProvider.notifier).refresh();
      ref.read(opportunitiesProvider.notifier).refresh();
      ref.invalidate(pipelineSummaryProvider);

      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Converted to an opportunity.')),
      );
      // Straight into the new deal: converting is the start of working it, not
      // the end of working the lead.
      openOpportunity(context, opportunity.id);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not convert that lead.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(leadDetailProvider(widget.id));

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(title: const Text('Lead')),
      body: async.when(
        loading: () => const Loader(),
        error: (error, _) => ErrorState(
          message: error is ApiException
              ? error.message
              : 'Could not load that lead.',
          onRetry: () => ref.invalidate(leadDetailProvider(widget.id)),
        ),
        data: (lead) => RefreshIndicator(
          color: bos.brand,
          backgroundColor: bos.bgCard,
          onRefresh: () async {
            ref.invalidate(leadDetailProvider(widget.id));
            ref.invalidate(leadActivitiesProvider(widget.id));
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              _Header(lead: lead),
              const SizedBox(height: 20),
              _Facts(lead: lead),
              const SizedBox(height: 20),
              if (_busy)
                const Loader(padding: 12)
              else
                _Actions(
                  lead: lead,
                  onLogActivity: _logActivity,
                  onConvert: () => _convert(lead),
                ),
              const SizedBox(height: 20),
              _Activities(id: widget.id),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.lead});

  final Lead lead;

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
                      lead.headline,
                      style: TextStyle(
                        color: bos.text,
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                        letterSpacing: -0.3,
                      ),
                    ),
                    if (lead.subline != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        lead.subline!,
                        style: TextStyle(color: bos.muted, fontSize: 13),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              StatusChip(lead.status),
            ],
          ),
          if (lead.tags.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [for (final tag in lead.tags) TagChip(tag: tag)],
            ),
          ],
          if (lead.notes != null && lead.notes!.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              lead.notes!,
              style: TextStyle(
                color: bos.textSecondary,
                fontSize: 14,
                height: 1.45,
              ),
            ),
          ],
          if (lead.converted) ...[
            const SizedBox(height: 14),
            MessageBanner.success(
              lead.convertedClientName == null
                  ? 'This lead has already been converted.'
                  : 'Converted to ${lead.convertedClientName}.',
            ),
          ] else if (lead.possibleDuplicate != null) ...[
            const SizedBox(height: 14),
            MessageBanner.info(
              'Might already be a client: '
              '${lead.possibleDuplicate!.clientCompanyName} '
              '(matched on ${Fmt.label(lead.possibleDuplicate!.matchedOn).toLowerCase()}).',
            ),
          ],
        ],
      ),
    );
  }
}

class _Facts extends StatelessWidget {
  const _Facts({required this.lead});

  final Lead lead;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    final rows = <({String label, String? value})>[
      (label: 'Email', value: lead.email),
      (label: 'Phone', value: lead.phone),
      (label: 'Job title', value: lead.jobTitle),
      (label: 'Industry', value: lead.industry),
      (label: 'Source', value: Fmt.label(lead.source)),
      (
        label: 'Priority',
        value: lead.priority == null ? null : Fmt.label(lead.priority)
      ),
      (
        label: 'Estimated value',
        value:
            lead.estimatedValue == null ? null : Fmt.money(lead.estimatedValue)
      ),
      (
        label: 'Expected close',
        value: lead.expectedCloseDate == null
            ? null
            : Fmt.date(lead.expectedCloseDate)
      ),
      (label: 'Owner', value: lead.assignedToName),
      (
        label: 'Last contacted',
        value: lead.lastContactDate == null
            ? null
            : Fmt.date(lead.lastContactDate)
      ),
      (label: 'Created', value: Fmt.date(lead.createdAt)),
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

class _Actions extends StatelessWidget {
  const _Actions({
    required this.lead,
    required this.onLogActivity,
    required this.onConvert,
  });

  final Lead lead;
  final VoidCallback onLogActivity;
  final VoidCallback onConvert;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: onLogActivity,
          icon: const Icon(Icons.add_comment_outlined, size: 18),
          label: const Text('Log a call, meeting or note'),
        ),
        if (lead.canConvert) ...[
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: onConvert,
            icon: const Icon(Icons.trending_up_rounded, size: 18),
            label: const Text('Convert to opportunity'),
          ),
        ] else if (!lead.converted) ...[
          const SizedBox(height: 10),
          // Said rather than shown greyed out: the reason is specific and
          // actionable, whereas a disabled button just invites tapping.
          Text(
            'Qualify this lead before converting it to an opportunity.',
            textAlign: TextAlign.center,
            style: TextStyle(color: bos.muted, fontSize: 12.5),
          ),
        ],
      ],
    );
  }
}

class _Activities extends ConsumerWidget {
  const _Activities({required this.id});

  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(leadActivitiesProvider(id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Activity', icon: Icons.history_rounded),
        AppCard(
          child: async.when(
            loading: () => const Loader(padding: 12),
            error: (_, _) => Text(
              'Could not load this lead’s activity.',
              style: TextStyle(color: bos.muted, fontSize: 13),
            ),
            data: (activities) {
              if (activities.isEmpty) {
                return Text(
                  'Nothing logged yet.',
                  style: TextStyle(color: bos.muted, fontSize: 13.5),
                );
              }
              return Column(
                children: [
                  for (var i = 0; i < activities.length; i++) ...[
                    if (i > 0) const SizedBox(height: 14),
                    _ActivityRow(activity: activities[i]),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.activity});

  final CrmActivity activity;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    // System entries are the audit trail — a stage change, a status change.
    // Drawn quieter than something a person chose to write down.
    final tone = activity.systemGenerated ? bos.muted : bos.brandInk;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 28,
          width: 28,
          decoration: BoxDecoration(
            color: tone.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(_iconFor(activity.type), size: 15, color: tone),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      activity.subject,
                      style: TextStyle(
                        color: bos.text,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    Fmt.relative(activity.activityDate),
                    style: TextStyle(color: bos.muted, fontSize: 11),
                  ),
                ],
              ),
              if (activity.description != null &&
                  activity.description!.trim().isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  activity.description!,
                  style: TextStyle(
                    color: bos.textSecondary,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
              ],
              const SizedBox(height: 3),
              Text(
                [
                  Fmt.label(activity.type),
                  if (activity.performedByName != null)
                    activity.performedByName!,
                ].join(' · '),
                style: TextStyle(color: bos.muted, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static IconData _iconFor(String type) => switch (type) {
        'CALL' => Icons.phone_outlined,
        'MEETING' => Icons.groups_outlined,
        'EMAIL' => Icons.mail_outline_rounded,
        'TASK' => Icons.check_box_outlined,
        'FOLLOW_UP' => Icons.replay_rounded,
        'STAGE_CHANGE' || 'STATUS_CHANGE' => Icons.swap_horiz_rounded,
        'DOCUMENT' => Icons.description_outlined,
        _ => Icons.sticky_note_2_outlined,
      };
}

class _LogActivitySheet extends StatefulWidget {
  const _LogActivitySheet();

  @override
  State<_LogActivitySheet> createState() => _LogActivitySheetState();
}

class _LogActivitySheetState extends State<_LogActivitySheet> {
  final _formKey = GlobalKey<FormState>();
  final _subject = TextEditingController();
  final _description = TextEditingController();
  String _type = 'CALL';

  @override
  void dispose() {
    _subject.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Log an activity',
                style: TextStyle(
                  color: bos.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 18),
              DropdownButtonFormField<String>(
                initialValue: _type,
                decoration: const InputDecoration(
                  labelText: 'Type',
                  prefixIcon: Icon(Icons.category_outlined),
                ),
                items: [
                  for (final type in crmActivityTypes)
                    DropdownMenuItem(value: type, child: Text(Fmt.label(type))),
                ],
                onChanged: (value) => setState(() => _type = value ?? _type),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _subject,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Summary',
                  hintText: 'Spoke to the finance lead about pricing',
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Say what happened.'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _description,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Detail (optional)',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  if (!(_formKey.currentState?.validate() ?? false)) return;
                  Navigator.pop(
                    context,
                    LogActivityRequest(
                      type: _type,
                      subject: _subject.text,
                      description: _description.text,
                    ),
                  );
                },
                child: const Text('Log it'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConvertLeadSheet extends StatefulWidget {
  const _ConvertLeadSheet({required this.lead});

  final Lead lead;

  @override
  State<_ConvertLeadSheet> createState() => _ConvertLeadSheetState();
}

class _ConvertLeadSheetState extends State<_ConvertLeadSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _value;
  DateTime? _closeDate;

  @override
  void initState() {
    super.initState();
    // Prefilled from the lead: the deal is almost always named after the
    // account, and the estimate is the number already agreed with them.
    _name = TextEditingController(text: widget.lead.headline);
    _value = TextEditingController(
      text: widget.lead.estimatedValue == null
          ? ''
          : widget.lead.estimatedValue!.toStringAsFixed(0),
    );
    final expected = widget.lead.expectedCloseDate;
    _closeDate = expected == null ? null : DateTime.tryParse(expected);
  }

  @override
  void dispose() {
    _name.dispose();
    _value.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _closeDate ?? now.add(const Duration(days: 30)),
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: DateTime(now.year + 3),
    );
    if (picked != null) setState(() => _closeDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Convert to an opportunity',
                style: TextStyle(
                  color: bos.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              // Worth stating: people expect "convert" to create a client, and
              // it does not — that happens only if the deal is later won.
              Text(
                'No client is created yet — that happens if the deal is won.',
                style: TextStyle(color: bos.muted, fontSize: 12.5),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Deal name',
                  prefixIcon: Icon(Icons.title_rounded),
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Give the deal a name.'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _value,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Expected value',
                  prefixIcon: Icon(Icons.payments_outlined),
                ),
                validator: (value) {
                  final parsed = double.tryParse(value?.trim() ?? '');
                  if (parsed == null) return 'Enter a number.';
                  if (parsed <= 0) return 'Enter an amount above zero.';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(8),
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Expected close date',
                    prefixIcon: const Icon(Icons.event_outlined),
                    errorText:
                        _closeDate == null ? 'Pick a date' : null,
                  ),
                  child: Text(
                    _closeDate == null
                        ? 'Choose a date'
                        : Fmt.date(Fmt.isoDate(_closeDate!)),
                    style: TextStyle(
                      color: _closeDate == null ? bos.muted : bos.text,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  final valid = _formKey.currentState?.validate() ?? false;
                  // The date lives outside the Form, so it has to be checked
                  // alongside rather than by it.
                  if (!valid || _closeDate == null) {
                    setState(() {});
                    return;
                  }
                  Navigator.pop(
                    context,
                    ConvertLeadRequest(
                      opportunityName: _name.text,
                      expectedValue: double.parse(_value.text.trim()),
                      expectedCloseDate: Fmt.isoDate(_closeDate!),
                    ),
                  );
                },
                child: const Text('Convert'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
