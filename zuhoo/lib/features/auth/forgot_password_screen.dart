import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_models.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/widgets/primitives.dart';

enum _Step { email, code, password }

/// The three-step reset: ask for a code, check it, set a new password.
///
/// The middle step exists so someone who mistypes the code finds out before
/// they have composed a new password, rather than after. It deliberately does
/// not consume the code — the final call re-validates it for real.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  _Step _step = _Step.email;
  bool _loading = false;
  bool _showPassword = false;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_loading) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await action();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _sendCode() => _run(() async {
        await ref
            .read(authRepositoryProvider)
            .forgotPassword(_email.text.trim());
        if (!mounted) return;
        setState(() {
          _step = _Step.code;
          // Worded so it says nothing about whether the account exists. The
          // backend answers 200 either way on purpose, and a message like
          // "we couldn't find that email" would hand back exactly the
          // information it is refusing to leak.
          _notice = 'If that email has an account, a 6-digit code is on its way.';
        });
      });

  void _verifyCode() => _run(() async {
        await ref
            .read(authRepositoryProvider)
            .verifyResetCode(_email.text.trim(), _code.text.trim());
        if (!mounted) return;
        setState(() {
          _step = _Step.password;
          _notice = null;
        });
      });

  void _resetPassword() => _run(() async {
        await ref.read(authRepositoryProvider).resetPassword(
              ResetPasswordRequest(
                email: _email.text.trim(),
                code: _code.text.trim(),
                newPassword: _password.text,
                confirmPassword: _confirm.text,
              ),
            );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password changed. Sign in with your new password.'),
          ),
        );
        context.pop();
      });

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Scaffold(
      backgroundColor: bos.bgPage,
      appBar: AppBar(
        title: const Text('Reset password'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => _step == _Step.email
              ? context.pop()
              : setState(() {
                  _step = _Step.values[_step.index - 1];
                  _error = null;
                }),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      switch (_step) {
                        _Step.email => 'Where should we send the code?',
                        _Step.code => 'Enter the 6-digit code',
                        _Step.password => 'Choose a new password',
                      },
                      style: TextStyle(
                        color: bos.text,
                        fontSize: 19,
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
                    if (_notice != null) ...[
                      MessageBanner.info(_notice!),
                      const SizedBox(height: 14),
                    ],
                    ..._fieldsFor(_step),
                    const SizedBox(height: 20),
                    LoadingButton(
                      label: switch (_step) {
                        _Step.email => 'Send code',
                        _Step.code => 'Continue',
                        _Step.password => 'Change password',
                      },
                      loading: _loading,
                      onPressed: switch (_step) {
                        _Step.email => _sendCode,
                        _Step.code => _verifyCode,
                        _Step.password => _resetPassword,
                      },
                    ),
                    if (_step == _Step.code)
                      TextButton(
                        onPressed: _loading ? null : _sendCode,
                        child: const Text('Send another code'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _fieldsFor(_Step step) {
    switch (step) {
      case _Step.email:
        return [
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.alternate_email_rounded),
            ),
            validator: (v) {
              final value = v?.trim() ?? '';
              if (value.isEmpty) return 'Enter your email.';
              if (!value.contains('@')) return 'Enter a valid email.';
              return null;
            },
          ),
        ];

      case _Step.code:
        return [
          TextFormField(
            controller: _code,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            style: const TextStyle(fontSize: 22, letterSpacing: 8),
            textAlign: TextAlign.center,
            decoration: const InputDecoration(
              labelText: 'Code',
              hintText: '000000',
              hintStyle: TextStyle(fontSize: 22, letterSpacing: 8),
            ),
            validator: (v) => (v?.trim().length ?? 0) == 6
                ? null
                : 'Enter the 6-digit code.',
          ),
        ];

      case _Step.password:
        return [
          TextFormField(
            controller: _password,
            obscureText: !_showPassword,
            decoration: InputDecoration(
              labelText: 'New password',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                icon: Icon(
                  _showPassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
                onPressed: () =>
                    setState(() => _showPassword = !_showPassword),
              ),
            ),
            validator: (v) => (v == null || v.length < 8)
                ? 'Use at least 8 characters.'
                : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _confirm,
            obscureText: !_showPassword,
            decoration: const InputDecoration(
              labelText: 'Confirm new password',
              prefixIcon: Icon(Icons.lock_reset_rounded),
            ),
            validator: (v) =>
                v == _password.text ? null : 'Those do not match.',
          ),
        ];
    }
  }
}
