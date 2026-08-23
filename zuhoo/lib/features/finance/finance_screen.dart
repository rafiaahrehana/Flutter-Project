import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';

import '../../core/auth/permission_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/paged_list_view.dart';
import '../../shared/widgets/primitives.dart';
import '../portal/portal_models.dart' show Invoice, InvoiceStatus;
import 'expenses_tab.dart';
import 'finance_models.dart';
import 'finance_overview_tab.dart';
import 'finance_repository.dart';
import 'submit_expense_sheet.dart';

/// Finance, cut down to what a phone can actually do.
///
/// The web module has eighteen screens. Twelve of them — chart of accounts,
/// general ledger, journal entries, bank reconciliation, fiscal years,
/// accounting periods, fixed assets, budgets, financial reports, vendors and
/// vendor bills — are wide multi-column reconciliation work. A phone cannot
/// show enough columns at once for those to be usable, and a half-shown ledger
/// is worse than no ledger, so they are deliberately absent rather than
/// squeezed in.
///
/// What is here is what people genuinely do away from a desk: check the
/// numbers, claim an expense, approve someone else's, chase an invoice, and
/// look at the wallet.
class FinanceScreen extends ConsumerWidget {
  const FinanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final permissions = ref.watch(permissionControllerProvider);

    if (!permissions.loaded && permissions.codes.isEmpty) {
      return Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(title: const Text('Finance')),
        body: const Loader(),
      );
    }

    // Submitting a claim needs no entitlement — everyone spends their own
    // money on the company's behalf — so the Expenses tab is always present
    // and only its extra views are gated.
    final tabs = <({String label, Widget view, bool showsFab})>[
      if (permissions.has(FinancePermissions.reportView))
        (label: 'Overview', view: const FinanceOverviewTab(), showsFab: false),
      (label: 'Expenses', view: const ExpensesTab(), showsFab: true),
      if (permissions.has(FinancePermissions.invoiceView))
        (label: 'Invoices', view: const _InvoicesTab(), showsFab: false),
      if (permissions.has(FinancePermissions.walletView))
        (label: 'Wallet', view: const _WalletTab(), showsFab: false),
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Builder(
        builder: (context) {
          final tabController = DefaultTabController.of(context);
          return AnimatedBuilder(
            animation: tabController,
            builder: (context, _) {
              return Scaffold(
                backgroundColor: bos.bgPage,
                appBar: AppBar(
                  title: const Text('Finance'),
                  bottom: tabs.length > 1
                      ? TabBar(
                          isScrollable: tabs.length > 3,
                          tabAlignment:
                              tabs.length > 3 ? TabAlignment.start : null,
                          tabs: [for (final tab in tabs) Tab(text: tab.label)],
                        )
                      : null,
                ),
                // Only over Expenses — a "claim an expense" button floating
                // above the ledger would create the wrong thing.
                floatingActionButton: tabs[tabController.index].showsFab
                    ? FloatingActionButton.extended(
                        onPressed: () => showSubmitExpenseSheet(context),
                        backgroundColor: bos.brand,
                        foregroundColor: Colors.white,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Claim'),
                      )
                    : null,
                body: tabs.length > 1
                    ? TabBarView(children: [for (final tab in tabs) tab.view])
                    : tabs.first.view,
              );
            },
          );
        },
      ),
    );
  }
}

class _InvoicesTab extends ConsumerWidget {
  const _InvoicesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(invoicesProvider.notifier);

    return Column(
      children: [
        const _InvoiceFilter(),
        Expanded(
          child: PagedListView<Invoice>(
            async: ref.watch(invoicesProvider),
            onRefresh: controller.refresh,
            onLoadMore: () => guardListAction(context, controller.loadMore),
            emptyIcon: Icons.receipt_long_outlined,
            emptyTitle: 'No invoices here',
            emptyMessage: 'Invoices you raise appear here with what is owed.',
            errorMessage: 'Could not load your invoices.',
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            itemBuilder: (context, invoice) => _InvoiceCard(invoice: invoice),
          ),
        ),
      ],
    );
  }
}

class _InvoiceFilter extends ConsumerWidget {
  const _InvoiceFilter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final selected = ref.watch(invoiceFilterProvider);

    // Straight from the backend enum. Ordered by how often someone filters by
    // them rather than by the enum's own order — chasing money comes first.
    const statuses = <String?>[
      null,
      InvoiceStatus.overdue,
      InvoiceStatus.issued,
      InvoiceStatus.partiallyPaid,
      InvoiceStatus.paid,
      InvoiceStatus.draft,
      InvoiceStatus.cancelled,
    ];

    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        itemCount: statuses.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final status = statuses[index];
          final isSelected = selected == status;
          return GestureDetector(
            onTap: () => ref.read(invoiceFilterProvider.notifier).set(status),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
              decoration: BoxDecoration(
                color: isSelected ? bos.brand : bos.bgCard,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isSelected ? bos.brand : bos.border),
              ),
              child: Text(
                status == null ? 'All' : Fmt.label(status),
                style: TextStyle(
                  color: isSelected ? Colors.white : bos.textSecondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _InvoiceCard extends ConsumerStatefulWidget {
  const _InvoiceCard({required this.invoice});

  final Invoice invoice;

  @override
  ConsumerState<_InvoiceCard> createState() => _InvoiceCardState();
}

class _InvoiceCardState extends ConsumerState<_InvoiceCard> {
  bool _downloading = false;

  Future<void> _open() async {
    setState(() => _downloading = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final path =
          await ref.read(financeRepositoryProvider).invoicePdf(widget.invoice);
      final result = await OpenFilex.open(path);
      if (result.type != ResultType.done && mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('No app on this device can open a PDF.')),
        );
      }
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not download that invoice.')),
      );
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final invoice = widget.invoice;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  invoice.invoiceNumber,
                  style: TextStyle(
                    color: bos.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              StatusChip(
                invoice.isOverdue ? InvoiceStatus.overdue : invoice.status,
                dense: true,
              ),
            ],
          ),
          if (invoice.description != null &&
              invoice.description!.trim().isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              invoice.description!,
              maxLines: 2,
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
                    Fmt.money(invoice.balanceAmount > 0
                        ? invoice.balanceAmount
                        : invoice.totalAmount),
                    style: TextStyle(
                      color: invoice.balanceAmount > 0 ? bos.text : bos.muted,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                  ),
                  Text(
                    invoice.balanceAmount > 0
                        ? 'owed of ${Fmt.money(invoice.totalAmount)}'
                        : 'settled',
                    style: TextStyle(color: bos.muted, fontSize: 11.5),
                  ),
                ],
              ),
              const Spacer(),
              if (invoice.dueDate != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      Fmt.dateShort(invoice.dueDate),
                      style: TextStyle(
                        color:
                            invoice.isOverdue ? bos.danger : bos.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      invoice.isOverdue ? 'overdue' : 'due',
                      style: TextStyle(color: bos.muted, fontSize: 11),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_downloading)
            const Loader(padding: 6)
          else
            OutlinedButton.icon(
              onPressed: _open,
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 17),
              label: const Text('Open PDF'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(40),
              ),
            ),
        ],
      ),
    );
  }
}

class _WalletTab extends ConsumerWidget {
  const _WalletTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final wallet = ref.watch(walletProvider);
    final controller = ref.read(walletTransactionsProvider.notifier);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: wallet.when(
            loading: () => const Loader(padding: 20),
            error: (error, _) => MessageBanner.error(
              error is ApiException
                  ? error.message
                  : 'Could not load your wallet.',
            ),
            data: (w) => AppCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  Text(
                    'Available',
                    style: TextStyle(color: bos.muted, fontSize: 12.5),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    Fmt.money(w.totalAvailable),
                    style: TextStyle(
                      color: bos.text,
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.8,
                    ),
                  ),
                  // Credit is spendable but not withdrawable, so the split
                  // matters — one number would hide that distinction.
                  if (w.hasCredit) ...[
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _Split(label: 'Cash', amount: w.balance),
                        Container(
                          width: 1,
                          height: 28,
                          margin: const EdgeInsets.symmetric(horizontal: 20),
                          color: bos.borderLight,
                        ),
                        _Split(label: 'Credit', amount: w.creditBalance),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: PagedListView<WalletTransaction>(
            async: ref.watch(walletTransactionsProvider),
            onRefresh: () async {
              ref.invalidate(walletProvider);
              await controller.refresh();
            },
            onLoadMore: () => guardListAction(context, controller.loadMore),
            emptyIcon: Icons.account_balance_wallet_outlined,
            emptyTitle: 'No transactions',
            emptyMessage: 'Top-ups and charges appear here.',
            errorMessage: 'Could not load your transactions.',
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            itemBuilder: (context, tx) => _TransactionRow(transaction: tx),
          ),
        ),
      ],
    );
  }
}

class _Split extends StatelessWidget {
  const _Split({required this.label, required this.amount});

  final String label;
  final double amount;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    return Column(
      children: [
        Text(
          Fmt.money(amount),
          style: TextStyle(
            color: bos.text,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(label, style: TextStyle(color: bos.muted, fontSize: 11)),
      ],
    );
  }
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({required this.transaction});

  final WalletTransaction transaction;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final credit = transaction.isCredit;
    final tone = credit ? bos.success : bos.danger;

    return AppCard(
      child: Row(
        children: [
          Container(
            height: 36,
            width: 36,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              credit ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
              size: 17,
              color: tone,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  Fmt.label(transaction.type),
                  style: TextStyle(
                    color: bos.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    Fmt.relative(transaction.transactedAt),
                    if (transaction.reference != null) transaction.reference!,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: bos.muted, fontSize: 11.5),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                // The sign is derived from the type: the backend stores
                // positive magnitudes on both sides, so reading the sign off
                // the amount would show every charge as a top-up.
                '${credit ? '+' : '−'}${Fmt.money(transaction.amount)}',
                style: TextStyle(
                  color: tone,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '${Fmt.money(transaction.balanceAfter)} after',
                style: TextStyle(color: bos.muted, fontSize: 10.5),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
