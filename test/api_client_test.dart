import 'dart:convert';

import 'package:dineflow_mobile/core/api_client.dart';
import 'package:dineflow_mobile/core/token_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support.dart';

void main() {
  group('ApiClient', () {
    test('unwraps the data envelope and sends the bearer token', () async {
      String? auth;
      final h = Harness((req) async {
        auth = req.headers['Authorization'];
        return envelope({'hello': 'world'});
      }, tokens: const Tokens(access: 'tok', refresh: 'ref'));

      final data = await h.api.get('things');
      expect(data, {'hello': 'world'});
      expect(auth, 'Bearer tok');
    });

    test('builds query strings and drops empty values', () async {
      Uri? seen;
      final h = Harness((req) async {
        seen = req.url;
        return envelope([]);
      });
      await h.api.get('orders', query: {'page': 2, 'status': null, 'search': '', 'x': 'a b'});
      expect(seen!.path, '/api/v1/orders');
      expect(seen!.queryParameters, {'page': '2', 'x': 'a b'});
    });

    test('surfaces the server error message and code', () async {
      final h = Harness((req) async => failure(422, 'INSUFFICIENT_STOCK', 'Not enough stock'));
      await expectLater(
        h.api.post('orders/1/send'),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Not enough stock').having((e) => e.code, 'code', 'INSUFFICIENT_STOCK').having((e) => e.status, 'status', 422)),
      );
    });

    test('falls back to a friendly message for non-JSON failures', () async {
      final h = Harness((req) async => http.Response('<html>boom</html>', 502));
      await expectLater(h.api.get('x'), throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('server had a problem'))));
    });

    test('maps network failures to an actionable message', () async {
      final h = Harness((req) async => throw http.ClientException('connection refused'));
      await expectLater(h.api.get('x'), throwsA(isA<ApiException>().having((e) => e.code, 'code', 'NETWORK')));
    });

    test('refreshes an expired token once and retries the request', () async {
      var calls = 0;
      final h = Harness((req) async {
        if (req.url.path.endsWith('/auth/refresh')) {
          expect(jsonDecode(req.body), {'refreshToken': 'ref-old'});
          return envelope({'accessToken': 'new-access', 'refreshToken': 'new-refresh'});
        }
        calls++;
        return req.headers['Authorization'] == 'Bearer new-access' ? envelope('ok') : failure(401, 'UNAUTHORIZED', 'expired');
      }, tokens: const Tokens(access: 'old-access', refresh: 'ref-old'));

      expect(await h.api.get('secure'), 'ok');
      expect(calls, 2);
      final t = await h.store.read();
      expect(t!.access, 'new-access');
      expect(t.refresh, 'new-refresh');
    });

    test('concurrent 401s share a single refresh call', () async {
      var refreshes = 0;
      final h = Harness((req) async {
        if (req.url.path.endsWith('/auth/refresh')) {
          refreshes++;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return envelope({'accessToken': 'fresh', 'refreshToken': 'fresh-r'});
        }
        return req.headers['Authorization'] == 'Bearer fresh' ? envelope('ok') : failure(401, 'UNAUTHORIZED', 'expired');
      }, tokens: const Tokens(access: 'stale', refresh: 'r'));

      final results = await Future.wait([h.api.get('a'), h.api.get('b'), h.api.get('c')]);
      expect(results, ['ok', 'ok', 'ok']);
      expect(refreshes, 1);
    });

    test('a failed refresh clears tokens and reports the session as expired', () async {
      var expired = 0;
      final h = Harness((req) async => failure(401, 'UNAUTHORIZED', 'nope'), tokens: const Tokens(access: 'a', refresh: 'r'));
      h.api.onSessionExpired = () => expired++;

      await expectLater(h.api.get('secure'), throwsA(isA<ApiException>().having((e) => e.isUnauthorized, 'isUnauthorized', true)));
      expect(expired, 1);
      expect(await h.store.read(), isNull);
    });

    test('anonymous calls never send or refresh a token', () async {
      String? auth;
      final h = Harness((req) async {
        auth = req.headers['Authorization'];
        return failure(401, 'INVALID_CREDENTIALS', 'Invalid email or password');
      }, tokens: const Tokens(access: 'a', refresh: 'r'));

      await expectLater(h.api.postAnonymous('auth/login', {'email': 'x', 'password': 'y'}), throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Invalid email or password')));
      expect(auth, isNull);
      expect((await h.store.read())!.access, 'a');
    });
  });
}
