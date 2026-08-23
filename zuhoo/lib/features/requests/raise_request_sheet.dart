import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/primitives.dart';
import 'request_controllers.dart';
import 'request_models.dart';

Future<void> showRaiseRequestSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _RaiseRequestSheet(),
  );
}

class _RaiseRequestSheet extends ConsumerStatefulWidget {
  const _RaiseRequestSheet();

  @override
  ConsumerState<_RaiseRequestSheet> createState() => _RaiseRequestSheetState();
}

class _RaiseRequestSheetState extends ConsumerState<_RaiseRequestSheet> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();

  CatalogService? _service;
  String _priority = 'NORMAL';
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  void _pickService(CatalogService? service) {
    setState(() {
      _service = service;
      // The catalogue entry carries a default priority; adopt it so the common
      // case needs no thought, while leaving the field editable.
      if (service?.defaultPriority != null &&
          requestPriorities.contains(service!.defaultPriority)) {
        _priority = service.defaultPriority!;
      }
    });
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final service = _service;
    if (service == null) {
      setState(() => _error = 'Choose the service this request is for.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(myRequestsProvider.notifier).create(
            CreateServiceRequest(
              title: _title.text,
              hubServiceId: service.id,
              description: _description.text,
              priority: _priority,
            ),
          );
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        const SnackBar(content: Text('Request submitted.')),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not submit that request.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;
    final catalogue = ref.watch(catalogServicesProvider);

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
                'New request',
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
              catalogue.when(
                loading: () => const Loader(padding: 16),
                error: (error, _) => MessageBanner.error(
                  error is ApiException
                      ? error.message
                      : 'Could not load the service catalogue.',
                ),
                data: (services) {
                  if (services.isEmpty) {
                    return const MessageBanner.info(
                      'Your company has no active services to request yet.',
                    );
                  }
                  return DropdownButtonFormField<CatalogService>(
                    initialValue: _service,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Service',
                      prefixIcon: Icon(Icons.category_outlined),
                    ),
                    items: [
                      for (final service in services)
                        DropdownMenuItem(
                          value: service,
                          child: Text(
                            service.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _submitting ? null : _pickService,
                    validator: (value) =>
                        value == null ? 'Choose a service.' : null,
                  );
                },
              ),
              if (_service != null) ...[
                const SizedBox(height: 8),
                _ServiceHint(service: _service!),
              ],
              const SizedBox(height: 16),
              TextFormField(
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  hintText: 'A short summary of what you need',
                  prefixIcon: Icon(Icons.title_rounded),
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Give this request a title.'
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
                  for (final priority in requestPriorities)
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
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Details (optional)',
                  alignLabelWithHint: true,
                  hintText: 'Anything the person picking this up should know',
                ),
              ),
              const SizedBox(height: 12),
              // Said plainly rather than hidden: PAY_NOW returns an invoice and
              // a gateway redirect, and a half-built checkout on a phone is a
              // worse outcome than sending someone to the invoice they will get.
              MessageBanner.info(
                'Submitted without payment. If this service is chargeable, an '
                'invoice follows and can be paid from the web app.',
              ),
              const SizedBox(height: 18),
              LoadingButton(
                label: 'Submit request',
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

/// What the catalogue says about the chosen service — price, turnaround, and
/// whether it will need a quotation or documents before it can proceed.
class _ServiceHint extends StatelessWidget {
  const _ServiceHint({required this.service});

  final CatalogService service;

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    final facts = <String>[
      if (service.categoryName != null) service.categoryName!,
      if (service.price != null)
        '${Fmt.money(service.price)}'
            '${service.priceType != null ? ' · ${Fmt.label(service.priceType)}' : ''}',
      if (service.estimatedDays != null)
        '~${service.estimatedDays} day${service.estimatedDays == 1 ? '' : 's'}',
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bos.bgSubtle,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: bos.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (facts.isNotEmpty)
            Text(
              facts.join('   ·   '),
              style: TextStyle(
                color: bos.textSecondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (service.description != null &&
              service.description!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              service.description!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: bos.muted, fontSize: 12.5, height: 1.35),
            ),
          ],
          if (service.requiresQuotation || service.requiresDocuments) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 14, color: bos.info),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    [
                      if (service.requiresQuotation)
                        'a quotation will be prepared before work starts',
                      if (service.requiresDocuments)
                        'documents will need to be attached from the web app',
                    ].join(', and '),
                    style: TextStyle(color: bos.info, fontSize: 12, height: 1.3),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
