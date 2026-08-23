import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/primitives.dart';
import 'support_controllers.dart';
import 'support_models.dart';

Future<void> showNewTicketSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _NewTicketSheet(),
  );
}

class _NewTicketSheet extends ConsumerStatefulWidget {
  const _NewTicketSheet();

  @override
  ConsumerState<_NewTicketSheet> createState() => _NewTicketSheetState();
}

class _NewTicketSheetState extends ConsumerState<_NewTicketSheet> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();

  String _priority = 'MEDIUM';
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
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
      await ref.read(myTicketsProvider.notifier).create(
            CreateTicketRequest(
              title: _title.text,
              description: _description.text,
              priority: _priority,
            ),
          );
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        const SnackBar(content: Text('Ticket raised.')),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not raise that ticket.');
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
                'Report a problem',
                style: TextStyle(
                  color: bos.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              // Says who receives it. The same screen also lists conversations
              // with this company's *own* clients, and a ticket sent to the
              // wrong audience is worse than no ticket.
              Text(
                'This goes to the Zuhoo support team.',
                style: TextStyle(color: bos.muted, fontSize: 12.5),
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
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  hintText: 'A one-line summary',
                  prefixIcon: Icon(Icons.title_rounded),
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Give this ticket a title.'
                    : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _priority,
                decoration: const InputDecoration(
                  labelText: 'Priority',
                  prefixIcon: Icon(Icons.flag_outlined),
                ),
                items: [
                  for (final priority in ticketPriorities)
                    DropdownMenuItem(
                      value: priority,
                      child: Text(Fmt.label(priority)),
                    ),
                ],
                onChanged: _submitting
                    ? null
                    : (value) => setState(() => _priority = value ?? _priority),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _description,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'What happened',
                  alignLabelWithHint: true,
                  hintText:
                      'What you were doing, what you expected, what happened '
                      'instead',
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Describe the problem so it can be reproduced.'
                    : null,
              ),
              const SizedBox(height: 20),
              LoadingButton(
                label: 'Raise ticket',
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
