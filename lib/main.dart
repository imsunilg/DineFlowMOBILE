import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/api_client.dart';
import 'core/auth_controller.dart';
import 'core/branding_controller.dart';
import 'core/config.dart';
import 'core/services/signalr_service.dart';
import 'core/token_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = await AppConfig.load();
  final tokens = SecureTokenStore();
  final api = ApiClient(config: config, tokens: tokens);
  final auth = AuthController(api: api, tokens: tokens, config: config);
  final branding = BrandingController(api: api, config: config);
  final signalr = SignalrService(auth: auth, tokens: tokens, config: config);

  runApp(MultiProvider(
    providers: [
      Provider<AppConfig>.value(value: config),
      Provider<ApiClient>.value(value: api),
      ChangeNotifierProvider<AuthController>.value(value: auth),
      ChangeNotifierProvider<BrandingController>.value(value: branding),
      Provider<SignalrService>.value(value: signalr),
    ],
    child: const DineFlowApp(),
  ));

  // Restore the session and brand the app in the background; the router shows a splash until auth is known.
  await Future.wait([branding.load(), auth.restore()]);
  if (auth.user?.tenantCode != null && auth.user!.tenantCode != config.tenantCode) {
    await branding.load(tenantCode: auth.user!.tenantCode);
  }
}
