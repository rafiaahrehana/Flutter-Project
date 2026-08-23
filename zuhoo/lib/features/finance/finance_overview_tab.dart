import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/primitives.dart';
import 'finance_models.dart';
import 'finance_repository.dart';

class FinanceOverviewTab extends ConsumerWidget {
  const FinanceOverviewTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(financeOverviewProvider);

    return async.when(
      loading: () => const Loader(),
      error: (error, _) => ErrorState(
        message: error is ApiException
            ? error.message
            : 'Could not load the finance overview.',
        onRetry: () => ref.invalidate(financeOverviewProvider),
      ),
      data: (overview) => RefreshIndicator(
        color: bos.brand,
        backgroundColor: bos.bgCard,
        onRefresh: () async => ref.invalidate(financeOverviewProvider),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            _ProfitCard(overview: overview),
            const SizedBox(height: 18),
            _Figures(overview: overview),
            const SizedBox(height: 20),
            _Receivables(overview: overview),
            if (overview.recentInvoices.isNotEmpty) ...[
              const SizedBox(height: 20),
              _RecentInvoices(lines: overview.recentInvoices),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProfitCard extends StatelessWidget {
  const _ProfitCard({required this.overview});

  final FinanceOverview overview;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final positive = overview.isProfitable;

    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          Text(
            Fmt.monthYear(overview.month, overview.year),
            style: TextStyle(color: bos.muted, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Text(
            Fmt.money(overview.netProfit),
            style: TextStyle(
              color: positive ? bos.success : bos.danger,
              fontSize: 32,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.8,
            ),
          ),
          Text(
            positive ? 'net profit' : 'net loss',
            style: TextStyle(color: bos.muted, fontSize: 12.5),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _Movement(
                  label: 'Revenue',
                  amount: overview.totalRevenue,
                  changePercent: overview.revenueChangePercent,
                  // More revenue is good news.
                  upIsGood: true,
                ),
              ),
              Container(width: 1, height: 40, color: bos.borderLight),
              Expanded(
                child: _Movement(
                  label: 'Expenses',
                  amount: overview.totalExpenses,
                  changePercent: overview.expenseChangePercent,
                  // More spend is not.
                  upIsGood: false,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Movement extends StatelessWidget {
  const _Movement({
    required this.label,
    required this.amount,
    required this.changePercent,
    required this.upIsGood,
  });

  final String label;
  final double amount;
  final double? changePercent;
  final bool upIsGood;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final change = changePercent;

    return Column(
      children: [
        Text(label, style: TextStyle(color: bos.muted, fontSize: 11.5)),
        const SizedBox(height: 3),
        Text(
          Fmt.money(amount),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: bos.text,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 3),
        // Null means there is no earlier month to compare with. Rendering 0%
        // would claim the figure held steady when nothing is known.
        if (change == null)
          Text(
            Fmt.dash,
            style: TextStyle(color: bos.muted, fontSize: 11.5),
          )
        else
          Builder(
            builder: (context) {
              final rose = change >= 0;
              final good = rose == upIsGood;
              final tone = change == 0
                  ? bos.muted
                  : (good ? bos.success : bos.danger);
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    rose
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded,
                    size: 12,
                    color: tone,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    '${change.abs().toStringAsFixed(change.abs() % 1 == 0 ? 0 : 1)}%',
                    style: TextStyle(
                      color: tone,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
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

class _Figures extends StatelessWidget {
  const _Figures({required this.overview});

  final FinanceOverview overview;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    final rows = <({String label, double value, Color tone})>[
      (
        label: 'Cash collected',
        value: overview.cashCollected,
        tone: bos.success
      ),
      (label: 'Payroll cost', value: overview.payrollCost, tone: bos.info),
      (label: 'Payables', value: overview.payables, tone: bos.textSecondary),
      (
        label: 'Payables overdue',
        value: overview.payablesOverdue,
        tone: overview.payablesOverdue > 0 ? bos.danger : bos.muted
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('This month', icon: Icons.insights_outlined),
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
                  children: [
                    Expanded(
                      child: Text(
                        rows[i].label,
                        style: TextStyle(color: bos.muted, fontSize: 13),
                      ),
                    ),
                    Text(
                      Fmt.money(rows[i].value),
                      style: TextStyle(
                        color: rows[i].tone,
                        fontSize: 14,
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

class _Receivables extends StatelessWidget {
  const _Receivables({required this.overview});

  final FinanceOverview overview;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final share = overview.overdueShare;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Owed to you',
            icon: Icons.account_balance_wallet_outlined),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        Fmt.money(overview.outstanding),
                        style: TextStyle(
                          color: bos.text,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                        ),
                      ),
                      Text(
                        'outstanding',
                        style: TextStyle(color: bos.muted, fontSize: 11.5),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        Fmt.money(overview.overdue),
                        style: TextStyle(
                          color: overview.overdue > 0 ? bos.danger : bos.muted,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'overdue',
                        style: TextStyle(color: bos.muted, fontSize: 11.5),
                      ),
                    ],
                  ),
                ],
              ),
              // Null when nothing is outstanding at all: an empty bar would
              // read as "all healthy" rather than "nothing is out".
              if (share != null) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: share,
                    minHeight: 7,
                    backgroundColor: bos.successSoft,
                    valueColor: AlwaysStoppedAnimation(bos.danger),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${(share * 100).toStringAsFixed(share * 100 % 1 == 0 ? 0 : 1)}% '
                  'of what you are owed is late',
                  style: TextStyle(color: bos.muted, fontSize: 11.5),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _RecentInvoices extends StatelessWidget {
  const _RecentInvoices({required this.lines});

  final List<InvoiceLine> lines;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Recent invoices',
            icon: Icons.receipt_long_outlined),
        AppCard(
          child: Column(
            children: [
              for (var i = 0; i < lines.length && i < 5; i++) ...[
                if (i > 0) ...[
                  const SizedBox(height: 10),
                  Divider(height: 1, color: bos.borderLight),
                  const SizedBox(height: 10),
                ],
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            lines[i].invoiceNumber,
                            style: TextStyle(
                              color: bos.text,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (lines[i].clientName != null)
                            Text(
                              lines[i].clientName!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: bos.muted, fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          Fmt.money(lines[i].balanceAmount > 0
                              ? lines[i].balanceAmount
                              : lines[i].totalAmount),
                          style: TextStyle(
                            color: bos.text,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        // The dashboard row carries its own overdue flag, so
                        // it is shown rather than recomputed here.
                        StatusChip(
                          lines[i].overdue ? 'OVERDUE' : lines[i].status,
                          dense: true,
                        ),
                      ],
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
