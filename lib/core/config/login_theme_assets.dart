/// Per-tenant login background images, keyed by tenant code. Add an entry here to white-label a new tenant.
class LoginThemeAssets {
  const LoginThemeAssets({required this.light, required this.dark});

  final String light;
  final String dark;

  static const _defaultTenant = 'DINEFLOW';

  static const Map<String, LoginThemeAssets> _byTenant = {
    _defaultTenant: LoginThemeAssets(
      light: 'assets/images/login/LightModeBG.png',
      dark: 'assets/images/login/DarkModeBG.png',
    ),
  };

  static LoginThemeAssets forTenant(String? tenantCode) {
    final code = (tenantCode == null || tenantCode.isEmpty) ? _defaultTenant : tenantCode.toUpperCase();
    return _byTenant[code] ?? _byTenant[_defaultTenant]!;
  }
}
