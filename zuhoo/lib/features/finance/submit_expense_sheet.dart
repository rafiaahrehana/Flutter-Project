import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/primitives.dart';
import 'finance_models.dart';
import 'finance_repository.dart';

Future<void> showSubmitExpenseSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _SubmitExpenseSheet(),
  );
}

/// Claiming an expense — the one finance task people genuinely do on a phone,
/// standing next to the thing they just paid for.
class _SubmitExpenseSheet extends ConsumerStatefulWidget {
  const _SubmitExpenseSheet();

  @override
  ConsumerState<_SubmitExpenseSheet> createState() =>
      _SubmitExpenseSheetState();
}

class _SubmitExpenseSheetState extends ConsumerState<_SubmitExpenseSheet> {
  final _formKey = GlobalKey<FormState>();
  final _description = TextEditingController();
  final _amount = TextEditingController();
  final _vendor = TextEditingController();
  final _category = TextEditingController();

  /// Defaults to today, because that is when almost every claim is made.
  DateTime _date = DateTime.now();

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    _vendor.dispose();
    _category.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      // A year back covers a late claim; nothing in the future, because you
      // cannot have already spent money you have not spent.
      firstDate: DateTime(now.year - 1),
      lastDate: now,
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(expensesProvider.notifier).submit(
            CreateExpenseRequest(
              description: _description.text,
              amount: double.parse(_amount.text.trim()),
              expenseDate: Fmt.isoDate(_date),
              vendorName: _vendor.text,
              category: _category.text,
            ),
          );
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        const SnackBar(content: Text('Claim submitted for approval.')),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not submit that claim.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
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
                'Claim an expense',
                style: TextStyle(
                  color: bos.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 18),
              if (_error != null) ...[
                MessageBanner.error(
                  _error!,
                  onDismiss: () => setState(() => _error = null),
                ),
                const SizedBox(height: 14),
              ],
              TextFormField(
                controller: _amount,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  prefixIcon: Icon(Icons.payments_outlined),
                ),
                validator: (value) {
                  final parsed = double.tryParse(value?.trim() ?? '');
                  if (parsed == null) return 'Enter the amount.';
                  if (parsed <= 0) return 'Enter an amount above zero.';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _description,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'What was it for',
                  hintText: 'Taxi to the client site',
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Whoever approves this needs to know what it was.'
                    : null,
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: _submitting ? null : _pickDate,
                borderRadius: BorderRadius.circular(8),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Date',
                    prefixIcon: Icon(Icons.event_outlined),
                  ),
                  child: Text(
                    Fmt.date(Fmt.isoDate(_date)),
                    style: TextStyle(color: bos.text, fontSize: 15),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _vendor,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Paid to (optional)',
                  prefixIcon: Icon(Icons.storefront_outlined),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _category,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Category (optional)',
                  hintText: 'Travel, Meals, Software...',
                  prefixIcon: Icon(Icons.sell_outlined),
                ),
              ),
              const SizedBox(height: 12),
              // Said rather than left to be discovered: the web app attaches a
              // receipt image, and this build does not, so a claim raised here
              // may need one added before it can be approved.
              MessageBanner.info(
                'Receipts cannot be attached from the phone yet. If your '
                'approver needs one, add it from the web app.',
              ),
              const SizedBox(height: 18),
              LoadingButton(
                label: 'Submit claim',
                loading: _submitting,
                icon: Icons.send_rounded,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
