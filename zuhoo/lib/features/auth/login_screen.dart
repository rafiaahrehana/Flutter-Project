import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/config/env.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/bos_tokens.dart';
import '../../shared/widgets/primitives.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _showPassword = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await ref
          .read(authControllerProvider.notifier)
          .login(_email.text, _password.text);
      // No navigation here: the router's redirect watches the auth state and
      // moves us as soon as it flips. Pushing as well would race it.
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

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return Scaffold(
      backgroundColor: bos.bgPage,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Header(bos: bos),
                  const SizedBox(height: 28),
                  AppCard(
                    padding: const EdgeInsets.all(22),
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
                          TextFormField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            autofillHints: const [AutofillHints.email],
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              hintText: 'you@company.com',
                              prefixIcon: Icon(Icons.alternate_email_rounded),
                            ),
                            validator: (v) {
                              final value = v?.trim() ?? '';
                              if (value.isEmpty) return 'Enter your email.';
                              if (!value.contains('@') || !value.contains('.')) {
                                return 'Enter a valid email.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _password,
                            obscureText: !_showPassword,
                            textInputAction: TextInputAction.done,
                            autofillHints: const [AutofillHints.password],
                            onFieldSubmitted: (_) => _submit(),
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(Icons.lock_outline_rounded),
                              suffixIcon: IconButton(
                                tooltip: _showPassword ? 'Hide' : 'Show',
                                icon: Icon(
                                  _showPassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                ),
                                onPressed: () => setState(
                                  () => _showPassword = !_showPassword,
                                ),
                              ),
                            ),
                            validator: (v) => (v == null || v.isEmpty)
                                ? 'Enter your password.'
                                : null,
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _loading
                                  ? null
                                  : () => context.push(Routes.forgotPassword),
                              child: const Text('Forgot password?'),
                            ),
                          ),
                          const SizedBox(height: 6),
                          LoadingButton(
                            label: _loading ? 'Signing in...' : 'Sign in',
                            loading: _loading,
                            icon: Icons.login_rounded,
                            onPressed: _submit,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  // Which backend this build talks to is genuinely useful on a
                  // phone: an emulator, a device on the office wifi and a
                  // staging build all look identical otherwise, and "it says
                  // wrong password" is usually "it is asking the wrong server".
                  Text(
                    Env.apiUrl,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: bos.muted, fontSize: 11.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.bos});

  final BosPalette bos;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 64,
          width: 64,
          decoration: BoxDecoration(
            color: bos.brand,
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Icon(Icons.grid_view_rounded,
              color: Colors.white, size: 30),
        ),
        const SizedBox(height: 16),
        Text(
          'Zuhoo',
          style: TextStyle(
            color: bos.text,
            fontSize: 26,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Sign in to your workspace',
          style: TextStyle(color: bos.muted, fontSize: 14),
        ),
      ],
    );
  }
}
