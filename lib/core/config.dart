import 'package:shared_preferences/shared_preferences.dart';

/// Where the API lives and which tenant's branding to show before sign-in.
/// Defaults come from --dart-define so no environment is hard-coded; users can also change them in Settings.
class AppConfig {
  AppConfig({required this.baseUrl, required this.tenantCode});

  /// PC's LAN address for development over Wi-Fi. Change it when the PC's IP changes
  /// (scripts/start-lan.ps1 -BuildApk rewrites it), or override with --dart-define=API_BASE_URL.
  static const apiHost = '192.168.1.6';
  static const apiPort = 5100;

  static const _defaultBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://$apiHost:$apiPort/api/v1');
  static const _defaultTenant = String.fromEnvironment('TENANT_CODE', defaultValue: '');
  static const _urlKey = 'api_base_url';
  static const _tenantKey = 'tenant_code';

  String baseUrl;
  String tenantCode;

  static Future<AppConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppConfig(baseUrl: prefs.getString(_urlKey) ?? _defaultBaseUrl, tenantCode: prefs.getString(_tenantKey) ?? _defaultTenant);
  }

  Future<void> save({required String baseUrl, required String tenantCode}) async {
    this.baseUrl = normalize(baseUrl);
    this.tenantCode = tenantCode.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_urlKey, this.baseUrl);
    await prefs.setString(_tenantKey, this.tenantCode);
  }

  static String normalize(String url) {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }
}
