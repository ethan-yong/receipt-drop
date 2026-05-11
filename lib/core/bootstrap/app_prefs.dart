import 'package:shared_preferences/shared_preferences.dart';

const _kOnboardingComplete = 'onboarding_complete';

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

  /// Test helper: reset stored prefs (widget tests).
  static Future<void> clearForTest() async {
    await _prefs?.clear();
  }
}
