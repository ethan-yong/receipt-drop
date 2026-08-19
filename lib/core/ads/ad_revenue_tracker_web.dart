/// No ad SDK runs on web (see [AdsService]) — nothing to track. Never
/// actually called (the web `AdBannerSlot` has no ad to report events for),
/// so `precision` is untyped here to avoid importing `google_mobile_ads`
/// (mobile-only) into the web build.
abstract final class AdRevenueTracker {
  static Future<void> trackLoaded({
    required String impressionId,
    required String adUnitId,
  }) async {}

  static Future<void> trackDisplayed({
    required String impressionId,
    required String adUnitId,
  }) async {}

  static Future<void> trackFailedToLoad({
    required String impressionId,
    required String adUnitId,
    required int errorCode,
  }) async {}

  static Future<void> trackRevenue({
    required String impressionId,
    required String adUnitId,
    required double valueMicros,
    required Object precision,
    required String currencyCode,
  }) async {}
}
