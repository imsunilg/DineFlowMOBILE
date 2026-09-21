import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/auth_controller.dart';
import 'core/branding_controller.dart';
import 'core/nav.dart';
import 'features/bar_stock_screen.dart';
import 'features/customers_screen.dart';
import 'features/dashboard_screen.dart';
import 'features/inventory_screen.dart';
import 'features/kitchen_screen.dart';
import 'features/login_screen.dart';
import 'features/more_screens.dart';
import 'features/notifications_screen.dart';
import 'features/order_detail_screen.dart';
import 'features/orders_screen.dart';
import 'features/pos_screen.dart';
import 'features/reservations_screen.dart';
import 'features/shell.dart';
import 'features/tables_screen.dart';

/// Routes a signed-in user may not open (missing permission or module switched off) fall back to their
/// first permitted screen, mirroring the web app's guards. The API still enforces permissions itself.
GoRouter buildRouter(AuthController auth, BrandingController brand) {
  List<Destination> allowed() => destinationsFor(roles: auth.user?.roles ?? const [], can: auth.can, featureOn: brand.isEnabled);
  String home() => allowed().isEmpty ? '/profile' : allowed().first.path;

  Destination? match(String loc) {
    Destination? best;
    for (final d in destinations.values) {
      if ((loc == d.path || loc.startsWith('${d.path}/')) && (best == null || d.path.length > best.path.length)) best = d;
    }
    return best;
  }

  String? redirect(BuildContext context, GoRouterState state) {
    final loc = state.matchedLocation;
    switch (auth.status) {
      case AuthStatus.unknown:
        return loc == '/splash' ? null : '/splash';
      case AuthStatus.signedOut:
        return loc == '/login' || loc == '/settings' ? null : '/login';
      case AuthStatus.signedIn:
        if (loc == '/login' || loc == '/splash' || loc == '/') return home();
        final d = match(loc);
        if (d != null && !allowed().any((a) => a.id == d.id) && d.permission != null) return home();
        return null;
    }
  }

  return GoRouter(
    initialLocation: '/',
    refreshListenable: Listenable.merge([auth, brand]),
    redirect: redirect,
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const Scaffold(body: Center(child: CircularProgressIndicator()))),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
      GoRoute(path: '/', builder: (_, _) => const SizedBox.shrink()),
      GoRoute(path: '/table/:id', builder: (_, s) => PosScreen(tableId: s.pathParameters['id'], tableCode: s.uri.queryParameters['code'])),
      GoRoute(path: '/order/:id', builder: (_, s) => OrderDetailScreen(orderId: s.pathParameters['id']!)),
      GoRoute(path: '/customer/:id', builder: (_, s) => CustomerDetailScreen(customerId: s.pathParameters['id']!)),
      ShellRoute(
        builder: (_, state, child) => HomeShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(path: '/dashboard', builder: (_, _) => const DashboardScreen()),
          GoRoute(path: '/tables', builder: (_, _) => const TablesScreen()),
          GoRoute(path: '/orders', builder: (_, _) => const OrdersScreen()),
          GoRoute(path: '/pos', builder: (_, s) => PosScreen(key: ValueKey('pos-${s.uri.queryParameters['order']}'), orderId: s.uri.queryParameters['order'])),
          GoRoute(path: '/bar', builder: (_, s) => PosScreen(key: ValueKey('bar-${s.uri.queryParameters['order']}'), area: 'Bar', orderId: s.uri.queryParameters['order'])),
          GoRoute(path: '/bar/stock', builder: (_, _) => const BarStockScreen()),
          GoRoute(path: '/kitchen', builder: (_, _) => const KitchenScreen()),
          GoRoute(path: '/customers', builder: (_, _) => const CustomersScreen()),
          GoRoute(path: '/reservations', builder: (_, _) => const ReservationsScreen()),
          GoRoute(path: '/inventory', builder: (_, _) => const InventoryScreen()),
          GoRoute(path: '/notifications', builder: (_, _) => const NotificationsScreen()),
          GoRoute(path: '/more', builder: (_, _) => const MoreScreen()),
          GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
        ],
      ),
    ],
  );
}

class DineFlowApp extends StatefulWidget {
  const DineFlowApp({super.key});

  @override
  State<DineFlowApp> createState() => _DineFlowAppState();
}

class _DineFlowAppState extends State<DineFlowApp> {
  late final GoRouter _router = buildRouter(context.read<AuthController>(), context.read<BrandingController>());

  @override
  Widget build(BuildContext context) {
    final brand = context.watch<BrandingController>();
    return MaterialApp.router(
      title: brand.displayName,
      debugShowCheckedModeBanner: false,
      theme: brand.theme(Brightness.light),
      darkTheme: brand.theme(Brightness.dark),
      routerConfig: _router,
    );
  }
}
