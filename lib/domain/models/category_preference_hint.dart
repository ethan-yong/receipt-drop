/// A learned per-user `(merchant, category)` preference, read at parse time
/// to bias category prediction for a recurring merchant — see
/// `docs/plans/2026-07-23-feedback-learning-system.md`. Lives in `domain/
/// models/` (rather than alongside its repository) so both the pure parsing
/// pipeline (`receipt_parse_pipeline.dart`) and the Supabase-backed
/// repository can depend on it without either layer reaching into the
/// other.
class CategoryPreferenceHint {
  const CategoryPreferenceHint({
    required this.category,
    required this.correctionCount,
    required this.confidence,
  });

  final String category;

  /// How many consecutive corrections agreed on [category] — the
  /// corroboration gate (Decision Logic: only surface a learned category
  /// once corrected consistently at least twice for this merchant). Also
  /// enforced server-side in `lookup_category_preference`.
  final int correctionCount;

  /// Decayed, corroboration-weighted confidence from
  /// `lookup_category_preference` — `f(correction_count, last_corrected_at)`,
  /// not a fixed constant.
  final double confidence;
}
