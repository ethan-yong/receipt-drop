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
      final v = dotenv.maybeGet('SUPABASE_URL');
      if (v != null && v.isNotEmpty) return v.trim();
    }
    return '';
  }

  static String get supabaseAnonKey {
    const fromDefine = String.fromEnvironment('SUPABASE_ANON_KEY');
    if (fromDefine.isNotEmpty) return fromDefine;
    if (kDebugMode) {
      final v = dotenv.maybeGet('SUPABASE_ANON_KEY');
      if (v != null && v.isNotEmpty) return v.trim();
    }
    return '';
  }

  static bool get hasSupabaseConfig =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
