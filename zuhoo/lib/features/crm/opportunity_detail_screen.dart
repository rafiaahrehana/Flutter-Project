import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/primitives.dart';
import 'crm_controllers.dart';
import 'crm_models.dart';
import 'crm_repository.dart';

void openOpportunity(BuildContext context, int id) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => OpportunityDetailScreen(id: id)),
  );
}

class OpportunityDetailScreen extends ConsumerStatefulWidget {
  const OpportunityDetailScreen({super.key, required this.id});

  final int id;

  @override
  ConsumerState<OpportunityDetailScreen> createState() =>
      _OpportunityDetailScreenState();
}

class _OpportunityDetailScreenState
    extends ConsumerState<OpportunityDetailScreen> {
  bool _busy = false;

  /// Moves the deal to [stage], collecting whatever that transition needs first.
  ///
  /// Two transitions need more than a stage name:
  ///   LOST — the backend requires a reason code, and free text when it's OTHER
  ///   WON on a deal with no client — the backend has to decide whether to make
  ///        a new client or attach an existing one, and asks first
  ///
  /// Everything else is a straight change.
  Future<void> _moveTo(Opportunity opportunity, String stage) async {
    ChangeStageRequest? request;

    if (stage == Stage.lost) {
      final reason = await _askLostReason();
      if (reason == null) return;
      request = ChangeStageRequest(
        stage: stage,
        lostReasonCode: reason.code,
        lostReason: reason.detail,
      );
    } else if (stage == Stage.won && opportunity.needsClientDecisionOnWin) {
      if (!mounted) return;
      setState(() => _busy = true);
      final match = await ref
          .read(crmRepositoryProvider)
          .wonDuplicateCheck(opportunity.id);
      if (!mounted) return;
      setState(() => _busy = false);

      if (match == null) {
        // No duplicate, or the check itself failed. Either way this must not
        // stand between a rep and closing a deal — the backend still decides.
        request = const ChangeStageRequest(stage: Stage.won);
      } else {
        final decision = await _askDuplicateDecision(match);
        if (decision == null) return;
        request = ChangeStageRequest(
          stage: Stage.won,
          linkToExistingClientId: decision ? match.clientId : null,
          forceCreateNewClient: decision ? null : true,
        );
      }
    } else {
      request = ChangeStageRequest(stage: stage);
    }

    if (!mounted) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(opportunitiesProvider.notifier)
          .changeStage(opportunity.id, request);
      messenger.showSnackBar(
        SnackBar(content: Text('Moved to ${Fmt.label(stage)}.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not move that deal.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<({String code, String? detail})?> _askLostReason() {
    return showModalBottomSheet<({String code, String? detail})>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _LostReasonSheet(),
    );
  }

  /// True = link to the existing client, false = create a new one.
  Future<bool?> _askDuplicateDecision(DuplicateMatch match) {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        final bos = Theme.of(context).bos;
        return AlertDialog(
          title: const Text('This may already be a client'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '“${match.clientCompanyName}” already exists',
                style: TextStyle(
                  color: bos.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Matched on ${Fmt.label(match.matchedOn).toLowerCase()}.',
                style: TextStyle(color: bos.muted, fontSize: 13),
              ),
              const SizedBox(height: 12),
              Text(
                'Attach this won deal to that client, or create a separate one? '
                'Creating a duplicate is hard to undo later.',
                style: TextStyle(
                  color: bos.textSecondary,
                  fontSize: 13.5,
                  height: 1.4,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Create new'),
            ),
            // The safe option gets the emphasis.
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Link existing'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(opportunityDetailProvider(widget.id));

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(title: const Text('Deal')),
      body: async.when(
        loading: () => const Loader(),
        error: (error, _) => ErrorState(
          message: error is ApiException
              ? error.message
              : 'Could not load that deal.',
          onRetry: () => ref.invalidate(opportunityDetailProvider(widget.id)),
        ),
        data: (opportunity) => RefreshIndicator(
          color: bos.brand,
          backgroundColor: bos.bgCard,
          onRefresh: () async =>
              ref.invalidate(opportunityDetailProvider(widget.id)),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              _Header(opportunity: opportunity),
              const SizedBox(height: 20),
              _Facts(opportunity: opportunity),
              const SizedBox(height: 20),
              if (_busy)
                const Loader(padding: 12)
              else
                _StageActions(
                  opportunity: opportunity,
                  onMove: (stage) => _moveTo(opportunity, stage),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.opportunity});

  final Opportunity opportunity;

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
                child: Text(
                  opportunity.name,
                  style: TextStyle(
                    color: bos.text,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              StatusChip(opportunity.stage),
            ],
          ),
          const SizedBox(height: 14),
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
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.6,
                    ),
                  ),
                  Text(
                    '${Fmt.money(opportunity.weightedAmount)} weighted at '
                    '${opportunity.probability}%',
                    style: TextStyle(color: bos.muted, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
          if (opportunity.description != null &&
              opportunity.description!.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              opportunity.description!,
              style: TextStyle(
                color: bos.textSecondary,
                fontSize: 14,
                height: 1.45,
              ),
            ),
          ],
          if (opportunity.isOverdue) ...[
            const SizedBox(height: 14),
            MessageBanner.error(
              'Expected to close ${Fmt.date(opportunity.expectedCloseDate)} — '
              'that date has passed.',
            ),
          ],
          if (opportunity.isLost && opportunity.lostReasonCode != null) ...[
            const SizedBox(height: 14),
            MessageBanner.info(
              'Lost: ${_lostLabel(opportunity.lostReasonCode!)}'
              '${opportunity.lostReason != null && opportunity.lostReason!.trim().isNotEmpty ? ' — ${opportunity.lostReason}' : ''}',
            ),
          ],
        ],
      ),
    );
  }

  static String _lostLabel(String code) {
    for (final reason in lostReasons) {
      if (reason.code == code) return reason.label;
    }
    return Fmt.label(code);
  }
}

class _Facts extends StatelessWidget {
  const _Facts({required this.opportunity});

  final Opportunity opportunity;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    final rows = <({String label, String? value})>[
      (label: 'Client', value: opportunity.clientCompanyName),
      (label: 'Contact', value: opportunity.contactName),
      (label: 'Owner', value: opportunity.ownerName),
      (
        label: 'Source',
        value: opportunity.source == null ? null : Fmt.label(opportunity.source)
      ),
      (
        label: 'Expected close',
        value: opportunity.expectedCloseDate == null
            ? null
            : Fmt.date(opportunity.expectedCloseDate)
      ),
      (
        label: 'Closed',
        value: opportunity.actualCloseDate == null
            ? null
            : Fmt.date(opportunity.actualCloseDate)
      ),
      (label: 'Next step', value: opportunity.nextStep),
      (
        label: 'Stage changed',
        value: opportunity.stageChangedAt == null
            ? null
            : Fmt.relative(opportunity.stageChangedAt)
      ),
      (
        label: 'Last activity',
        value: opportunity.lastActivityAt == null
            ? null
            : Fmt.relative(opportunity.lastActivityAt)
      ),
      (label: 'Created', value: Fmt.date(opportunity.createdAt)),
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

class _StageActions extends StatelessWidget {
  const _StageActions({required this.opportunity, required this.onMove});

  final Opportunity opportunity;
  final void Function(String stage) onMove;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    // A closed deal is history. Reopening one is a correction rather than a
    // routine move, and it belongs where someone can see the full record.
    if (!opportunity.isOpen) {
      return MessageBanner.info(
        'This deal is ${Fmt.label(opportunity.stage).toLowerCase()}. Reopening '
        'it is done from the web app.',
      );
    }

    final current = Stage.open.indexOf(opportunity.stage);
    final next = current >= 0 && current < Stage.open.length - 1
        ? Stage.open[current + 1]
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Move this deal', icon: Icons.swap_horiz_rounded),
        // The next stage forward is the overwhelmingly common move, so it gets
        // the primary button and does not need a picker.
        if (next != null) ...[
          ElevatedButton.icon(
            onPressed: () => onMove(next),
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: Text('Advance to ${Fmt.label(next)}'),
          ),
          const SizedBox(height: 10),
        ],
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => onMove(Stage.lost),
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text('Lost'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: bos.danger,
                  side: BorderSide(color: bos.danger.withValues(alpha: 0.4)),
                  minimumSize: const Size.fromHeight(46),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => onMove(Stage.won),
                icon: const Icon(Icons.emoji_events_outlined, size: 18),
                label: const Text('Won'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: bos.success,
                  minimumSize: const Size.fromHeight(46),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        // Every other stage, including going back a step, behind a picker —
        // real but rare, and not worth four more buttons.
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final stage in Stage.open)
              if (stage != opportunity.stage && stage != next)
                OutlinedButton(
                  onPressed: () => onMove(stage),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 38),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  child: Text(
                    Fmt.label(stage),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
          ],
        ),
      ],
    );
  }
}

class _LostReasonSheet extends StatefulWidget {
  const _LostReasonSheet();

  @override
  State<_LostReasonSheet> createState() => _LostReasonSheetState();
}

class _LostReasonSheetState extends State<_LostReasonSheet> {
  final _detail = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String _code = lostReasons.first.code;

  bool get _needsDetail => _code == 'OTHER';

  @override
  void dispose() {
    _detail.dispose();
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
                'Why was this lost?',
                style: TextStyle(
                  color: bos.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'This is what the pipeline reports are built from.',
                style: TextStyle(color: bos.muted, fontSize: 12.5),
              ),
              const SizedBox(height: 16),
              // The group owns the selection now; the tiles just declare their
              // value. `groupValue`/`onChanged` per tile is deprecated.
              RadioGroup<String>(
                groupValue: _code,
                onChanged: (value) => setState(() => _code = value ?? _code),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final reason in lostReasons)
                      RadioListTile<String>(
                        value: reason.code,
                        title: Text(
                          reason.label,
                          style: TextStyle(color: bos.text, fontSize: 14.5),
                        ),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        activeColor: bos.brand,
                      ),
                  ],
                ),
              ),
              if (_needsDetail) ...[
                const SizedBox(height: 8),
                TextFormField(
                  controller: _detail,
                  maxLines: 2,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'What happened',
                    alignLabelWithHint: true,
                  ),
                  // The backend requires the free text when the code is OTHER;
                  // catching it here saves a round trip and a raw error.
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'Say what happened — "Other" on its own tells nobody anything.'
                      : null,
                ),
              ],
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: () {
                  if (_needsDetail &&
                      !(_formKey.currentState?.validate() ?? false)) {
                    return;
                  }
                  Navigator.pop(
                    context,
                    (
                      code: _code,
                      detail: _needsDetail ? _detail.text.trim() : null,
                    ),
                  );
                },
                child: const Text('Mark as lost'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
