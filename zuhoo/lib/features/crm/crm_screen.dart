import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/permission_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/primitives.dart';
import 'clients_tab.dart';
import 'crm_controllers.dart';
import 'crm_models.dart';
import 'leads_tab.dart';
import 'pipeline_tab.dart';

/// The CRM shell.
///
/// Each tab is gated on the permission the backend enforces for it, and the
/// tabs are assembled from whatever survives — a rep with only LEAD_VIEW gets a
/// one-tab screen rather than two tabs that 403.
class CrmScreen extends ConsumerWidget {
  const CrmScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final permissions = ref.watch(permissionControllerProvider);

    if (!permissions.loaded && permissions.codes.isEmpty) {
      return Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(title: const Text('CRM')),
        body: const Loader(),
      );
    }

    final tabs = <({String label, Widget view, bool showsNewLead})>[
      if (permissions.has(CrmPermissions.opportunityView))
        (label: 'Pipeline', view: const PipelineTab(), showsNewLead: false),
      if (permissions.has(CrmPermissions.leadView))
        (label: 'Leads', view: const LeadsTab(), showsNewLead: true),
      if (permissions.has(CrmPermissions.clientView))
        (label: 'Clients', view: const ClientsTab(), showsNewLead: false),
    ];

    if (tabs.isEmpty) {
      return Scaffold(
        backgroundColor: bos.bgPage,
        appBar: AppBar(title: const Text('CRM')),
        body: const EmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Not available to you',
          message:
              'Your role does not include access to the CRM. Ask your '
              'administrator if you think it should.',
        ),
      );
    }

    return DefaultTabController(
      length: tabs.length,
      child: Builder(
        builder: (context) {
          // Read from the controller so the FAB can appear only on the Leads
          // tab — a "New lead" button floating over the pipeline would create
          // the wrong thing.
          final tabController = DefaultTabController.of(context);
          return AnimatedBuilder(
            animation: tabController,
            builder: (context, _) {
              final showNewLead = tabs[tabController.index].showsNewLead;
              return Scaffold(
                backgroundColor: bos.bgPage,
                appBar: AppBar(
                  title: const Text('CRM'),
                  bottom: tabs.length > 1
                      ? TabBar(
                          tabs: [for (final tab in tabs) Tab(text: tab.label)],
                        )
                      : null,
                ),
                floatingActionButton: showNewLead
                    ? FloatingActionButton.extended(
                        onPressed: () => showNewLeadSheet(context),
                        backgroundColor: bos.brand,
                        foregroundColor: Colors.white,
                        icon: const Icon(Icons.person_add_alt_rounded),
                        label: const Text('New lead'),
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

Future<void> showNewLeadSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _NewLeadSheet(),
  );
}

class _NewLeadSheet extends ConsumerStatefulWidget {
  const _NewLeadSheet();

  @override
  ConsumerState<_NewLeadSheet> createState() => _NewLeadSheetState();
}

class _NewLeadSheetState extends ConsumerState<_NewLeadSheet> {
  final _formKey = GlobalKey<FormState>();
  final _contactName = TextEditingController();
  final _companyName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _value = TextEditingController();

  String _source = leadSources.first;
  String _priority = 'NORMAL';
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _contactName.dispose();
    _companyName.dispose();
    _email.dispose();
    _phone.dispose();
    _value.dispose();
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
      await ref.read(leadsProvider.notifier).create(
            CreateLeadRequest(
              contactName: _contactName.text,
              source: _source,
              companyName: _companyName.text,
              email: _email.text,
              phone: _phone.text,
              priority: _priority,
              estimatedValue: double.tryParse(_value.text.trim()),
            ),
          );
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(const SnackBar(content: Text('Lead captured.')));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not capture that lead.');
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
                'New lead',
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
                controller: _contactName,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Contact name',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Who is this lead?'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _companyName,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Company (optional)',
                  prefixIcon: Icon(Icons.business_outlined),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Email (optional)',
                  prefixIcon: Icon(Icons.alternate_email_rounded),
                ),
                validator: (value) {
                  final trimmed = value?.trim() ?? '';
                  if (trimmed.isEmpty) return null;
                  return trimmed.contains('@') ? null : 'That is not an email.';
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone (optional)',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _source,
                decoration: const InputDecoration(
                  labelText: 'Source',
                  prefixIcon: Icon(Icons.input_rounded),
                ),
                items: [
                  for (final source in leadSources)
                    DropdownMenuItem(
                      value: source,
                      child: Text(Fmt.label(source)),
                    ),
                ],
                onChanged: _submitting
                    ? null
                    : (value) => setState(() => _source = value ?? _source),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _priority,
                decoration: const InputDecoration(
                  labelText: 'Priority',
                  prefixIcon: Icon(Icons.flag_outlined),
                ),
                items: [
                  for (final priority in leadPriorities)
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
                controller: _value,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Estimated value (optional)',
                  prefixIcon: Icon(Icons.payments_outlined),
                ),
                validator: (value) {
                  final trimmed = value?.trim() ?? '';
                  if (trimmed.isEmpty) return null;
                  return double.tryParse(trimmed) == null
                      ? 'Enter a number.'
                      : null;
                },
              ),
              const SizedBox(height: 20),
              LoadingButton(
                label: 'Capture lead',
                loading: _submitting,
                icon: Icons.person_add_alt_rounded,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
