import 'package:flutter/material.dart';

import 'app.dart';
import 'core/bootstrap/app_prefs.dart';
import 'core/bootstrap/app_services.dart';
import 'core/config/env.dart';
import 'core/routing/app_router.dart';
import 'core/routing/auth_refresh.dart';
import 'data/remote/supabase_client_holder.dart';
import 'widgets/missing_supabase_config_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Env.loadDotEnvIfDebug();
  await AppPrefs.init();
  await AppServices.init();

  if (!Env.hasSupabaseConfig) {
    runApp(const MissingSupabaseConfigApp());
    return;
  }

  await initializeSupabase(
    url: Env.supabaseUrl,
    anonKey: Env.supabaseAnonKey,
  );

  final authRefresh = AuthRefreshNotifier();
  final router = createAppRouter(authRefresh);

  runApp(PuggyBankApp(routerConfig: router));
}
