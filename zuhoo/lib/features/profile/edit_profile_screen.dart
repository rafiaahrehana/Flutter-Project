import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/util/formatters.dart';
import '../../shared/widgets/primitives.dart';
import 'employee_models.dart';
import 'employee_repository.dart';

/// The fields an employee may change about themselves.
///
/// Name, department, designation, shift and salary are all HR's to set and are
/// deliberately absent — the backend rejects them on this endpoint anyway, and
/// showing them greyed out would only invite the question of how to change them
/// here.
class EditProfileScreen extends ConsumerWidget {
  const EditProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bos = Theme.of(context).bos;
    final employee = ref.watch(myEmployeeProvider);

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(title: const Text('Edit profile')),
      body: employee.when(
        loading: () => const Loader(),
        error: (error, _) => ErrorState(
          message: error is ApiException
              ? error.message
              : 'Could not load your record.',
          onRetry: () => ref.invalidate(myEmployeeProvider),
        ),
        data: (record) => record == null
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: EmptyState(
                  icon: Icons.badge_outlined,
                  title: 'No employee record',
                  message:
                      'There is nothing to edit here until your account is '
                      'linked to an employee record.',
                ),
              )
            : _Form(employee: record),
      ),
    );
  }
}

class _Form extends ConsumerStatefulWidget {
  const _Form({required this.employee});

  final Employee employee;

  @override
  ConsumerState<_Form> createState() => _FormState();
}

class _FormState extends ConsumerState<_Form> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _phone;
  late final TextEditingController _workPhone;
  late final TextEditingController _contactName;
  late final TextEditingController _contactPhone;
  late final TextEditingController _contactRelation;

  late String? _gender;

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.employee;
    _phone = TextEditingController(text: e.phone ?? '');
    _workPhone = TextEditingController(text: e.workPhone ?? '');
    _contactName = TextEditingController(text: e.emergencyContactName ?? '');
    _contactPhone = TextEditingController(text: e.emergencyContactPhone ?? '');
    _contactRelation =
        TextEditingController(text: e.emergencyContactRelation ?? '');
    _gender = genderOptions.contains(e.gender) ? e.gender : null;
  }

  @override
  void dispose() {
    _phone.dispose();
    _workPhone.dispose();
    _contactName.dispose();
    _contactPhone.dispose();
    _contactRelation.dispose();
    super.dispose();
  }

  /// Sends only what actually changed.
  ///
  /// A PATCH that repeats every field would overwrite anything HR edited
  /// between this screen loading and the user pressing save, which on a phone
  /// left open in a pocket can be a long while.
  SelfUpdateEmployeeRequest _buildPatch() {
    final e = widget.employee;
    String? changed(TextEditingController c, String? original) {
      final value = c.text.trim();
      if (value == (original ?? '').trim()) return null;
      return value;
    }

    return SelfUpdateEmployeeRequest(
      phone: changed(_phone, e.phone),
      workPhone: changed(_workPhone, e.workPhone),
      gender: _gender == e.gender ? null : _gender,
      emergencyContactName: changed(_contactName, e.emergencyContactName),
      emergencyContactPhone: changed(_contactPhone, e.emergencyContactPhone),
      emergencyContactRelation:
          changed(_contactRelation, e.emergencyContactRelation),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final patch = _buildPatch();
    if (patch.toJson().isEmpty) {
      Navigator.of(context).pop();
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final updated =
          await ref.read(employeeRepositoryProvider).updateMe(patch);

      // This endpoint also syncs the user's image server-side, and that
      // response never passes through AuthController — so the cached avatar is
      // refreshed explicitly rather than left showing a stale one until the
      // next sign-in.
      await ref.read(authControllerProvider.notifier).setAvatar(updated.image);
      ref.invalidate(myEmployeeProvider);

      messenger.showSnackBar(
        const SnackBar(content: Text('Profile updated.')),
      );
      navigator.pop();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save those changes.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[
              MessageBanner.error(
                _error!,
                onDismiss: () => setState(() => _error = null),
              ),
              const SizedBox(height: 16),
            ],
            const SectionHeader('Contact', icon: Icons.contact_phone_outlined),
            AppCard(
              child: Column(
                children: [
                  TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Personal phone',
                      prefixIcon: Icon(Icons.smartphone_outlined),
                    ),
                    validator: _optionalPhone,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _workPhone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Work phone',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                    validator: _optionalPhone,
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: _gender,
                    decoration: const InputDecoration(
                      labelText: 'Gender',
                      prefixIcon: Icon(Icons.person_outline_rounded),
                    ),
                    items: [
                      for (final g in genderOptions)
                        DropdownMenuItem(value: g, child: Text(Fmt.label(g))),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _gender = value),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            const SectionHeader('Emergency contact',
                icon: Icons.emergency_outlined),
            AppCard(
              child: Column(
                children: [
                  TextFormField(
                    controller: _contactName,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      prefixIcon: Icon(Icons.person_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _contactPhone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone',
                      prefixIcon: Icon(Icons.phone_in_talk_outlined),
                    ),
                    validator: _optionalPhone,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _contactRelation,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Relationship',
                      prefixIcon: Icon(Icons.diversity_1_outlined),
                      hintText: 'Spouse, parent, sibling...',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            LoadingButton(
              label: 'Save changes',
              loading: _saving,
              icon: Icons.check_rounded,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }

  /// Blank is fine — these are all optional. Anything typed has to look like a
  /// phone number, since a half-entered one is worse than none in an emergency.
  static String? _optionalPhone(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    if (v.length < 6) return 'That looks too short to be a phone number.';
    if (!RegExp(r'^[0-9+\-\s()]+$').hasMatch(v)) {
      return 'Use digits, spaces, +, - and brackets only.';
    }
    return null;
  }
}
