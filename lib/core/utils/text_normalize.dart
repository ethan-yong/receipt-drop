/// Normalizes text for merchant-identity comparison/keying: lowercase, then
/// collapses every run of punctuation/whitespace into a single space (so
/// separators read as word boundaries rather than being deleted outright).
///
/// Mirrors `normalizeForCompare()` in
/// `supabase/functions/_shared/place_matching.ts` exactly (same bit-for-bit
/// behavior expected) since the category-preference lookup key computed here
/// must match whatever a future correction write normalizes to server-side.
/// If you change one, change the other — same Dart/TS logic-parity risk
/// already flagged for `geohashEncode` (see `lib/core/utils/place_key.dart`).
String normalizeForCompare(String s) {
  return s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
}
