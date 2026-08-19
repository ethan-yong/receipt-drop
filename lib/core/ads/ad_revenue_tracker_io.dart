// RevenueCat's ad-tracking API (Purchases.adTracker and its data classes) is
// marked @experimental for its whole surface — this file exists specifically
// to wrap that API, so the warning is suppressed file-wide rather than once
// per call site.
// ignore_for_file: experimental_member_use

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// Translates this app's AdMob banner lifecycle events into RevenueCat's
/// (experimental, beta) ad-monetization tracking — see
/// `Purchases.adTracker` in `purchases_flutter`. Kept separate from the ad
/// UI so `AdBannerSlot` never touches RevenueCat types directly.
///
/// Android only, matching [AdsService]/[RevenueCatService]. Every call is
/// best-effort: tracking must never crash or block the ad UI, so failures
/// (including "RevenueCat not configured") are swallowed and logged rather
/// than thrown — same philosophy as `ReceiptNotificationService`.
abstract final class AdRevenueTracker {
  static const _placement = 'receipt_saved_banner';

  static bool get _supported => Platform.isAndroid;

  static Future<void> trackLoaded({
    required String impressionId,
    required String adUnitId,
  }) => _guard(
    () => Purchases.adTracker.trackAdLoaded(
      AdLoadedData(
        mediatorName: AdMediatorName.adMob,
        adFormat: AdFormat.banner,
        placement: _placement,
        adUnitId: adUnitId,
        impressionId: impressionId,
      ),
    ),
  );

  static Future<void> trackDisplayed({
    required String impressionId,
    required String adUnitId,
  }) => _guard(
    () => Purchases.adTracker.trackAdDisplayed(
      AdDisplayedData(
        mediatorName: AdMediatorName.adMob,
        adFormat: AdFormat.banner,
        placement: _placement,
        adUnitId: adUnitId,
        impressionId: impressionId,
      ),
    ),
  );

  static Future<void> trackFailedToLoad({
    required String impressionId,
    required String adUnitId,
    required int errorCode,
  }) => _guard(
    () => Purchases.adTracker.trackAdFailedToLoad(
      AdFailedToLoadData(
        mediatorName: AdMediatorName.adMob,
        adFormat: AdFormat.banner,
        placement: _placement,
        adUnitId: adUnitId,
        mediatorErrorCode: errorCode,
      ),
    ),
  );

  static Future<void> trackRevenue({
    required String impressionId,
    required String adUnitId,
    required double valueMicros,
    required PrecisionType precision,
    required String currencyCode,
  }) => _guard(
    () => Purchases.adTracker.trackAdRevenue(
      AdRevenueData(
        mediatorName: AdMediatorName.adMob,
        adFormat: AdFormat.banner,
        placement: _placement,
        adUnitId: adUnitId,
        impressionId: impressionId,
        revenueMicros: valueMicros.round(),
        currency: currencyCode,
        precision: _toRevenueCatPrecision(precision),
      ),
    ),
  );

  static AdRevenuePrecision _toRevenueCatPrecision(PrecisionType precision) {
    switch (precision) {
      case PrecisionType.precise:
          return AdRevenuePrecision.exact;
      case PrecisionType.estimated:
          return AdRevenuePrecision.estimated;
      case PrecisionType.publisherProvided:
          return AdRevenuePrecision.publisherDefined;
      case PrecisionType.unknown:
          return AdRevenuePrecision.unknown;
    }
  }

  static Future<void> _guard(Future<void> Function() call) async {
    if (!_supported) return;
    try {
      await call();
    } on Object catch (e) {
      debugPrint('AdRevenueTracker: tracking call failed, ignoring. $e');
    }
  }
}
