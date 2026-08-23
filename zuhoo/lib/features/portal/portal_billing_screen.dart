import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/paged_list_view.dart';
import '../../shared/widgets/primitives.dart';
import 'portal_models.dart';
import 'portal_repository.dart';

class PortalBillingScreen extends ConsumerWidget {
  const PortalBillingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(
          title: const Text('Billing'),
          bottom: const TabBar(
            tabs: [Tab(text: 'Invoices'), Tab(text: 'Payments')],
          ),
        ),
        body: const TabBarView(children: [_InvoicesTab(), _ReceiptsTab()]),
      ),
    );
  }
}

class _InvoicesTab extends ConsumerWidget {
  const _InvoicesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(clientInvoicesProvider.notifier);

    return PagedListView<Invoice>(
      async: ref.watch(clientInvoicesProvider),
      onRefresh: controller.refresh,
      onLoadMore: () => guardListAction(context, controller.loadMore),
      emptyIcon: Icons.receipt_long_outlined,
      emptyTitle: 'No invoices',
      emptyMessage: 'Invoices for work you have commissioned appear here.',
      errorMessage: 'Could not load your invoices.',
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      itemBuilder: (context, invoice) => _InvoiceCard(invoice: invoice),
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
          await ref.read(portalRepositoryProvider).invoicePdf(widget.invoice);
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      invoice.invoiceNumber,
                      style: TextStyle(
                        color: bos.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
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
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Overdue is derived, not just read off the status: a bill can be
              // past due before any nightly job relabels it, and the person who
              // owes the money should see that straight away.
              StatusChip(
                invoice.isOverdue ? InvoiceStatus.overdue : invoice.status,
                dense: true,
              ),
            ],
          ),
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
                        ? 'due of ${Fmt.money(invoice.totalAmount)}'
                        : 'paid in full',
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
                        color: invoice.isOverdue ? bos.danger : bos.textSecondary,
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
          if (invoice.isPartlyPaid) ...[
            const SizedBox(height: 8),
            Text(
              '${Fmt.money(invoice.paidAmount)} already paid',
              style: TextStyle(
                color: bos.success,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
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

class _ReceiptsTab extends ConsumerWidget {
  const _ReceiptsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final controller = ref.read(clientReceiptsProvider.notifier);

    return PagedListView<PaymentReceipt>(
      async: ref.watch(clientReceiptsProvider),
      onRefresh: controller.refresh,
      onLoadMore: () => guardListAction(context, controller.loadMore),
      emptyIcon: Icons.payments_outlined,
      emptyTitle: 'No payments yet',
      emptyMessage: 'Receipts for payments you have made appear here.',
      errorMessage: 'Could not load your payment history.',
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      itemBuilder: (context, receipt) => AppCard(
        child: Row(
          children: [
            Container(
              height: 38,
              width: 38,
              decoration: BoxDecoration(
                color: bos.successSoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.check_rounded, size: 19, color: bos.success),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    Fmt.money(receipt.amount),
                    style: TextStyle(
                      color: bos.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      Fmt.date(receipt.paymentDate),
                      if (receipt.paymentMethod != null)
                        Fmt.label(receipt.paymentMethod),
                    ].join(' · '),
                    style: TextStyle(color: bos.muted, fontSize: 12),
                  ),
                  if (receipt.invoiceNumber != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'against ${receipt.invoiceNumber}',
                      style: TextStyle(color: bos.muted, fontSize: 11.5),
                    ),
                  ],
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                StatusChip(receipt.status, dense: true),
                const SizedBox(height: 4),
                Text(
                  receipt.receiptNumber,
                  style: TextStyle(color: bos.muted, fontSize: 10.5),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
