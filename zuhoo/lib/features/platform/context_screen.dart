import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/paged_list_view.dart';
import '../../shared/widgets/primitives.dart';
import 'context_models.dart';
import 'context_repository.dart';
import 'platform_models.dart';
import 'platform_repository.dart';

/// Support context switches: who is working inside which customer, and why.
///
/// The distinction from impersonation matters and is stated on the screen,
/// because the two look alike and are not: impersonation hands you a token and
/// puts you *inside* a tenant; a context switch grants nothing at all. It is a
/// declaration of what you are working on, and the row it writes is the
/// accountability for having looked.
class ContextSwitchTab extends ConsumerWidget {
  const ContextSwitchTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final user = ref.watch(currentUserProvider);

    final canSwitch = user?.hasAnyRole(contextSwitchRoles) ?? false;
    final canReview = user?.hasAnyRole(contextSwitchReviewRoles) ?? false;

    if (!canSwitch && !canReview) {
      return const EmptyState(
        icon: Icons.lock_outline_rounded,
        title: 'Not available to you',
        message:
            'Context switches are for support staff. Your platform role does '
            'not include working inside customer accounts.',
      );
    }

    return RefreshIndicator(
      color: bos.brand,
      backgroundColor: bos.bgCard,
      onRefresh: () async {
        ref.invalidate(activeContextSwitchesProvider);
        await ref.read(myContextSwitchProvider.notifier).refresh();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
        children: [
          const MessageBanner.info(
            'A context switch records that you are working in a customer’s '
            'account. It does not open their data — that is what accessing '
            'a company does.',
          ),
          const SizedBox(height: 18),
          if (canSwitch) ...[
            const SectionHeader(
              'Your context',
              icon: Icons.person_pin_circle_outlined,
            ),
            const _MyContextCard(),
            const SizedBox(height: 22),
          ],
          if (canReview) ...[
            const SectionHeader(
              'Working now',
              icon: Icons.groups_2_outlined,
            ),
            const _ActiveBoard(),
          ],
        ],
      ),
    );
  }
}

/// The signed-in agent's own open switch, and the controls to start or end one.
class _MyContextCard extends ConsumerStatefulWidget {
  const _MyContextCard();

  @override
  ConsumerState<_MyContextCard> createState() => _MyContextCardState();
}

class _MyContextCardState extends ConsumerState<_MyContextCard> {
  bool _busy = false;

  Future<void> _guard(Future<void> Function() action, String failure) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(failure)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    final choice = await showModalBottomSheet<({int companyId, String purpose})>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _StartSheet(),
    );
    if (choice == null || !mounted) return;

    await _guard(
      () async {
        await ref.read(myContextSwitchProvider.notifier).start(
              companyId: choice.companyId,
              purpose: choice.purpose,
            );
      },
      'Could not start that context switch.',
    );
  }

  Future<void> _end() => _guard(
        () => ref.read(myContextSwitchProvider.notifier).end(),
        'Could not end that context switch.',
      );

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final mine = ref.watch(myContextSwitchProvider);

    return AppCard(
      child: mine.when(
        loading: () => const Loader(padding: 8),
        error: (error, _) => ErrorState(
          message: error is ApiException
              ? error.message
              : 'Could not check your current context.',
          onRetry: () => ref.read(myContextSwitchProvider.notifier).refresh(),
        ),
        data: (current) {
          if (_busy) return const Loader(padding: 8);

          if (current == null) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Not working in any company',
                  style: TextStyle(
                    color: bos.text,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Start one when you pick up a ticket, so it is on record '
                  'which account you were in.',
                  style: TextStyle(
                    color: bos.muted,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _start,
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('Start a context switch'),
                ),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      current.companyLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: bos.text,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const StatusChip('ACTIVE', label: 'Open', dense: true),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                current.hasPurpose
                    ? current.purpose!.trim()
                    : 'No purpose recorded.',
                style: TextStyle(
                  color: current.hasPurpose ? bos.text : bos.muted,
                  fontSize: 13,
                  height: 1.3,
                  fontStyle:
                      current.hasPurpose ? FontStyle.normal : FontStyle.italic,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.schedule_rounded, size: 13, color: bos.muted),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      'Since ${Fmt.dateTime(current.switchedInTime)}'
                      '${current.elapsedLabel == null ? '' : ' · ${current.elapsedLabel}'}',
                      style: TextStyle(color: bos.muted, fontSize: 11.5),
                    ),
                  ),
                ],
              ),
              if (current.looksForgotten) ...[
                const SizedBox(height: 10),
                MessageBanner.warning(
                  'This has been open for ${current.elapsedLabel}. If you are '
                  'no longer in this account, end it — a stale record is '
                  'worse than none.',
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _end,
                    icon: const Icon(Icons.stop_rounded, size: 16),
                    label: const Text('End'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: bos.danger,
                      side: BorderSide(color: bos.danger.withValues(alpha: 0.4)),
                      minimumSize: const Size(0, 36),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _start,
                    icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                    label: const Text('Switch company'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: bos.brandInk,
                      side: BorderSide(
                        color: bos.brandInk.withValues(alpha: 0.4),
                      ),
                      minimumSize: const Size(0, 36),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Picks the company and the purpose for a new switch.
class _StartSheet extends ConsumerStatefulWidget {
  const _StartSheet();

  @override
  ConsumerState<_StartSheet> createState() => _StartSheetState();
}

class _StartSheetState extends ConsumerState<_StartSheet> {
  final _purpose = TextEditingController();
  final _filter = TextEditingController();
  Company? _selected;

  @override
  void initState() {
    super.initState();
    _filter.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _purpose.dispose();
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    // Watching this loads the first page if the Companies tab has not been
    // opened yet, so the picker is never empty for want of a fetch.
    final companies = ref.watch(companiesProvider);
    final query = _filter.text.trim().toLowerCase();

    final all = companies.value?.items ?? const <Company>[];
    final shown = query.isEmpty
        ? all
        : all
            .where(
              (c) =>
                  c.companyName.toLowerCase().contains(query) ||
                  c.subdomain.toLowerCase().contains(query),
            )
            .toList(growable: false);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Column(
          children: [
            const SizedBox(height: 10),
            Container(
              height: 4,
              width: 38,
              decoration: BoxDecoration(
                color: bos.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Start a context switch',
                    style: TextStyle(
                      color: bos.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _purpose,
                    maxLength: 200,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Purpose (optional)',
                      hintText: 'e.g. Ticket #482 — payroll not running',
                    ),
                  ),
                  TextField(
                    controller: _filter,
                    decoration: const InputDecoration(
                      labelText: 'Find a company',
                      prefixIcon: Icon(Icons.search_rounded, size: 20),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: companies.when(
                loading: () => const Loader(),
                error: (error, _) => ErrorState(
                  message: error is ApiException
                      ? error.message
                      : 'Could not load the company list.',
                  onRetry: () =>
                      ref.read(companiesProvider.notifier).refresh(),
                ),
                data: (_) => shown.isEmpty
                    ? const EmptyState(
                        icon: Icons.search_off_rounded,
                        title: 'No match',
                        message: 'No company on this page matches that.',
                      )
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: shown.length,
                        itemBuilder: (context, i) {
                          final company = shown[i];
                          final selected = _selected?.id == company.id;
                          return ListTile(
                            title: Text(company.companyName),
                            subtitle: Text(company.subdomain),
                            trailing: selected
                                ? Icon(
                                    Icons.check_circle_rounded,
                                    color: bos.brand,
                                  )
                                : null,
                            onTap: () => setState(() => _selected = company),
                          );
                        },
                      ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _selected == null
                        ? null
                        : () => Navigator.pop(
                              context,
                              (
                                companyId: _selected!.id,
                                purpose: _purpose.text,
                              ),
                            ),
                    child: Text(
                      _selected == null
                          ? 'Pick a company'
                          : 'Start on ${_selected!.companyName}',
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Everyone currently inside a customer account.
class _ActiveBoard extends ConsumerWidget {
  const _ActiveBoard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeContextSwitchesProvider);

    return active.when(
      loading: () => const Loader(),
      error: (error, _) => ErrorState(
        message: error is ApiException
            ? error.message
            : 'Could not load who is working where.',
        onRetry: () => ref.invalidate(activeContextSwitchesProvider),
      ),
      data: (switches) {
        if (switches.isEmpty) {
          return const AppCard(
            child: EmptyState(
              icon: Icons.nights_stay_outlined,
              title: 'Nobody is in a customer account',
              message: 'Open switches show up here as soon as one starts.',
            ),
          );
        }
        return Column(
          children: [
            for (final entry in switches)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ActiveRow(entry: entry),
              ),
          ],
        );
      },
    );
  }
}

class _ActiveRow extends ConsumerWidget {
  const _ActiveRow({required this.entry});

  final SupportContextSwitch entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => AgentContextHistoryScreen.open(
        context,
        agentId: entry.supportAgentId,
        agentName: entry.agentLabel,
      ),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Avatar(initials: _initials(entry.agentLabel), size: 34),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.agentLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: bos.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'in ${entry.companyLabel}',
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
                if (entry.looksForgotten)
                  StatusChip(
                    'OVERDUE',
                    label: 'Open ${entry.elapsedLabel}',
                    dense: true,
                  )
                else if (entry.elapsedLabel != null)
                  Text(
                    entry.elapsedLabel!,
                    style: TextStyle(color: bos.muted, fontSize: 11.5),
                  ),
              ],
            ),
            if (entry.hasPurpose) ...[
              const SizedBox(height: 8),
              Text(
                entry.purpose!.trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: bos.text, fontSize: 12.5, height: 1.3),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _initials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}

/// One agent's past context switches.
///
/// Reachable only by the roles that may read it. An agent cannot open their
/// own history — the backend restricts this to managers and above, and
/// offering it to everybody would 403 for most of the people who see it.
class AgentContextHistoryScreen extends ConsumerWidget {
  const AgentContextHistoryScreen({
    super.key,
    required this.agentId,
    required this.agentName,
  });

  final int agentId;
  final String agentName;

  static void open(
    BuildContext context, {
    required int agentId,
    required String agentName,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AgentContextHistoryScreen(
          agentId: agentId,
          agentName: agentName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final user = ref.watch(currentUserProvider);

    if (user != null && !user.hasAnyRole(contextSwitchReviewRoles)) {
      return Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(title: const Text('History')),
        body: const EmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Not available to you',
          message:
              'Reviewing context switches is for support managers and above.',
        ),
      );
    }

    final provider = agentContextHistoryProvider(agentId);

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(
        title: Text(agentName),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Context switches',
              style: TextStyle(color: bos.muted, fontSize: 12),
            ),
          ),
        ),
      ),
      body: PagedListView<SupportContextSwitch>(
        async: ref.watch(provider),
        onRefresh: () => ref.read(provider.notifier).refresh(),
        onLoadMore: () => ref.read(provider.notifier).loadMore(),
        emptyTitle: 'Nothing recorded',
        emptyMessage: 'This agent has not worked inside a customer account.',
        emptyIcon: Icons.history_rounded,
        itemBuilder: (context, entry) => _HistoryRow(entry: entry),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry});

  final SupportContextSwitch entry;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  entry.companyLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: bos.text,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (entry.stillActive)
                const StatusChip('ACTIVE', label: 'Open', dense: true),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            entry.hasPurpose ? entry.purpose!.trim() : 'No purpose recorded.',
            style: TextStyle(
              color: entry.hasPurpose ? bos.text : bos.muted,
              fontSize: 13,
              height: 1.3,
              fontStyle:
                  entry.hasPurpose ? FontStyle.normal : FontStyle.italic,
            ),
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Icon(Icons.schedule_rounded, size: 13, color: bos.muted),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  entry.stillActive
                      ? Fmt.dateTime(entry.switchedInTime)
                      : '${Fmt.dateTime(entry.switchedInTime)} → '
                          '${Fmt.time(entry.switchedOutTime)}',
                  style: TextStyle(color: bos.muted, fontSize: 11.5),
                ),
              ),
              if (entry.elapsedLabel != null)
                Text(
                  entry.elapsedLabel!,
                  style: TextStyle(
                    color: bos.muted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          if (entry.ipAddress?.isNotEmpty == true) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.router_outlined, size: 13, color: bos.muted),
                const SizedBox(width: 5),
                Text(
                  entry.ipAddress!,
                  style: TextStyle(color: bos.muted, fontSize: 11.5),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
