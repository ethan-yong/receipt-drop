import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/ads/ads_service.dart';
import 'core/bootstrap/app_prefs.dart';
import 'core/bootstrap/app_services.dart';
import 'core/config/env.dart';
import 'core/notifications/receipt_notification_service.dart';
import 'core/payment_detection/payment_event_drain_service.dart';
import 'core/routing/app_router.dart';
import 'core/routing/auth_refresh.dart';
import 'data/remote/supabase_client_holder.dart';
import 'data/repositories/profile_repository.dart';
import 'widgets/missing_supabase_config_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Env.loadDotEnvIfDebug();
  await AppPrefs.init();
  await AppServices.init();
  // Drains any payment events captured natively while the Flutter engine
  // wasn't running (see lib/core/payment_detection/). Never blocks startup.
  unawaited(PaymentEventDrainService.drainAndIngest());
  await ReceiptNotificationService.init();
  await AdsService.init();

  if (!Env.hasSupabaseConfig) {
    runApp(const MissingSupabaseConfigApp());
    return;
  }

  await initializeSupabase(url: Env.supabaseUrl, anonKey: Env.supabaseAnonKey);

  final authRefresh = AuthRefreshNotifier();

  // Local-first means every screen reads from the on-device DB only — a
  // fresh install (or a cleared local cache) has nothing to show even
  // though the account's data is intact in Supabase. Covers both a session
  // restored at launch and an interactive sign-in on the /auth screen.
  Supabase.instance.client.auth.onAuthStateChange.listen((state) {
    final user = state.session?.user;
    debugPrint('onAuthStateChange: event=${state.event} userId=${user?.id}');
    if (user != null) {
      unawaited(AppServices.transactions.hydrateFromCloudIfEmpty(user.id));
      // The router's redirect reads AppPrefs synchronously; refresh it once
      // this lands so a reinstall on an already-set-up account skips
      // /profile-setup instead of getting stuck on a stale local flag.
      unawaited(
        ProfileRepository.syncProfileSetupStatus(
          user.id,
        ).then((_) => authRefresh.refresh()),
      );
    }
  });

  final router = createAppRouter(authRefresh);

  runApp(ReceiptDropApp(routerConfig: router));
}
