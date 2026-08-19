import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../config/env.dart';

/// Configures the RevenueCat SDK so ad events can be tracked against it.
///
/// Android only for now, matching [AdsService] — best-effort and never
/// blocks startup: skips silently (with a debug log) if there's no
/// configured key or we're not on Android, rather than throwing.
abstract final class RevenueCatService {
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized || !Platform.isAndroid) return;
    if (!Env.hasRevenueCatConfig) {
      debugPrint('RevenueCatService: no REVENUECAT_ANDROID_API_KEY, skipping init.');
      return;
    }
    _initialized = true;
    await Purchases.configure(PurchasesConfiguration(Env.revenueCatAndroidApiKey));
  }
}
