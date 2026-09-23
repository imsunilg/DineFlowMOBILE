import 'dart:convert';

import 'package:dineflow_mobile/app.dart';
import 'package:dineflow_mobile/core/api_client.dart';
import 'package:dineflow_mobile/core/auth_controller.dart';
import 'package:dineflow_mobile/core/branding_controller.dart';
import 'package:dineflow_mobile/core/config.dart';
import 'package:dineflow_mobile/core/services/signalr_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'support.dart';

const _waiterPerms = ['Table.View', 'Order.View', 'Order.Create', 'Order.Update', 'Customer.View', 'Menu.View'];
const _bartenderPerms = ['Bar.View', 'Order.View', 'Order.Create', 'Order.Update', 'Menu.View'];

Map<String, dynamic> order({List<Map<String, dynamic>> lines = const [], double total = 0}) => {
      'id': 'o1',
      'orderNo': 'ORD-1',
      'orderType': 'DineIn',
      'tableId': 't1',
      'tableCode': 'T01',
      'status': 'Draft',
      'subtotal': total,
      'grandTotal': total,
      'lines': lines,
    };

/// A tiny in-memory stand-in for the DineFlow API, just enough for the screens under test.
Future<http.Response> fakeApi(http.Request req, {required Map<String, dynamic> user}) async {
  final path = req.url.path.replaceFirst('/api/v1/', '');
  switch ((req.method, path)) {
    case ('GET', 'config/branding'):
      return envelope(brandingJson());
    case ('POST', 'auth/login'):
      return envelope(authJson(user));
    case ('GET', 'auth/me'):
      return envelope(user);
    case ('GET', 'notifications/unread-count'):
      return envelope({'count': 3});
    case ('GET', 'tables/layout'):
      return envelope([
        {'id': 'f1', 'name': 'Ground floor', 'tables': [{'id': 't1', 'floorId': 'f1', 'code': 'T01', 'capacity': 4, 'status': 'Available'}]},
      ]);
    case ('GET', 'tables/summary'):
      return envelope({'total': 1, 'available': 1, 'reserved': 0, 'occupied': 0, 'cleaning': 0, 'blocked': 0});
    case ('GET', 'menu'):
      return envelope([
        {
          'id': 'm1',
          'name': 'Main',
          'categories': [
            {
              'id': 'c1',
              'name': 'Mains',
              'serviceArea': 'Restaurant',
              'items': [
                {'id': 'i1', 'name': 'Butter Chicken', 'basePrice': 380, 'isVeg': false, 'isAvailable': true, 'serviceArea': 'Restaurant', 'variants': [], 'addons': []},
              ],
            },
            {
              'id': 'c2',
              'name': 'Whisky',
              'serviceArea': 'Bar',
              'items': [
                {'id': 'i2', 'name': 'Single Malt', 'basePrice': 250, 'isVeg': true, 'isAvailable': true, 'serviceArea': 'Bar', 'variants': [], 'addons': []},
              ],
            },
          ],
        },
      ]);
    case ('GET', 'orders/by-table/t1'):
      return envelope(null);
    case ('POST', 'orders'):
      return envelope(order(), status: 201);
    case ('POST', 'orders/o1/items'):
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      _lastItemBody = body;
      return envelope(order(total: 380, lines: [
        {'id': 'l1', 'itemName': 'Butter Chicken', 'quantity': 1, 'lineSubtotal': 380, 'status': 'Draft', 'serviceArea': 'Restaurant'},
      ]));
    case ('GET', 'bar/stock'):
      return envelope([
        {'productName': 'Old Monk 750ml', 'categoryName': 'Rum', 'volumeMl': 750, 'quantityMl': 1500, 'wholeBottles': 2, 'looseMl': 0, 'isLow': true},
      ]);
    case ('GET', 'orders'):
      return envelope({'items': [], 'page': 1, 'totalPages': 1, 'totalCount': 0});
    case ('GET', 'customers'):
      return envelope({'items': [], 'page': 1, 'totalPages': 1, 'totalCount': 0});
  }
  return failure(404, 'NOT_FOUND', 'Unhandled ${req.method} $path');
}

Map<String, dynamic>? _lastItemBody;

Future<Harness> startApp(WidgetTester tester, Map<String, dynamic> user) async {
  final h = Harness((req) => fakeApi(req, user: user));
  await h.auth.restore();
  await h.brand.load();
  await tester.pumpWidget(MultiProvider(
    providers: [
      Provider<AppConfig>.value(value: h.config),
      Provider<ApiClient>.value(value: h.api),
      ChangeNotifierProvider<AuthController>.value(value: h.auth),
      ChangeNotifierProvider<BrandingController>.value(value: h.brand),
      Provider<SignalrService>.value(value: h.signalr),
    ],
    child: const DineFlowApp(),
  ));
  await tester.pumpAndSettle();
  return h;
}

Future<void> signIn(WidgetTester tester) async {
  await tester.enterText(find.widgetWithText(TextFormField, 'Email or Login ID'), 'asha@acme.test');
  await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'secret');
  await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sign-in shows the tenant brand, not a hard-coded name', (tester) async {
    await startApp(tester, userJson(permissions: _waiterPerms));
    expect(find.text('Acme Bar & Grill'), findsOneWidget);
    expect(find.text('Sign in to continue'), findsOneWidget);
  });

  testWidgets('sign-in validates before calling the API', (tester) async {
    await startApp(tester, userJson(permissions: _waiterPerms));
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();
    expect(find.text('Enter your email or login ID'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);
  });

  testWidgets('waiter lands on tables with waiter navigation', (tester) async {
    final h = await startApp(tester, userJson(roles: ['Waiter'], permissions: _waiterPerms));
    await signIn(tester);

    expect(h.auth.status, AuthStatus.signedIn);
    expect(find.text('Acme Bar & Grill'), findsWidgets);
    expect(find.text('T01'), findsOneWidget);
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.destinations.map((d) => (d as NavigationDestination).label).toList(), ['Tables', 'Orders', 'Customers', 'New order', 'More']);
    expect(find.text('Dashboard'), findsNothing);
    expect(find.text('Kitchen'), findsNothing);
  });

  testWidgets('bartender lands on the bar with bar navigation', (tester) async {
    await startApp(tester, userJson(roles: ['Bartender'], permissions: _bartenderPerms));
    await signIn(tester);

    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.destinations.map((d) => (d as NavigationDestination).label).toList(), ['Bar orders', 'Bar stock', 'Orders', 'More']);
    expect(find.text('Single Malt'), findsOneWidget);
    expect(find.text('Butter Chicken'), findsNothing);

    await tester.tap(find.text('Bar stock'));
    await tester.pumpAndSettle();
    expect(find.text('Old Monk 750ml'), findsOneWidget);
    expect(find.text('2 btl'), findsOneWidget);
    expect(find.text('Low'), findsWidgets);
  });

  testWidgets('waiter opens a table and adds an item; the API prices it', (tester) async {
    await startApp(tester, userJson(roles: ['Waiter'], permissions: _waiterPerms));
    await signIn(tester);

    await tester.tap(find.text('T01'));
    await tester.pumpAndSettle();
    expect(find.text('Butter Chicken'), findsOneWidget);
    expect(find.text('€380.00'), findsOneWidget);

    await tester.tap(find.text('Butter Chicken'));
    await tester.pumpAndSettle();

    expect(_lastItemBody, containsPair('menuItemId', 'i1'));
    expect(_lastItemBody, containsPair('quantity', 1));
    expect(find.textContaining('1 item · ORD-1'), findsOneWidget);
    expect(find.text('€380.00'), findsWidgets);
  });

  testWidgets('a user without permission for a route is redirected to their home', (tester) async {
    await startApp(tester, userJson(roles: ['Waiter'], permissions: _waiterPerms));
    await signIn(tester);
    final router = GoRouterAccess.of(tester);
    router.go('/kitchen');
    await tester.pumpAndSettle();
    expect(find.text('T01'), findsOneWidget);
  });
}

class GoRouterAccess {
  static dynamic of(WidgetTester tester) => (tester.widget<MaterialApp>(find.byType(MaterialApp)).routerConfig as dynamic);
}
