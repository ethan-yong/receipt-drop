class AmountParseResult {
  const AmountParseResult({required this.amount, required this.confidence});
  final double? amount;
  final double confidence;
}

/// Below this, the parser's own scoring says the picked amount is a guess
/// (e.g. only a plain "RM x.xx" match with no "total"/"tunai" context, or worse).
const lowOcrConfidenceThreshold = 0.5;

final _rmRegex = RegExp(r'RM\s*([\d,]+\.\d{2})', caseSensitive: false);

/// Lines mentioning change/discount/tax/subtotal wording. Used to discount
/// candidate total-amount lines here, and reused by
/// receipt_line_item_extractor.dart to skip non-item summary rows.
final discountOrSummaryHints = RegExp(
  r'(baki|tunai|change|diskaun|discount|cukai|tax|subtotal)',
  caseSensitive: false,
);

/// Lines that read as the grand total. Boosts confidence when picking the
/// paid amount here, and reused by receipt_line_item_extractor.dart to
/// reject total rows from being treated as items.
final totalKeywordHints = RegExp(r'total|amount\s*due|jumlah', caseSensitive: false);

AmountParseResult parseRmAmountFromOcr(String raw) {
  final lines = raw.split(RegExp(r'\r?\n'));
  final candidates = <({double value, double score, int lineIndex})>[];

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    for (final m in _rmRegex.allMatches(line)) {
      final value = double.tryParse(m.group(1)!.replaceAll(',', ''));
      if (value == null) continue;
      var score = 1.0;
      if (discountOrSummaryHints.hasMatch(line)) score -= 0.45;
      if (totalKeywordHints.hasMatch(line)) {
        score += 0.35;
      }
      candidates.add((value: value, score: score, lineIndex: i));
    }
  }

  if (candidates.isEmpty) {
    return const AmountParseResult(amount: null, confidence: 0.1);
  }

  candidates.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    return b.value.compareTo(a.value);
  });

  final best = candidates.first;
  final confidence = (best.score.clamp(0.0, 2.0)) / 2.0;

  return AmountParseResult(amount: best.value, confidence: confidence);
}
