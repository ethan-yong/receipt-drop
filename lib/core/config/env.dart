import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Supabase and runtime configuration.
///
/// Priority:
/// 1. `--dart-define=SUPABASE_URL` / `SUPABASE_ANON_KEY`
/// 2. In **debug**, values from `.env` after [loadDotEnvIfDebug]
class Env {
  Env._();

  /// Loads `.env` from the project root when [kDebugMode] is true.
  /// Ignores missing file so CI/tests can rely on dart-define only.
  static Future<void> loadDotEnvIfDebug() async {
    if (!kDebugMode) return;
    try {
      await dotenv.load(fileName: '.env');
    } catch (_) {
      // Optional file for local dev.
    }
  }

  static String get supabaseUrl {
    const fromDefine = String.fromEnvironment('SUPABASE_URL');
    if (fromDefine.isNotEmpty) return fromDefine;
    if (kDebugMode) {
      try {
        final v = dotenv.maybeGet('SUPABASE_URL');
        if (v != null && v.isNotEmpty) return v.trim();
      } on Object {
        // dotenv not loaded yet (e.g. widget tests).
      }
    }
    return '';
  }

  static String get supabaseAnonKey {
    const fromDefine = String.fromEnvironment('SUPABASE_ANON_KEY');
    if (fromDefine.isNotEmpty) return fromDefine;
    if (kDebugMode) {
      try {
        final v = dotenv.maybeGet('SUPABASE_ANON_KEY');
        if (v != null && v.isNotEmpty) return v.trim();
      } on Object {
        // dotenv not loaded yet (e.g. widget tests).
      }
    }
    return '';
  }

  static bool get hasSupabaseConfig =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static String get leaderboardApiUrl {
    const fromDefine = String.fromEnvironment('LEADERBOARD_API_URL');
    if (fromDefine.isNotEmpty) return fromDefine;
    if (kDebugMode) {
      final v = dotenv.maybeGet('LEADERBOARD_API_URL');
      if (v != null && v.isNotEmpty) return v.trim();
    }
    return '';
  }

  static bool get hasLeaderboardApiConfig => leaderboardApiUrl.isNotEmpty;

  /// Skip onboarding + auth redirects while building features (debug only by default).
  ///
  /// Enabled when `SKIP_AUTH=true` in `.env` or `--dart-define=SKIP_AUTH=true`,
  /// or by default in [kDebugMode] unless `SKIP_AUTH=false`.
  /// Always off in profile/release unless you pass the dart-define (not recommended).
  static bool get skipAuth {
    const fromDefine = String.fromEnvironment('SKIP_AUTH');
    if (fromDefine == 'true' || fromDefine == '1') return true;
    if (fromDefine == 'false' || fromDefine == '0') return false;
    if (kDebugMode) {
      try {
        final v = dotenv.maybeGet('SKIP_AUTH');
        if (v != null) {
          final lower = v.trim().toLowerCase();
          if (lower == 'true' || lower == '1') return true;
          if (lower == 'false' || lower == '0') return false;
        }
      } on Object {
        // dotenv not loaded yet (e.g. widget tests) — fall through to debug default.
      }
      return true;
    }
    return false;
  }
}
