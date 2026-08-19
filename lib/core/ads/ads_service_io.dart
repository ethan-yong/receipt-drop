import 'dart:io';

import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Initializes the Google Mobile Ads SDK.
///
/// Android only for now (Stage 1) — no iOS ad unit is configured yet, so
/// this is a no-op there and on desktop rather than initializing a plugin
/// with nothing to serve.
abstract final class AdsService {
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized || !Platform.isAndroid) return;
    _initialized = true;
    await MobileAds.instance.initialize();
  }
}
