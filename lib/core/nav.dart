import 'package:flutter/material.dart';

/// One place a signed-in user can go. [permission] and [feature] mirror the web app's route guards.
class Destination {
  const Destination(this.id, this.label, this.icon, this.path, {this.permission, this.feature});
  final String id;
  final String label;
  final IconData icon;
  final String path;
  final String? permission;
  final String? feature;
}

const destinations = <String, Destination>{
  'dashboard': Destination('dashboard', 'Dashboard', Icons.space_dashboard_outlined, '/dashboard', permission: 'Dashboard.View'),
  'tables': Destination('tables', 'Tables', Icons.table_restaurant_outlined, '/tables', permission: 'Table.View', feature: 'restaurantManagement'),
  'orders': Destination('orders', 'Orders', Icons.receipt_long_outlined, '/orders', permission: 'Order.View'),
  'pos': Destination('pos', 'New order', Icons.point_of_sale, '/pos', permission: 'Order.Create', feature: 'restaurantManagement'),
  'kitchen': Destination('kitchen', 'Kitchen', Icons.soup_kitchen_outlined, '/kitchen', permission: 'Kitchen.View'),
  'bar': Destination('bar', 'Bar orders', Icons.local_bar_outlined, '/bar', permission: 'Order.Create', feature: 'barManagement'),
  'barStock': Destination('barStock', 'Bar stock', Icons.liquor_outlined, '/bar/stock', permission: 'Bar.View', feature: 'barManagement'),
  'customers': Destination('customers', 'Customers', Icons.groups_outlined, '/customers', permission: 'Customer.View'),
  'reservations': Destination('reservations', 'Reservations', Icons.event_available_outlined, '/reservations', permission: 'Reservation.View', feature: 'reservation'),
  'inventory': Destination('inventory', 'Inventory', Icons.inventory_2_outlined, '/inventory', permission: 'Inventory.View', feature: 'inventory'),
  'notifications': Destination('notifications', 'Alerts', Icons.notifications_outlined, '/notifications'),
  'profile': Destination('profile', 'Profile', Icons.person_outline, '/profile'),
};

/// Ordered navigation per role (the spec's Waiter / Bartender / Manager views plus the other seeded roles).
/// The first role of the user that has a profile wins; anything not listed still appears under "More"
/// as long as the user is permitted to see it, so custom roles keep working.
const roleProfiles = <String, List<String>>{
  'Owner': ['dashboard', 'orders', 'tables', 'inventory', 'customers', 'reservations', 'kitchen', 'bar', 'barStock'],
  'TenantAdmin': ['dashboard', 'orders', 'tables', 'inventory', 'customers', 'reservations', 'kitchen', 'bar', 'barStock'],
  'SuperAdmin': ['dashboard', 'orders', 'tables', 'inventory', 'customers', 'reservations', 'kitchen', 'bar', 'barStock'],
  'Manager': ['dashboard', 'orders', 'inventory', 'tables', 'customers', 'reservations', 'kitchen', 'bar', 'barStock'],
  'Supervisor': ['dashboard', 'tables', 'orders', 'kitchen', 'customers'],
  'Waiter': ['tables', 'orders', 'customers', 'pos'],
  'Bartender': ['bar', 'barStock', 'orders'],
  'KitchenStaff': ['kitchen', 'orders'],
  'Cashier': ['orders', 'tables', 'customers'],
  'InventoryManager': ['inventory', 'barStock', 'dashboard'],
  'Receptionist': ['reservations', 'tables', 'customers'],
  'Accountant': ['dashboard', 'orders'],
};

const _fallbackOrder = ['dashboard', 'tables', 'orders', 'pos', 'kitchen', 'bar', 'barStock', 'customers', 'reservations', 'inventory'];

/// Destinations the user may open, ordered for their role. Notifications and profile are reachable from every role.
List<Destination> destinationsFor({
  required List<String> roles,
  required bool Function(String permission) can,
  required bool Function(String? feature) featureOn,
}) {
  final order = [
    for (final r in roles)
      if (roleProfiles.containsKey(r)) ...roleProfiles[r]!,
  ];
  final seen = <String>{};
  final ids = [...order, ..._fallbackOrder].where(seen.add);
  return [
    for (final id in ids)
      if (destinations[id] case final d? when (d.permission == null || can(d.permission!)) && featureOn(d.feature)) d,
  ];
}

const maxBarItems = 4;

/// What goes on the bottom bar and what goes under "More".
class NavPlan {
  const NavPlan({required this.bar, required this.more});
  final List<Destination> bar;
  final List<Destination> more;
}

/// A role with a profile (Waiter, Bartender, ...) gets exactly its own screens on the bar, in its own order;
/// anything else the user is permitted to open lives under "More". Roles without a profile (custom roles)
/// get every permitted screen, the first four on the bar.
NavPlan planNavigation({
  required List<String> roles,
  required bool Function(String permission) can,
  required bool Function(String? feature) featureOn,
}) {
  final all = destinationsFor(roles: roles, can: can, featureOn: featureOn);
  final profileIds = {
    for (final r in roles)
      if (roleProfiles.containsKey(r)) ...roleProfiles[r]!,
  };
  final primary = all.where((d) => profileIds.contains(d.id)).toList();

  if (primary.isEmpty) {
    return all.length <= maxBarItems + 1 ? NavPlan(bar: all, more: const []) : NavPlan(bar: all.take(maxBarItems).toList(), more: all.skip(maxBarItems).toList());
  }
  final bar = primary.take(maxBarItems).toList();
  return NavPlan(bar: bar, more: all.where((d) => !bar.contains(d)).toList());
}
