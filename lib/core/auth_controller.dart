import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'config.dart';
import 'models.dart';
import 'token_store.dart';

enum AuthStatus { unknown, signedOut, signedIn }

/// Holds the signed-in user. Permissions and roles come from the server; the app only uses them to decide
/// which screens to show — the API enforces them regardless.
class AuthController extends ChangeNotifier {
  AuthController({required this.api, required this.tokens, required this.config}) {
    api.onSessionExpired = _expired;
  }

  final ApiClient api;
  final TokenStore tokens;
  final AppConfig config;

  AuthStatus _status = AuthStatus.unknown;
  UserProfile? _user;
  bool _sessionExpired = false;

  AuthStatus get status => _status;
  UserProfile? get user => _user;
  bool get sessionExpired => _sessionExpired;

  bool can(String permission) => _user?.permissions.contains(permission) ?? false;
  bool canAny(Iterable<String> permissions) => permissions.any(can);

  Future<void> restore() async {
    if (await tokens.read() == null) return _set(AuthStatus.signedOut, null);
    try {
      final me = await api.get('auth/me');
      _set(AuthStatus.signedIn, UserProfile.fromJson(me as Map<String, dynamic>));
    } on ApiException catch (e) {
      // A network failure keeps the stored session so a flaky connection does not sign the user out.
      if (e.isUnauthorized) {
        await tokens.clear();
        _set(AuthStatus.signedOut, null);
      } else {
        _set(AuthStatus.signedOut, null);
      }
    }
  }

  Future<void> login(String email, String password, {String? tenantCode}) async {
    final data = await api.postAnonymous('auth/login', {
      'email': email.trim(),
      'password': password,
      'tenantCode': (tenantCode ?? config.tenantCode).trim().isEmpty ? null : (tenantCode ?? config.tenantCode).trim(),
    }) as Map<String, dynamic>;
    await tokens.write(Tokens(access: data['accessToken'] as String, refresh: data['refreshToken'] as String));
    _sessionExpired = false;
    _set(AuthStatus.signedIn, UserProfile.fromJson(data['user'] as Map<String, dynamic>));
  }

  Future<void> logout() async {
    final t = await tokens.read();
    if (t != null) {
      try {
        await api.post('auth/logout', {'refreshToken': t.refresh});
      } catch (_) {}
    }
    await tokens.clear();
    _sessionExpired = false;
    _set(AuthStatus.signedOut, null);
  }

  void _expired() {
    if (_status != AuthStatus.signedIn) return;
    _sessionExpired = true;
    _set(AuthStatus.signedOut, null);
  }

  void _set(AuthStatus s, UserProfile? u) {
    _status = s;
    _user = u;
    notifyListeners();
  }
}
