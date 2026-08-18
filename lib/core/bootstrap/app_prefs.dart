import 'package:shared_preferences/shared_preferences.dart';

const _kOnboardingComplete = 'onboarding_complete';
const _kProfileSetupComplete = 'profile_setup_complete';
const _kInsightsLastGeneratedAt = 'insights_last_generated_at';
const _kInsightsSyncedTxSinceLastCycle = 'insights_synced_tx_since_last_cycle';
const _kPaymentNotificationAccessPrompted =
    'payment_notification_access_prompted';
const _kPaymentOverlayPrompted = 'payment_overlay_prompted';

/// Persisted first-run flags (onboarding) + insights generation guard state.
class AppPrefs {
  AppPrefs._();

  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  static bool get onboardingComplete =>
      _prefs?.getBool(_kOnboardingComplete) ?? false;

  static Future<void> setOnboardingComplete() async {
    await _prefs?.setBool(_kOnboardingComplete, true);
  }

  static bool get profileSetupComplete =>
      _prefs?.getBool(_kProfileSetupComplete) ?? false;

  static Future<void> setProfileSetupComplete() async {
    await _prefs?.setBool(_kProfileSetupComplete, true);
  }

  static DateTime? get insightsLastGeneratedAt {
    final ms = _prefs?.getInt(_kInsightsLastGeneratedAt);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  static Future<void> setInsightsLastGeneratedAt(DateTime t) async {
    await _prefs?.setInt(_kInsightsLastGeneratedAt, t.millisecondsSinceEpoch);
  }

  static int get insightsSyncedTxSinceLastCycle =>
      _prefs?.getInt(_kInsightsSyncedTxSinceLastCycle) ?? 0;

  static Future<void> setInsightsSyncedTxSinceLastCycle(int n) async {
    await _prefs?.setInt(_kInsightsSyncedTxSinceLastCycle, n);
  }

  /// True after the in-app notification-access rationale has been shown
  /// once this install — Android cannot show a system runtime dialog for
  /// this permission, so we only prompt once then leave it to Settings.
  static bool get paymentNotificationAccessPrompted =>
      _prefs?.getBool(_kPaymentNotificationAccessPrompted) ?? false;

  static Future<void> setPaymentNotificationAccessPrompted() async {
    await _prefs?.setBool(_kPaymentNotificationAccessPrompted, true);
  }

  static bool get paymentOverlayPrompted =>
      _prefs?.getBool(_kPaymentOverlayPrompted) ?? false;

  static Future<void> setPaymentOverlayPrompted() async {
    await _prefs?.setBool(_kPaymentOverlayPrompted, true);
  }

  /// Clears onboarding flag and other local prefs (not cloud data).
  static Future<void> clearLocalCache() async {
    await _prefs?.remove(_kOnboardingComplete);
    await _prefs?.remove(_kProfileSetupComplete);
  }

  /// Test helper: reset stored prefs (widget tests).
  static Future<void> clearForTest() async {
    await _prefs?.clear();
  }
}
