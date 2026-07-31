import 'dart:async';

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform, debugPrint;
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
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
  await _initNativeGoogleSignIn();

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

/// Initializes native (in-app) Google Sign-In on Android so the account
/// picker is available the moment the auth screen's Google button is
/// tapped — iOS/web/desktop keep the existing browser-OAuth flow and don't
/// need this (see `_useNativeGoogle` in `auth_screen.dart`). Failures are
/// logged, not fatal: the button surfaces a real error if native sign-in is
/// actually attempted while unconfigured.
Future<void> _initNativeGoogleSignIn() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  try {
    await GoogleSignIn.instance.initialize(
      serverClientId: Env.googleWebClientId,
    );
  } catch (e) {
    debugPrint('GoogleSignIn.initialize failed: $e');
  }
}
