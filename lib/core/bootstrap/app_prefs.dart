import 'package:shared_preferences/shared_preferences.dart';

const _kOnboardingComplete = 'onboarding_complete';
const _kShareCoachMarkSeen = 'share_coach_mark_seen';
const _kShareCoachMarkPending = 'share_coach_mark_pending';

/// Persisted first-run flags (onboarding).
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

  static bool get shareCoachMarkSeen =>
      _prefs?.getBool(_kShareCoachMarkSeen) ?? false;

  static bool get shareCoachMarkPending =>
      _prefs?.getBool(_kShareCoachMarkPending) ?? false;

  static Future<void> setShareCoachMarkPending() async {
    if (shareCoachMarkSeen) return;
    await _prefs?.setBool(_kShareCoachMarkPending, true);
  }

  static Future<void> setShareCoachMarkSeen() async {
    await _prefs?.setBool(_kShareCoachMarkSeen, true);
    await _prefs?.remove(_kShareCoachMarkPending);
  }

  /// Clears onboarding flag and other local prefs (not cloud data).
  static Future<void> clearLocalCache() async {
    await _prefs?.remove(_kOnboardingComplete);
  }

  /// Test helper: reset stored prefs (widget tests).
  static Future<void> clearForTest() async {
    await _prefs?.clear();
  }
}
