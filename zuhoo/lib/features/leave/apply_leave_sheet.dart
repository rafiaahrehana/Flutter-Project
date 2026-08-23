import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/primitives.dart';
import 'leave_models.dart';
import 'leave_repository.dart';

Future<void> showApplyLeaveSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _ApplyLeaveSheet(),
  );
}

class _ApplyLeaveSheet extends ConsumerStatefulWidget {
  const _ApplyLeaveSheet();

  @override
  ConsumerState<_ApplyLeaveSheet> createState() => _ApplyLeaveSheetState();
}

class _ApplyLeaveSheetState extends ConsumerState<_ApplyLeaveSheet> {
  final _reason = TextEditingController();

  String _type = leaveTypes.first;
  DateTimeRange? _range;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  /// Inclusive day count, which is what "3 days off" means to a person.
  ///
  /// Only an estimate: the server recomputes it and excludes weekends and
  /// public holidays, so the figure shown here is labelled as calendar days
  /// rather than presented as the number that will be deducted.
  int? get _calendarDays {
    final range = _range;
    if (range == null) return null;
    return range.end.difference(range.start).inDays + 1;
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      // A year back covers backdating a sick day; a year forward covers
      // booking next year's holiday once balances roll over.
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _range,
    );
    if (picked != null) setState(() => _range = picked);
  }

  Future<void> _submit() async {
    final range = _range;
    if (range == null) {
      setState(() => _error = 'Choose the dates you will be away.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(leaveControllerProvider.notifier).apply(
            LeaveRequestPayload(
              leaveType: _type,
              startDate: Fmt.isoDate(range.start),
              endDate: Fmt.isoDate(range.end),
              reason: _reason.text,
            ),
          );
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        const SnackBar(content: Text('Leave request submitted.')),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not submit that request.');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final days = _calendarDays;

    return Padding(
      // Lifts the sheet above the keyboard so the reason field stays visible
      // while it is being typed into.
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Apply for leave',
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
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(
                labelText: 'Leave type',
                prefixIcon: Icon(Icons.category_outlined),
              ),
              items: [
                for (final type in leaveTypes)
                  DropdownMenuItem(value: type, child: Text(Fmt.label(type))),
              ],
              onChanged: _submitting
                  ? null
                  : (value) => setState(() => _type = value ?? _type),
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: _submitting ? null : _pickRange,
              borderRadius: BorderRadius.circular(8),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Dates',
                  prefixIcon: Icon(Icons.date_range_rounded),
                ),
                child: Text(
                  _range == null
                      ? 'Choose dates'
                      : '${Fmt.date(Fmt.isoDate(_range!.start))} — '
                          '${Fmt.date(Fmt.isoDate(_range!.end))}',
                  style: TextStyle(
                    color: _range == null ? bos.muted : bos.text,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
            if (days != null) ...[
              const SizedBox(height: 8),
              Text(
                '$days calendar day${days == 1 ? '' : 's'}. '
                'Weekends and holidays are excluded when this is approved.',
                style: TextStyle(color: bos.muted, fontSize: 12, height: 1.35),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _reason,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                alignLabelWithHint: true,
                hintText: 'Anything your manager should know',
              ),
            ),
            const SizedBox(height: 20),
            LoadingButton(
              label: 'Submit request',
              loading: _submitting,
              icon: Icons.send_rounded,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
