import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/auth_controller.dart';
import '../core/branding_controller.dart';
import '../core/config.dart';
import '../core/nav.dart';
import '../ui/common.dart';

/// Everything the user may open that did not fit on the bottom bar.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final brand = context.watch<BrandingController>();
    final extra = planNavigation(roles: auth.user?.roles ?? const [], can: auth.can, featureOn: brand.isEnabled).more;

    return ListView(children: [
      if (extra.isNotEmpty) const SectionTitle('More'),
      for (final d in extra) ListTile(leading: Icon(d.icon), title: Text(d.label), trailing: const Icon(Icons.chevron_right), onTap: () => context.go(d.path)),
      const SectionTitle('Account'),
      ListTile(leading: const Icon(Icons.notifications_outlined), title: const Text('Alerts'), trailing: const Icon(Icons.chevron_right), onTap: () => context.go('/notifications')),
      ListTile(leading: const Icon(Icons.person_outline), title: const Text('Profile'), trailing: const Icon(Icons.chevron_right), onTap: () => context.go('/profile')),
      ListTile(leading: const Icon(Icons.settings_outlined), title: const Text('Server settings'), trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/settings')),
      ListTile(leading: const Icon(Icons.info_outline), title: const Text('About'), trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/about')),
    ]);
  }
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthController>().user;
    final theme = Theme.of(context);
    if (user == null) return const SizedBox.shrink();

    return ListView(padding: const EdgeInsets.all(16), children: [
      Center(
        child: CircleAvatar(radius: 36, backgroundColor: theme.colorScheme.primaryContainer, child: Text(user.fullName.isEmpty ? '?' : user.fullName[0].toUpperCase(), style: theme.textTheme.headlineMedium?.copyWith(color: theme.colorScheme.onPrimaryContainer))),
      ),
      const SizedBox(height: 12),
      Center(child: Text(user.fullName, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700))),
      Center(child: Text(user.email, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline))),
      const SizedBox(height: 16),
      Wrap(alignment: WrapAlignment.center, spacing: 8, children: [for (final r in user.roles) Chip(label: Text(r))]),
      const SectionTitle('Business'),
      ListTile(leading: const Icon(Icons.storefront_outlined), title: Text(context.brand.displayName), subtitle: Text(user.tenantCode ?? '')),
      ListTile(leading: const Icon(Icons.shield_outlined), title: const Text('Permissions'), subtitle: Text('${user.permissions.length} granted by your role(s)')),
      const SizedBox(height: 16),
      FilledButton.tonalIcon(
        onPressed: () async {
          await context.read<AuthController>().logout();
        },
        icon: const Icon(Icons.logout),
        label: const Text('Sign out'),
      ),
    ]);
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _url;
  late final TextEditingController _tenant;

  @override
  void initState() {
    super.initState();
    final c = context.read<AppConfig>();
    _url = TextEditingController(text: c.baseUrl);
    _tenant = TextEditingController(text: c.tenantCode);
  }

  @override
  void dispose() {
    _url.dispose();
    _tenant.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final uri = Uri.tryParse(_url.text.trim());
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https') || uri.host.isEmpty) {
      context.toast('Enter a full address such as https://example.com/api/v1', error: true);
      return;
    }
    final brand = context.read<BrandingController>();
    await context.read<AppConfig>().save(baseUrl: _url.text, tenantCode: _tenant.text);
    await brand.load();
    if (!mounted) return;
    context.toast('Settings saved');
    context.pop();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Server settings')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          TextField(controller: _url, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'API address', helperText: 'For example https://your-server/api/v1')),
          const SizedBox(height: 16),
          TextField(controller: _tenant, decoration: const InputDecoration(labelText: 'Business code (optional)', helperText: 'Shows your branding on the sign-in screen')),
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: const Text('Save')),
        ]),
      );
}
