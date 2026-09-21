import 'dart:convert';

import 'package:dineflow_mobile/core/api_client.dart';
import 'package:dineflow_mobile/core/auth_controller.dart';
import 'package:dineflow_mobile/core/branding_controller.dart';
import 'package:dineflow_mobile/core/models.dart';
import 'package:dineflow_mobile/core/nav.dart';
import 'package:dineflow_mobile/core/token_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

List<String> labels(List<String> roles, Set<String> permissions, {Map<String, bool> features = const {}}) =>
    destinationsFor(roles: roles, can: permissions.contains, featureOn: (f) => f == null || features[f] != false).map((d) => d.label).toList();

void main() {
  group('AuthController', () {
    test('login stores tokens securely and exposes permissions', () async {
      Map<String, dynamic>? body;
      final h = Harness((req) async {
        body = jsonDecode(req.body) as Map<String, dynamic>;
        return envelope(authJson(userJson(roles: ['Manager'], permissions: ['Order.View', 'Dashboard.View'])));
      });

      await h.auth.login(' a@b.c ', 'secret');

      expect(body, {'email': 'a@b.c', 'password': 'secret', 'tenantCode': 'ACME'});
      expect(h.auth.status, AuthStatus.signedIn);
      expect(h.auth.can('Order.View'), isTrue);
      expect(h.auth.can('Order.Cancel'), isFalse);
      expect((await h.store.read())!.refresh, 'refresh-1');
    });

    test('a failed login leaves the user signed out', () async {
      final h = Harness((req) async => failure(401, 'INVALID_CREDENTIALS', 'Invalid email or password'));
      await expectLater(h.auth.login('a@b.c', 'bad'), throwsA(isA<ApiException>()));
      expect(h.auth.status, AuthStatus.unknown);
      expect(await h.store.read(), isNull);
    });

    test('restore signs in from a stored token', () async {
      final h = Harness((req) async => envelope(userJson(roles: ['Bartender'])), tokens: const Tokens(access: 'a', refresh: 'r'));
      await h.auth.restore();
      expect(h.auth.status, AuthStatus.signedIn);
      expect(h.auth.user!.firstName, 'Asha');
    });

    test('restore without a token goes straight to signed out', () async {
      final h = Harness((req) async => fail('must not call the API'));
      await h.auth.restore();
      expect(h.auth.status, AuthStatus.signedOut);
    });

    test('logout revokes the refresh token and clears storage', () async {
      String? logoutBody;
      final h = Harness((req) async {
        if (req.url.path.endsWith('/auth/login')) return envelope(authJson(userJson()));
        logoutBody = req.body;
        return envelope(null);
      });
      await h.auth.login('a@b.c', 'x');
      await h.auth.logout();
      expect(jsonDecode(logoutBody!), {'refreshToken': 'refresh-1'});
      expect(h.auth.status, AuthStatus.signedOut);
      expect(await h.store.read(), isNull);
    });

    test('an expired session signs the user out and flags it', () async {
      final h = Harness((req) async {
        if (req.url.path.endsWith('/auth/login')) return envelope(authJson(userJson()));
        return failure(401, 'UNAUTHORIZED', 'expired');
      });
      await h.auth.login('a@b.c', 'x');
      await expectLater(h.api.get('orders'), throwsA(isA<ApiException>()));
      expect(h.auth.status, AuthStatus.signedOut);
      expect(h.auth.sessionExpired, isTrue);
    });
  });

  group('role-based navigation', () {
    const waiterPerms = {'Table.View', 'Order.View', 'Order.Create', 'Order.Update', 'Customer.View', 'Menu.View'};
    const bartenderPerms = {'Bar.View', 'Order.View', 'Order.Create', 'Order.Update', 'Menu.View'};
    const managerPerms = {'Dashboard.View', 'Order.View', 'Order.Create', 'Table.View', 'Inventory.View', 'Customer.View', 'Reservation.View', 'Kitchen.View', 'Bar.View'};

    test('waiter sees tables, orders and customers first', () {
      expect(labels(['Waiter'], waiterPerms).take(3), ['Tables', 'Orders', 'Customers']);
    });

    test('bartender sees bar orders and bar stock first', () {
      expect(labels(['Bartender'], bartenderPerms).take(2), ['Bar orders', 'Bar stock']);
    });

    test('manager starts with the dashboard, then orders and inventory', () {
      expect(labels(['Manager'], managerPerms).take(3), ['Dashboard', 'Orders', 'Inventory']);
    });

    test('nothing the user lacks permission for is ever listed', () {
      final l = labels(['Manager'], {'Order.View'});
      expect(l, ['Orders']);
    });

    test('a disabled module hides its screens', () {
      final l = labels(['Manager'], managerPerms, features: {'barManagement': false, 'inventory': false});
      expect(l, isNot(contains('Bar orders')));
      expect(l, isNot(contains('Bar stock')));
      expect(l, isNot(contains('Inventory')));
      expect(l, contains('Dashboard'));
    });

    test('custom roles fall back to every permitted screen', () {
      expect(labels(['NightAuditor'], {'Order.View', 'Dashboard.View'}), ['Dashboard', 'Orders']);
    });

    test('multiple roles combine, first role has priority', () {
      final l = labels(['Bartender', 'Waiter'], {...bartenderPerms, ...waiterPerms});
      expect(l.first, 'Bar orders');
      expect(l, contains('Tables'));
    });

    test('profile roles get only their own screens on the bar; the rest go under More', () {
      final plan = planNavigation(roles: ['Bartender'], can: {...bartenderPerms, ...waiterPerms}.contains, featureOn: (_) => true);
      expect(plan.bar.map((d) => d.label), ['Bar orders', 'Bar stock', 'Orders']);
      expect(plan.more.map((d) => d.label), containsAll(['Tables', 'New order']));
    });

    test('the bar never holds more than four items', () {
      final plan = planNavigation(roles: ['Manager'], can: managerPerms.contains, featureOn: (_) => true);
      expect(plan.bar.length, 4);
      expect(plan.bar.first.label, 'Dashboard');
      expect(plan.bar.length + plan.more.length, destinationsFor(roles: ['Manager'], can: managerPerms.contains, featureOn: (_) => true).length);
    });

    test('custom roles put up to five screens on the bar and overflow into More', () {
      final few = planNavigation(roles: ['NightAuditor'], can: {'Order.View', 'Dashboard.View'}.contains, featureOn: (_) => true);
      expect(few.bar.map((d) => d.label), ['Dashboard', 'Orders']);
      expect(few.more, isEmpty);
      final many = planNavigation(roles: ['NightAuditor'], can: managerPerms.contains, featureOn: (_) => true);
      expect(many.bar.length, 4);
      expect(many.more, isNotEmpty);
    });
  });

  group('models and branding', () {
    test('parsers tolerate missing and null fields', () {
      final o = Order.fromJson({'id': 'o1', 'lines': [{'id': 'l1', 'quantity': '2', 'lineSubtotal': 10}], 'grandTotal': null});
      expect(o.grandTotal, 0);
      expect(o.lines.single.quantity, 2);
      expect(o.lines.single.lineSubtotal, 10.0);
      expect(o.liveLines, hasLength(1));
    });

    test('cancelled lines are excluded from live lines', () {
      final o = Order.fromJson({'lines': [{'status': 'Cancelled'}, {'status': 'Draft'}]});
      expect(o.liveLines, hasLength(1));
      expect(o.hasDraft, isTrue);
    });

    test('branding colours and money come from the tenant', () {
      final h = Harness((req) async => envelope(brandingJson(symbol: '₹')));
      expect(BrandingController.parseColor('#0055aa', Colors.red), const Color(0xFF0055AA));
      expect(BrandingController.parseColor('nonsense', Colors.red), Colors.red);
      return h.brand.load().then((_) {
        expect(h.brand.displayName, 'Acme Bar & Grill');
        expect(h.brand.money(1234.5), '₹1,234.50');
        expect(h.brand.money(-0.4), '-₹0.40');
        expect(h.brand.isEnabled('barManagement'), isTrue);
      });
    });

    test('a failed branding load keeps the app usable', () async {
      final h = Harness((req) async => failure(500, 'X', 'down'));
      await h.brand.load();
      expect(h.brand.branding, isNull);
      expect(h.brand.money(5), '5.00');
    });
  });
}
