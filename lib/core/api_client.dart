import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config.dart';
import 'token_store.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.code = 'ERROR', this.status = 0});
  final String message;
  final String code;
  final int status;

  bool get isUnauthorized => status == 401;

  @override
  String toString() => message;
}

/// Thin REST client over the DineFlow API envelope `{ success, message, data, errors[] }`.
/// Sends the JWT, refreshes it once (single-flight) on a 401 and surfaces server messages as [ApiException].
class ApiClient {
  ApiClient({required this.config, required this.tokens, http.Client? client, this.onSessionExpired}) : _http = client ?? http.Client();

  final AppConfig config;
  final TokenStore tokens;
  final http.Client _http;
  void Function()? onSessionExpired;
  Future<bool>? _refreshing;

  Uri uri(String path, [Map<String, Object?>? query]) {
    final q = <String, String>{};
    query?.forEach((k, v) {
      if (v != null && '$v'.isNotEmpty) q[k] = '$v';
    });
    return Uri.parse('${config.baseUrl}/${path.replaceFirst(RegExp(r'^/'), '')}').replace(queryParameters: q.isEmpty ? null : q);
  }

  Future<dynamic> get(String path, {Map<String, Object?>? query}) => _send('GET', path, query: query);
  Future<dynamic> post(String path, [Object? body]) => _send('POST', path, body: body ?? const {});
  Future<dynamic> put(String path, Object? body) => _send('PUT', path, body: body);
  Future<dynamic> patch(String path, Object? body) => _send('PATCH', path, body: body);
  Future<dynamic> delete(String path) => _send('DELETE', path);

  /// Sign-in and other calls that must not carry (or refresh) a token.
  Future<dynamic> postAnonymous(String path, Object body) => _send('POST', path, body: body, auth: false);
  Future<dynamic> getAnonymous(String path, {Map<String, Object?>? query}) => _send('GET', path, query: query, auth: false);

  Future<dynamic> _send(String method, String path, {Map<String, Object?>? query, Object? body, bool auth = true, bool retried = false}) async {
    final headers = <String, String>{'Accept': 'application/json'};
    if (body != null) headers['Content-Type'] = 'application/json';
    if (auth) {
      final t = await tokens.read();
      if (t != null) headers['Authorization'] = 'Bearer ${t.access}';
    }

    http.Response res;
    try {
      final request = http.Request(method, uri(path, query))..headers.addAll(headers);
      if (body != null) request.body = jsonEncode(body);
      res = await http.Response.fromStream(await _http.send(request).timeout(const Duration(seconds: 30)));
    } on TimeoutException {
      throw ApiException('The server took too long to respond. Check your connection and try again.', code: 'TIMEOUT');
    } on http.ClientException {
      throw ApiException('Cannot reach the server. Check your connection and the server address in Settings.', code: 'NETWORK');
    } on FormatException {
      throw ApiException('The server address looks invalid. Check it in Settings.', code: 'BAD_URL');
    }

    if (res.statusCode == 401 && auth && !retried) {
      if (await _refresh()) return _send(method, path, query: query, body: body, auth: auth, retried: true);
      onSessionExpired?.call();
    }
    return _unwrap(res);
  }

  dynamic _unwrap(http.Response res) {
    Map<String, dynamic>? json;
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is Map<String, dynamic>) json = decoded;
    } catch (_) {}

    if (res.statusCode >= 200 && res.statusCode < 300) return json?['data'];

    final errors = json?['errors'];
    final first = errors is List && errors.isNotEmpty && errors.first is Map ? errors.first as Map : null;
    final message = (first?['message'] ?? json?['message'] ?? _fallback(res.statusCode)).toString();
    throw ApiException(message, code: (first?['code'] ?? 'HTTP_${res.statusCode}').toString(), status: res.statusCode);
  }

  static String _fallback(int status) => switch (status) {
        401 => 'Your session has expired. Please sign in again.',
        403 => 'You do not have permission to do that.',
        404 => 'That item no longer exists.',
        >= 500 => 'The server had a problem. Please try again.',
        _ => 'Something went wrong.',
      };

  Future<bool> _refresh() => _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);

  Future<bool> _doRefresh() async {
    final t = await tokens.read();
    if (t == null) return false;
    try {
      final res = await _http
          .post(uri('auth/refresh'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'refreshToken': t.refresh}))
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        await tokens.clear();
        return false;
      }
      final data = (jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>)['data'] as Map<String, dynamic>;
      await tokens.write(Tokens(access: data['accessToken'] as String, refresh: data['refreshToken'] as String));
      return true;
    } catch (_) {
      return false;
    }
  }
}
