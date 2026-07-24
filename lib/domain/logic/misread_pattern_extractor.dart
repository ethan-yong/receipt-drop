/// An abstracted character-substitution pair — "a predicted character of
/// this class was corrected to this confirmed character" — with the actual
/// amount/receipt content discarded before construction. This is the unit
/// synced to the global, anonymized `ocr_misread_patterns` table; see
/// `docs/plans/2026-07-23-feedback-learning-system.md`.
class MisreadPattern {
  const MisreadPattern({required this.fromChar, required this.toChar});

  final String fromChar;
  final String toChar;
}

/// Max number of differing positions for two equal-length amount strings to
/// still count as a "small, localized fix" rather than a wholesale rewrite
/// unrelated to any specific OCR misread. Decision Logic: "never guess at an
/// alignment that isn't confident" — a large mismatch is evidence the whole
/// field was wrong for unrelated reasons, not evidence of a misread pattern.
const misreadAlignmentMaxDiffs = 2;

/// Compares a predicted vs. confirmed amount string (both formatted via
/// [FieldCorrection.formatAmount] — `String field_correction.dart`'s
/// two-decimal fixed format, so both sides align digit-for-digit when the
/// underlying values are close) and emits the differing-character pairs
/// only when they align as a small, localized fix.
///
/// Returns an empty list for anything that isn't a confident alignment:
/// different lengths, more than [misreadAlignmentMaxDiffs] differing
/// positions, a decimal-point shift, or no difference at all. This
/// abstraction is the actual privacy guarantee for the misread-pattern
/// surface — the amount values themselves never appear in the returned
/// patterns, only the character classes involved.
List<MisreadPattern> extractMisreadPatterns(
  String predicted,
  String confirmed,
) {
  if (predicted.length != confirmed.length) return const [];

  final diffs = <MisreadPattern>[];
  for (var i = 0; i < predicted.length; i++) {
    final from = predicted[i];
    final to = confirmed[i];
    if (from == to) continue;
    // A decimal-point shift means the two strings aren't really aligned at
    // all (e.g. a misplaced total), not a digit-level OCR misread.
    if (from == '.' || to == '.') return const [];
    diffs.add(MisreadPattern(fromChar: from, toChar: to));
    if (diffs.length > misreadAlignmentMaxDiffs) return const [];
  }
  return diffs;
}
