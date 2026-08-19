/// AdMob ad unit IDs.
///
/// Stage 1: Android test banner only. Replace [androidBannerAdUnitId] with
/// the production unit ID before release — kept isolated here rather than
/// scattered through call sites so that swap is a one-line change.
abstract final class AdsConfig {
  /// Google's public Android test banner unit — see
  /// https://developers.google.com/admob/android/test-ads
  static const androidBannerAdUnitId = 'ca-app-pub-3940256099942544/6300978111';
}
