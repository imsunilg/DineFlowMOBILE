import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/auth_controller.dart';
import '../core/branding_controller.dart';
import '../core/nav.dart';



/// Role-based scaffold: the bottom bar shows the first destinations for the user's role (filtered by
/// permission and enabled modules) and everything else lives under "More".
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.location, required this.child});
  final String location;
  final Widget child;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _unread = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _pollUnread();
    _timer = Timer.periodic(const Duration(seconds: 45), (_) => _pollUnread());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _pollUnread() async {
    try {
      final data = await context.read<ApiClient>().get('notifications/unread-count');
      final count = (data is Map ? data['count'] : 0) as num? ?? 0;
      if (mounted && count.toInt() != _unread) setState(() => _unread = count.toInt());
    } catch (_) {}
  }

  NavPlan _plan(BuildContext context) {
    final auth = context.watch<AuthController>();
    final brand = context.watch<BrandingController>();
    return planNavigation(roles: auth.user?.roles ?? const [], can: auth.can, featureOn: brand.isEnabled);
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan(context);

    final onBar = plan.bar;
    final hasMore = plan.more.isNotEmpty;
    final items = [...onBar, if (hasMore) const Destination('more', 'More', Icons.more_horiz, '/more')];

    // Longest matching path wins so /bar/stock highlights "Bar stock", not "Bar orders".
    var index = -1;
    var best = -1;
    for (var i = 0; i < items.length; i++) {
      final p = items[i].path;
      if ((widget.location == p || widget.location.startsWith('$p/')) && p.length > best) {
        best = p.length;
        index = i;
      }
    }
    if (index < 0) index = hasMore ? items.length - 1 : 0;
    final brand = context.watch<BrandingController>();

    return Scaffold(
      appBar: AppBar(
        title: Text(brand.displayName),
        actions: [
          IconButton(
            tooltip: 'Alerts',
            onPressed: () => context.go('/notifications'),
            icon: Badge(isLabelVisible: _unread > 0, label: Text('$_unread'), child: const Icon(Icons.notifications_outlined)),
          ),
          IconButton(tooltip: 'Profile', onPressed: () => context.go('/profile'), icon: const Icon(Icons.account_circle_outlined)),
        ],
      ),
      body: SafeArea(top: false, child: widget.child),
      bottomNavigationBar: items.length < 2
          ? null
          : NavigationBar(
              selectedIndex: index,
              onDestinationSelected: (i) => context.go(items[i].path),
              destinations: [for (final d in items) NavigationDestination(icon: Icon(d.icon), label: d.label)],
            ),
    );
  }
}
