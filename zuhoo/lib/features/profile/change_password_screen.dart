import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/auth_models.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/widgets/primitives.dart';

class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();

  bool _show = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(authRepositoryProvider).changePassword(
            ChangePasswordRequest(
              currentPassword: _current.text,
              newPassword: _next.text,
              confirmPassword: _confirm.text,
            ),
          );

      messenger.showSnackBar(
        const SnackBar(
          content: Text('Password changed. Please sign in again.'),
        ),
      );

      // The backend revokes every refresh token on a successful change, so the
      // tokens this device is holding are already dead. Signing out here is
      // what makes that visible now rather than as a confusing failure on the
      // next request.
      await ref.read(authControllerProvider.notifier).clearSession();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not change your password.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(title: const Text('Change password')),
      body: SingleChildScrollView(
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
              MessageBanner.info(
                'Changing your password signs you out everywhere, including '
                'this device.',
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _current,
                obscureText: !_show,
                decoration: InputDecoration(
                  labelText: 'Current password',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _show
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                    onPressed: () => setState(() => _show = !_show),
                  ),
                ),
                validator: (v) => (v == null || v.isEmpty)
                    ? 'Enter your current password.'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _next,
                obscureText: !_show,
                decoration: const InputDecoration(
                  labelText: 'New password',
                  prefixIcon: Icon(Icons.password_rounded),
                ),
                validator: (v) {
                  if (v == null || v.length < 8) {
                    return 'Use at least 8 characters.';
                  }
                  if (v == _current.text) {
                    return 'That is your current password.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _confirm,
                obscureText: !_show,
                decoration: const InputDecoration(
                  labelText: 'Confirm new password',
                  prefixIcon: Icon(Icons.lock_reset_rounded),
                ),
                validator: (v) =>
                    v == _next.text ? null : 'Those do not match.',
              ),
              const SizedBox(height: 24),
              LoadingButton(
                label: 'Change password',
                loading: _saving,
                icon: Icons.check_rounded,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
