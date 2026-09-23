import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/auth_controller.dart';
import '../core/branding_controller.dart';
import '../core/config/login_theme_assets.dart';
import '../ui/common.dart';

/// Development/demo sign-in shortcut. `kDebugMode` is false in release builds, so this never ships to production;
/// these must still authenticate through the real /auth/login call, same as any other credentials.
class _DemoUser {
  const _DemoUser(this.label, this.loginId, this.password);
  final String label;
  final String loginId;
  final String password;
}

const _demoUsers = [
  _DemoUser('Login as Admin', 'admin', 'DineFlow@123'),
  _DemoUser('Login as Manager', 'manager', 'Demo@123'),
];

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

  Future<void> _loginAsDemo(_DemoUser user) async {
    _email.text = user.loginId;
    _password.text = user.password;
    await _submit();
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.watch<BrandingController>();
    final auth = context.watch<AuthController>();
    final theme = Theme.of(context);
    final logo = brand.branding?.logoUrl;
    final isDark = theme.brightness == Brightness.dark;
    final assets = LoginThemeAssets.forTenant(brand.branding?.tenantCode);
    final cardColor = isDark ? const Color(0xE6181820) : const Color(0xE6FFFFFF);

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(isDark ? assets.dark : assets.light, fit: BoxFit.cover),
          Container(color: isDark ? const Color(0x73111827) : const Color(0x40FFFFFF)),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 24, offset: Offset(0, 8))],
                    ),
                    child: Form(
                      key: _form,
                      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        if (logo != null && logo.isNotEmpty)
                          Image.network(logo, height: 140, errorBuilder: (_, _, _) => Image.asset('assets/icons/app_icon.jpg', height: 140))
                        else
                          Image.asset('assets/icons/app_icon.jpg', height: 140),
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
                          autofillHints: const [AutofillHints.username],
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(labelText: 'Email or Login ID', prefixIcon: Icon(Icons.mail_outline)),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your email or login ID' : null,
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
                        if (kDebugMode) ...[
                          const SizedBox(height: 20),
                          const Divider(),
                          const SizedBox(height: 4),
                          Text('Demo Login', textAlign: TextAlign.center, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline, letterSpacing: 1)),
                          const SizedBox(height: 8),
                          for (final user in _demoUsers) ...[
                            OutlinedButton(onPressed: _busy ? null : () => _loginAsDemo(user), child: Text(user.label)),
                            const SizedBox(height: 8),
                          ],
                          Text('Development / Demo Environment', textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                        ],
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
