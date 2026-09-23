import 'dart:convert';

import 'package:dineflow_mobile/core/api_client.dart';
import 'package:dineflow_mobile/core/auth_controller.dart';
import 'package:dineflow_mobile/core/branding_controller.dart';
import 'package:dineflow_mobile/core/config.dart';
import 'package:dineflow_mobile/core/services/signalr_service.dart';
import 'package:dineflow_mobile/core/token_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response envelope(Object? data, {int status = 200, String message = 'OK'}) =>
    http.Response(jsonEncode({'success': status < 300, 'message': message, 'data': data, 'errors': <Object>[]}), status, headers: {'content-type': 'application/json'});

http.Response failure(int status, String code, String message) =>
    http.Response(jsonEncode({'success': false, 'message': message, 'data': null, 'errors': [{'code': code, 'message': message}]}), status, headers: {'content-type': 'application/json'});

Map<String, dynamic> userJson({List<String> roles = const ['Waiter'], List<String> permissions = const [], String tenant = 'ACME'}) => {
      'id': 'u1',
      'email': 'a@b.c',
      'fullName': 'Asha Rao',
      'tenantId': 't1',
      'tenantCode': tenant,
      'roles': roles,
      'permissions': permissions,
    };

Map<String, dynamic> authJson(Map<String, dynamic> user, {String access = 'access-1', String refresh = 'refresh-1'}) => {
      'accessToken': access,
      'accessTokenExpiresAt': '2099-01-01T00:00:00Z',
      'refreshToken': refresh,
      'user': user,
    };

Map<String, dynamic> brandingJson({String name = 'Acme Bar & Grill', String symbol = '€', Map<String, bool> features = const {}}) => {
      'tenantCode': 'ACME',
      'applicationName': name,
      'displayName': name,
      'primaryColor': '#0055aa',
      'secondaryColor': '#111827',
      'accentColor': '#f59e0b',
      'currency': 'EUR',
      'currencySymbol': symbol,
      'features': features,
      'platformName': 'DineFlow',
    };

class Harness {
  Harness(MockClientHandler handler, {Tokens? tokens}) {
    store = MemoryTokenStore();
    if (tokens != null) store.write(tokens);
    config = AppConfig(baseUrl: 'http://test.local/api/v1', tenantCode: 'ACME');
    client = MockClient(handler);
    api = ApiClient(config: config, tokens: store, client: client);
    auth = AuthController(api: api, tokens: store, config: config);
    brand = BrandingController(api: api, config: config);
  }

  late final MemoryTokenStore store;
  late final AppConfig config;
  late final MockClient client;
  late final ApiClient api;
  late final AuthController auth;
  late final BrandingController brand;

  // Lazy: constructing it registers a WidgetsBinding observer, which needs a binding that only widget tests have.
  // Never actually connects in tests (no real server); screens just read it from the widget tree via Provider.
  SignalrService? _signalr;
  SignalrService get signalr => _signalr ??= SignalrService(auth: auth, tokens: store, config: config);
}
