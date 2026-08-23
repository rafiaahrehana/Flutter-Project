import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/primitives.dart';
import 'payslip_models.dart';
import 'payslip_repository.dart';

class PayslipsScreen extends ConsumerWidget {
  const PayslipsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final async = ref.watch(myPayslipsProvider);

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(title: const Text('My payslips')),
      body: async.when(
        loading: () => const Loader(),
        error: (error, _) => ErrorState(
          message: error is ApiException
              ? error.message
              : 'Could not load your payslips.',
          onRetry: () => ref.invalidate(myPayslipsProvider),
        ),
        data: (payslips) {
          if (payslips.isEmpty) {
            return const EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No payslips yet',
              message: 'Payslips appear here after each payroll run.',
            );
          }
          return RefreshIndicator(
            color: bos.brand,
            backgroundColor: bos.bgCard,
            onRefresh: () async => ref.invalidate(myPayslipsProvider),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              itemCount: payslips.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) =>
                  _PayslipCard(payslip: payslips[index]),
            ),
          );
        },
      ),
    );
  }
}

class _PayslipCard extends StatelessWidget {
  const _PayslipCard({required this.payslip});

  final Payslip payslip;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return AppCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PayslipDetailScreen(payslip: payslip),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  Fmt.monthYear(payslip.payMonth, payslip.payYear),
                  style: TextStyle(
                    color: bos.text,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                StatusChip(payslip.status, dense: true),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                Fmt.money(payslip.netSalary),
                style: TextStyle(
                  color: bos.text,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              Text(
                'net pay',
                style: TextStyle(color: bos.muted, fontSize: 11.5),
              ),
            ],
          ),
          const SizedBox(width: 6),
          Icon(Icons.chevron_right_rounded, size: 20, color: bos.muted),
        ],
      ),
    );
  }
}

class PayslipDetailScreen extends ConsumerStatefulWidget {
  const PayslipDetailScreen({super.key, required this.payslip});

  final Payslip payslip;

  @override
  ConsumerState<PayslipDetailScreen> createState() =>
      _PayslipDetailScreenState();
}

class _PayslipDetailScreenState extends ConsumerState<PayslipDetailScreen> {
  bool _downloading = false;

  Future<void> _openPdf() async {
    setState(() => _downloading = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final path = await ref
          .read(payslipRepositoryProvider)
          .downloadPdf(widget.payslip);
      final result = await OpenFilex.open(path);
      if (result.type != ResultType.done && mounted) {
        // Almost always means no PDF viewer is installed. Saying so is more
        // use than "could not open file".
        messenger.showSnackBar(
          const SnackBar(
            content: Text('No app on this device can open a PDF.'),
          ),
        );
      }
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not download that payslip.')),
      );
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final p = widget.payslip;

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(
        title: Text(Fmt.monthYear(p.payMonth, p.payYear)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          AppCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Text(
                  'Net pay',
                  style: TextStyle(color: bos.muted, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  Fmt.money(p.netSalary),
                  style: TextStyle(
                    color: bos.text,
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 10),
                StatusChip(p.status),
                if (p.paidAt != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Paid ${Fmt.date(p.paidAt)}'
                    '${p.paymentMethod != null ? ' · ${Fmt.label(p.paymentMethod)}' : ''}',
                    style: TextStyle(color: bos.muted, fontSize: 12.5),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 22),
          const SectionHeader('Earnings', icon: Icons.trending_up_rounded),
          _Lines(lines: p.earnings, total: p.gross, totalLabel: 'Gross'),
          const SizedBox(height: 22),
          const SectionHeader('Deductions', icon: Icons.trending_down_rounded),
          if (p.deductionLines.isEmpty)
            AppCard(
              child: Text(
                'Nothing was deducted this month.',
                style: TextStyle(color: bos.muted, fontSize: 13.5),
              ),
            )
          else
            _Lines(
              lines: p.deductionLines,
              total: p.totalDeductions,
              totalLabel: 'Total deductions',
              negative: true,
            ),
          if (p.absentDays != null && p.absentDays! > 0) ...[
            const SizedBox(height: 12),
            MessageBanner.info(
              '${p.absentDays} unpaid absent day'
              '${p.absentDays == 1 ? '' : 's'} counted this month.',
            ),
          ],
          if (p.notes != null && p.notes!.isNotEmpty) ...[
            const SizedBox(height: 22),
            const SectionHeader('Notes', icon: Icons.sticky_note_2_outlined),
            AppCard(
              child: Text(
                p.notes!,
                style: TextStyle(
                  color: bos.textSecondary,
                  fontSize: 13.5,
                  height: 1.4,
                ),
              ),
            ),
          ],
          const SizedBox(height: 26),
          if (p.canDownload)
            LoadingButton(
              label: 'Open PDF payslip',
              loading: _downloading,
              icon: Icons.picture_as_pdf_outlined,
              onPressed: _openPdf,
            )
          else
            // A DRAFT has not been approved, so its figures can still change.
            // Handing someone a document that does not match what they are
            // eventually paid causes more trouble than withholding it.
            MessageBanner.info(
              'This payslip is still a draft. The PDF becomes available once '
              'payroll approves it.',
            ),
        ],
      ),
    );
  }
}

class _Lines extends StatelessWidget {
  const _Lines({
    required this.lines,
    required this.total,
    required this.totalLabel,
    this.negative = false,
  });

  final List<({String label, double amount})> lines;
  final double total;
  final String totalLabel;
  final bool negative;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return AppCard(
      child: Column(
        children: [
          for (final line in lines) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      line.label,
                      style: TextStyle(color: bos.textSecondary, fontSize: 13.5),
                    ),
                  ),
                  Text(
                    Fmt.money(line.amount),
                    style: TextStyle(
                      color: bos.text,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 6),
          Divider(height: 1, color: bos.borderLight),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  totalLabel,
                  style: TextStyle(
                    color: bos.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${negative ? '- ' : ''}${Fmt.money(total)}',
                style: TextStyle(
                  color: negative ? bos.danger : bos.success,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
