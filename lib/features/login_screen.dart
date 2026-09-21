import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/auth_controller.dart';
import '../core/branding_controller.dart';
import '../ui/common.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _hidden = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final auth = context.read<AuthController>();
    final brand = context.read<BrandingController>();
    try {
      await auth.login(_email.text, _password.text);
      await brand.load(tenantCode: auth.user?.tenantCode);
    } catch (e) {
      if (mounted) context.toastError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.watch<BrandingController>();
    final auth = context.watch<AuthController>();
    final theme = Theme.of(context);
    final logo = brand.branding?.logoUrl;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (logo != null && logo.isNotEmpty)
                    Image.network(logo, height: 72, errorBuilder: (_, _, _) => const SizedBox.shrink())
                  else
                    Icon(Icons.restaurant, size: 64, color: theme.colorScheme.primary),
                  const SizedBox(height: 16),
                  Text(brand.displayName.isEmpty ? 'Welcome' : brand.displayName, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700), textAlign: TextAlign.center),
                  const SizedBox(height: 4),
                  Text('Sign in to continue', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline), textAlign: TextAlign.center),
                  if (auth.sessionExpired) ...[
                    const SizedBox(height: 16),
                    Text('Your session expired. Please sign in again.', style: TextStyle(color: theme.colorScheme.error), textAlign: TextAlign.center),
                  ],
                  const SizedBox(height: 28),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.username],
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline)),
                    validator: (v) => (v == null || !v.contains('@')) ? 'Enter your email address' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _password,
                    obscureText: _hidden,
                    autofillHints: const [AutofillHints.password],
                    onFieldSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(tooltip: _hidden ? 'Show password' : 'Hide password', icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined), onPressed: () => setState(() => _hidden = !_hidden)),
                    ),
                    validator: (v) => (v == null || v.isEmpty) ? 'Enter your password' : null,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Sign in'),
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(onPressed: () => context.push('/settings'), icon: const Icon(Icons.settings_outlined), label: const Text('Server settings')),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
