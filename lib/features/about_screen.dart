import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ui/common.dart';

const _developerName = 'Sunil B Gadakari';
const _developerEmail = 'sunilbgadakari@gmail.com';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  PackageInfo? _info;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _info = info);
    });
  }

  Future<void> _emailDeveloper() async {
    final uri = Uri(scheme: 'mailto', path: _developerEmail);
    if (!await launchUrl(uri) && mounted) context.toast('Could not open an email app', error: true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final version = _info?.version ?? '—';
    final build = _info?.buildNumber ?? '—';

    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const SectionTitle('About Application'),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Image.asset('assets/icons/app_icon.jpg', height: 44, width: 44, fit: BoxFit.cover),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('DineFlow', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                    Text('Bar & Restaurant Management CRM', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)),
                  ]),
                ),
              ]),
              const SizedBox(height: 16),
              Text(
                'DineFlow is a modern Bar & Restaurant Management CRM designed to manage orders, tables, '
                'inventory, bar stock, billing, customers, staff and real-time restaurant operations from '
                'Web and Mobile.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              _InfoRow(label: 'Platform', value: 'Web + Android Mobile'),
              _InfoRow(label: 'Technology', value: 'Angular + ASP.NET Core + PostgreSQL + Flutter'),
              _InfoRow(label: 'Version', value: version),
              _InfoRow(label: 'Build', value: build),
            ]),
          ),
        ),
        const SectionTitle('About Developer'),
        Card(
          margin: EdgeInsets.zero,
          child: Column(children: [
            ListTile(leading: const Icon(Icons.person_outline), title: const Text(_developerName), subtitle: const Text('Developer')),
            ListTile(
              leading: const Icon(Icons.mail_outline),
              title: const Text(_developerEmail),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: _emailDeveloper,
            ),
          ]),
        ),
      ]),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(width: 90, child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline))),
        Expanded(child: Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
      ]),
    );
  }
}
