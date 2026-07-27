import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/env.dart';
import '../../core/utils/text_normalize.dart';
import '../../domain/models/category_preference_hint.dart';

/// Client-side lookup for the per-user category-preference table
/// (`user_category_preferences`). Deliberately best-effort and short-timeout:
/// a lookup failure or slow network must never block or delay a receipt
/// capture — the caller treats `null` exactly like "no preference learned
/// yet" (today's baseline behavior, unaffected).
class CategoryPreferenceRepository {
  CategoryPreferenceRepository._();

  static const _lookupTimeout = Duration(seconds: 3);

  static Future<CategoryPreferenceHint?> lookup(String? merchantName) async {
    if (merchantName == null || !Env.hasSupabaseConfig) return null;
    final normalized = normalizeForCompare(merchantName);
    if (normalized.isEmpty) return null;

    try {
      final client = Supabase.instance.client;
      if (client.auth.currentSession == null) return null;

      final rows = await client
          .rpc(
            'lookup_category_preference',
            params: {'p_merchant_normalized': normalized},
          )
          .timeout(_lookupTimeout);
      if (rows is! List || rows.isEmpty) return null;
      final row = rows.first;
      if (row is! Map) return null;
      final category = row['category'];
      final count = row['correction_count'];
      final confidence = row['confidence'];
      if (category is! String || count is! num || confidence is! num) {
        return null;
      }
      return CategoryPreferenceHint(
        category: category,
        correctionCount: count.toInt(),
        confidence: confidence.toDouble(),
      );
    } catch (_) {
      // Never block capture on a failed/slow lookup.
      return null;
    }
  }
}
