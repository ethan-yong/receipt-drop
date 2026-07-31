/// Curated allow-list mapping a sharing app's package/bundle id to a display
/// name for the post-share notification ("Maybank receipt is processing").
/// Deliberately an allow-list, not a guess: an unmapped package (or no
/// referrer at all, which is the only case on iOS — see
/// `share_referrer_reader.dart`) leaves the source unidentified rather than
/// showing a raw, unverified package string. See
/// `docs/plans/2026-07-30-post-share-receipt-notification.md`.
abstract final class ReceiptSourceProviders {
  /// Android package name -> display name. Verified against the current
  /// Google Play listings as of 2026-07-30 (Maybank2u MY was discontinued
  /// mid-2024; MAE by Maybank2u is the current Maybank app for Malaysia).
  static const Map<String, String> _androidPackageToDisplayName = {
    'com.maybank2u.life': 'Maybank',
    'my.com.tngdigital.ewallet': 'Touch \'n Go',
  };

  /// Returns the curated display name for [androidPackage], or `null` when
  /// it isn't a recognized provider — callers must treat `null` as "unknown",
  /// never fall back to showing the raw package name.
  static String? displayNameForAndroidPackage(String? androidPackage) {
    if (androidPackage == null) return null;
    return _androidPackageToDisplayName[androidPackage];
  }
}
