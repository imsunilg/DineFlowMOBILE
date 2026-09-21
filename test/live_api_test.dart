// Opt-in contract test against a running DineFlowAPI. Skipped unless LIVE_API_URL is set:
//   LIVE_API_URL=http://localhost:5080/api/v1 LIVE_EMAIL=... LIVE_PASSWORD=... flutter test test/live_api_test.dart
import 'dart:io';

import 'package:dineflow_mobile/core/api_client.dart';
import 'package:dineflow_mobile/core/auth_controller.dart';
import 'package:dineflow_mobile/core/config.dart';
import 'package:dineflow_mobile/core/models.dart';
import 'package:dineflow_mobile/core/token_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final url = Platform.environment['LIVE_API_URL'];
  final email = Platform.environment['LIVE_EMAIL'] ?? '';
  final password = Platform.environment['LIVE_PASSWORD'] ?? '';

  group('live API contract', () {
    late ApiClient api;
    late AuthController auth;

    setUp(() {
      final config = AppConfig(baseUrl: url!, tenantCode: '');
      final store = MemoryTokenStore();
      api = ApiClient(config: config, tokens: store);
      auth = AuthController(api: api, tokens: store, config: config);
    });

    test('sign in, then every screen model parses real responses', () async {
      await auth.login(email, password);
      expect(auth.user!.permissions, isNotEmpty);

      final branding = Branding.fromJson(await api.getAnonymous('config/branding', query: {'tenantCode': auth.user!.tenantCode}) as Map<String, dynamic>);
      expect(branding.displayName, isNotEmpty);
      expect(branding.currencySymbol, isNotEmpty);

      final floors = (await api.get('tables/layout') as List).map((e) => FloorLayout.fromJson(e as Map<String, dynamic>)).toList();
      expect(floors, isNotEmpty);
      expect(floors.expand((f) => f.tables).first.code, isNotEmpty);
      TableSummary.fromJson(await api.get('tables/summary') as Map<String, dynamic>);

      final menu = (await api.get('menu', query: {'onlyAvailable': true}) as List);
      final cats = [for (final m in menu) for (final c in (m['categories'] as List)) MenuCategory.fromJson(c as Map<String, dynamic>)];
      expect(cats.expand((c) => c.items), isNotEmpty);

      Dashboard.fromJson(await api.get('reports/dashboard') as Map<String, dynamic>);
      Paged.from(await api.get('orders', query: {'pageSize': 5}), OrderSummary.fromJson);
      Paged.from(await api.get('customers', query: {'pageSize': 5}), Customer.fromJson);
      Paged.from(await api.get('reservations', query: {'pageSize': 5}), Reservation.fromJson);
      Paged.from(await api.get('notifications', query: {'pageSize': 5}), AppNotification.fromJson);
      Paged.from(await api.get('inventory/stock', query: {'pageSize': 5}), InvStockRow.fromJson);
      (await api.get('inventory/alerts') as List).map((e) => StockAlert.fromJson(e as Map<String, dynamic>)).toList();
      (await api.get('bar/stock') as List).map((e) => BarStockRow.fromJson(e as Map<String, dynamic>)).toList();
      (await api.get('kitchen/tickets') as List).map((e) => KitchenTicket.fromJson(e as Map<String, dynamic>)).toList();
      (await api.get('payments/methods') as List).map((e) => PaymentMethod.fromJson(e as Map<String, dynamic>)).toList();
    });

    test('the full order flow works through the mobile client', () async {
      await auth.login(email, password);
      final floors = (await api.get('tables/layout') as List).map((e) => FloorLayout.fromJson(e as Map<String, dynamic>)).toList();
      final table = floors.expand((f) => f.tables).firstWhere((t) => t.status == 'Available');
      final menu = (await api.get('menu', query: {'onlyAvailable': true}) as List);
      final item = [for (final m in menu) for (final c in (m['categories'] as List)) ...MenuCategory.fromJson(c as Map<String, dynamic>).items].firstWhere((i) => i.variants.isEmpty && i.addons.isEmpty);

      var order = Order.fromJson(await api.post('orders', {'orderType': 'DineIn', 'tableId': table.id, 'customerId': null, 'notes': null}) as Map<String, dynamic>);
      order = Order.fromJson(await api.post('orders/${order.id}/items', {'menuItemId': item.id, 'variantId': null, 'addonIds': <String>[], 'quantity': 2, 'notes': null}) as Map<String, dynamic>);
      expect(order.liveLines.single.quantity, 2);
      expect(order.grandTotal, greaterThan(0));
      expect(order.hasDraft, isTrue);

      order = Order.fromJson(await api.post('orders/${order.id}/send') as Map<String, dynamic>);
      expect(order.hasDraft, isFalse);
      final bill = Bill.fromJson(await api.post('billing/orders/${order.id}/generate') as Map<String, dynamic>);
      expect(bill.grandTotal, order.grandTotal);
      final methods = (await api.get('payments/methods') as List).map((e) => PaymentMethod.fromJson(e as Map<String, dynamic>)).toList();
      final paid = Bill.fromJson(await api.post('payments/bills/${bill.id}', {
        'payments': [{'paymentMethodId': methods.first.id, 'amount': bill.dueAmount, 'reference': null}],
      }) as Map<String, dynamic>);
      expect(paid.status, 'Paid');
      expect(paid.dueAmount, 0);
    });
  }, skip: url == null ? 'set LIVE_API_URL to run' : false);
}
