import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'api_client.dart';
import 'config.dart';
import 'models.dart';

/// Single source of truth for tenant identity in the app: name, colours, currency and enabled modules.
/// Nothing else hard-codes a business name, currency or colour.
class BrandingController extends ChangeNotifier {
  BrandingController({required this.api, required this.config});

  final ApiClient api;
  final AppConfig config;
  Branding? _branding;

  Branding? get branding => _branding;
  String get displayName => _branding?.displayName.isNotEmpty == true ? _branding!.displayName : (_branding?.platformName ?? '');
  String get currencySymbol => _branding?.currencySymbol ?? '';
  bool isEnabled(String? feature) => _branding?.isEnabled(feature) ?? true;

  Future<void> load({String? tenantCode}) async {
    final code = tenantCode ?? config.tenantCode;
    try {
      final data = await api.getAnonymous('config/branding', query: {'tenantCode': code.isEmpty ? null : code});
      _branding = Branding.fromJson(data as Map<String, dynamic>);
      notifyListeners();
    } on ApiException {
      // Keep whatever we had; the app is still usable with the default theme.
    }
  }

  String money(num value) {
    final amount = NumberFormat('#,##0.00').format(value.abs());
    return '${value < 0 ? '-' : ''}$currencySymbol$amount';
  }

  ThemeData theme(Brightness brightness) {
    final seed = parseColor(_branding?.primaryColor, const Color(0xFF7C3AED));
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness, secondary: parseColor(_branding?.accentColor, const Color(0xFFF59E0B)));
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      appBarTheme: AppBarTheme(centerTitle: false, backgroundColor: scheme.surface, surfaceTintColor: scheme.surfaceTint),
      cardTheme: CardThemeData(elevation: 0, color: scheme.surfaceContainerLow, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
      inputDecorationTheme: InputDecorationTheme(border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size(48, 48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
    );
  }

  static Color parseColor(String? hex, Color fallback) {
    if (hex == null) return fallback;
    final h = hex.replaceFirst('#', '');
    if (h.length != 6 && h.length != 8) return fallback;
    final v = int.tryParse(h, radix: 16);
    if (v == null) return fallback;
    return Color(h.length == 6 ? 0xFF000000 | v : v);
  }
}
