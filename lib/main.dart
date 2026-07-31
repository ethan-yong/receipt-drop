import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/bootstrap/app_prefs.dart';
import 'core/bootstrap/app_services.dart';
import 'core/config/env.dart';
import 'core/notifications/receipt_notification_service.dart';
import 'core/routing/app_router.dart';
import 'core/routing/auth_refresh.dart';
import 'data/remote/supabase_client_holder.dart';
import 'widgets/missing_supabase_config_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Env.loadDotEnvIfDebug();
  await AppPrefs.init();
  await AppServices.init();
  await ReceiptNotificationService.init();

  if (!Env.hasSupabaseConfig) {
    runApp(const MissingSupabaseConfigApp());
    return;
  }

  await initializeSupabase(
    url: Env.supabaseUrl,
    anonKey: Env.supabaseAnonKey,
  );

  // Local-first means every screen reads from the on-device DB only — a
  // fresh install (or a cleared local cache) has nothing to show even
  // though the account's data is intact in Supabase. Covers both a session
  // restored at launch and an interactive sign-in on the /auth screen.
  Supabase.instance.client.auth.onAuthStateChange.listen((state) {
    final user = state.session?.user;
    debugPrint(
      'onAuthStateChange: event=${state.event} userId=${user?.id}',
    );
    if (user != null) {
      unawaited(AppServices.transactions.hydrateFromCloudIfEmpty(user.id));
    }
  });

  final authRefresh = AuthRefreshNotifier();
  final router = createAppRouter(authRefresh);

  runApp(ReceiptDropApp(routerConfig: router));
}
