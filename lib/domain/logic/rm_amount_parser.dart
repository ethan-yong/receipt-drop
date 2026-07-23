import '../models/receipt_line_zone.dart';

/// How the paid amount was found: an explicit `RM x.xx` match, a bare number
/// on/near a total-keyword line, or not at all.
enum AmountParseSource { rmPrefixed, totalKeywordFallback, none }

/// [AmountParseResult.failureReason] when no amount pattern matched at all.
const noAmountPatternFailure = 'no_amount_pattern';

class AmountParseResult {
  const AmountParseResult({
    required this.amount,
    required this.confidence,
    required this.source,
    this.failureReason,
  });

  final double? amount;
  final double confidence;
  final AmountParseSource source;

  /// Machine-readable reason when [source] is [AmountParseSource.none].
  /// A parse *failure* is reported as such — never disguised as a low
  /// confidence score.
  final String? failureReason;
}

/// Below this, the parser's own scoring says the picked amount is a guess
/// (e.g. only a plain "RM x.xx" match with no "total"/"tunai" context, or worse).
const lowOcrConfidenceThreshold = 0.5;

/// Two line items summing to within 5 sen of a candidate counts as agreement.
const itemsSubtotalExactToleranceMyr = 0.05;

/// Items under-shooting the total by up to this fraction reads as SST/service
/// charge rather than a mismatch.
const itemsSubtotalTaxServiceAllowanceFraction = 0.12;

/// Score boost when a candidate's gap from the items sum is an exact match or
/// is within 10% of the Malaysian SST rate (6%) — stronger signal than a vague gap.
const _subtotalAgreementSstBoost = 0.35;

/// Score boost when a candidate agrees with the items sum within the 12%
/// allowance but the gap doesn't resemble the 6% SST rate.
const _subtotalAgreementApproxBoost = 0.30;

/// Additional boost on top of [_subtotalAgreementSstBoost] when the candidate
/// EXACTLY matches the sum of three or more extracted items. Many independent
/// item rows agreeing with a candidate is near-proof it is the paid total —
/// same consensus principle as [_clusterConsensusBoost]. Keeps a mangled
/// TOTAL line (forcing the amount to come off a penalized CASH/TUNAI line)
/// from review-flagging an otherwise perfectly reconciled receipt.
const _subtotalExactConsensusBoost = 0.20;

/// Penalty when a candidate merely equals the single largest item price:
/// likely one item's row misread as the total.
const _largestItemMimicryPenalty = 0.15;

/// Base score for fallback candidates (bare number on a total-keyword line).
/// After the /2 normalization this lands below [lowOcrConfidenceThreshold],
/// so fallback-sourced amounts always surface as low-confidence.
const _fallbackBaseScore = 0.55;

/// Boost applied when a candidate appears in the bottom 20% of the receipt —
/// totals are printed near the end, so position is a weak but free signal.
const _bottomPositionBoost = 0.15;

/// Additional boost when layout zones reliably mark the line as footer.
const _footerZoneBoost = 0.10;

/// Boost applied when the same value appears as an RM candidate two or more
/// times (e.g. on both the TOTAL and BAYARAN lines). Consensus overcomes a
/// higher-scored single stray value.
const _clusterConsensusBoost = 0.20;

final _rmRegex = RegExp(r'RM\s*([\d,]+\.\d{2})', caseSensitive: false);
final _bareDecimalRegex = RegExp(r'([\d,]+\.\d{2})');

/// Lines mentioning change/discount/tax/subtotal wording. Used to discount
/// candidate total-amount lines here, and reused by
/// receipt_line_item_extractor.dart to skip non-item summary rows.
// \bcash\b: word-bounded so item names like "Cashew" don't get filtered.
final discountOrSummaryHints = RegExp(
  r'(baki|tunai|\bcash\b|change|diskaun|discount|cukai|tax|subtotal)',
  caseSensitive: false,
);

/// Lines that read as the grand total. Boosts confidence when picking the
/// paid amount here, and reused by receipt_line_item_extractor.dart to
/// reject total rows from being treated as items.
final totalKeywordHints = RegExp(
  r'total|amount\s*due|jumlah|bayaran|pembayaran|wang\s*diterima|amaun\s*dibayar',
  caseSensitive: false,
);

bool _agreesWithSubtotal(double value, double subtotal) {
  if ((value - subtotal).abs() <= itemsSubtotalExactToleranceMyr) return true;
  return subtotal < value &&
      (value - subtotal) <= value * itemsSubtotalTaxServiceAllowanceFraction;
}

/// True when the gap between [value] and [subtotal] is within 10% of the
/// Malaysian SST rate (6%), indicating a properly tax-inclusive total.
bool _isSstGap(double value, double subtotal) {
  final gap = value - subtotal;
  final expected = subtotal * 0.06;
  return gap > 0 && (gap - expected).abs() <= expected * 0.10;
}

double _crossCheckAdjust(
  double score,
  double value, {
  required double? itemsSubtotalMyr,
  required double? largestItemPriceMyr,
  required int lineItemCount,
}) {
  final matchesSubtotal =
      itemsSubtotalMyr != null && _agreesWithSubtotal(value, itemsSubtotalMyr);
  var adjusted = score;
  if (matchesSubtotal) {
    final exact =
        (value - itemsSubtotalMyr!).abs() <= itemsSubtotalExactToleranceMyr;
    final exactOrSst = exact || _isSstGap(value, itemsSubtotalMyr);
    adjusted +=
        exactOrSst ? _subtotalAgreementSstBoost : _subtotalAgreementApproxBoost;
    if (exact && lineItemCount >= 3) adjusted += _subtotalExactConsensusBoost;
  }
  if (!matchesSubtotal &&
      lineItemCount >= 2 &&
      largestItemPriceMyr != null &&
      (value - largestItemPriceMyr).abs() <= itemsSubtotalExactToleranceMyr) {
    adjusted -= _largestItemMimicryPenalty;
  }
  return adjusted;
}

List<double> _bareDecimalValues(String line) => _bareDecimalRegex
    .allMatches(line)
    .map((m) => double.tryParse(m.group(1)!.replaceAll(',', '')))
    .whereType<double>()
    .toList();

/// Picks the paid total from raw receipt OCR text.
///
/// Tier (a): score every `RM x.xx` occurrence by keyword context, position,
/// and semantic cross-check against extracted items. Tier (b), only when no
/// RM token survived OCR: bare decimals on (or immediately after) a
/// total-keyword line. Tier (c): honest `0.0` failure — never the old `0.1`
/// lie. After both tiers, a cluster consensus pass boosts any value that
/// appears as a candidate more than once.
AmountParseResult parseRmAmountFromOcr(
  String raw, {
  double? itemsSubtotalMyr,
  double? largestItemPriceMyr,
  int lineItemCount = 0,
  ReceiptLayoutAnalysis? layout,
}) {
  final lines = raw.split(RegExp(r'\r?\n'));
  final candidates = <({double value, double score})>[];

  double adjust(double score, double value) => _crossCheckAdjust(
        score,
        value,
        itemsSubtotalMyr: itemsSubtotalMyr,
        largestItemPriceMyr: largestItemPriceMyr,
        lineItemCount: lineItemCount,
      );

  // Pre-compute the position threshold once (floor avoids float indexing).
  final bottomThreshold = (lines.length * 0.8).floor();

  // Tier (a): score every RM-prefixed amount. Position near the bottom is a
  // weak prior (totals print at the end); keyword context is a stronger signal.
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final isNearBottom = i >= bottomThreshold;
    final inFooterZone =
        layout?.isReliable == true && layout!.zoneAt(i) == ReceiptLineZone.footer;
    for (final m in _rmRegex.allMatches(line)) {
      final value = double.tryParse(m.group(1)!.replaceAll(',', ''));
      if (value == null) continue;
      var score = 1.0;
      if (isNearBottom) score += _bottomPositionBoost;
      if (inFooterZone) score += _footerZoneBoost;
      if (discountOrSummaryHints.hasMatch(line)) score -= 0.45;
      if (totalKeywordHints.hasMatch(line)) score += 0.35;
      candidates.add((value: value, score: adjust(score, value)));
    }
  }

  var source = AmountParseSource.rmPrefixed;

  if (candidates.isEmpty) {
    // Tier (b): no RM token survived OCR. Look for bare decimals on/after a
    // total-keyword line — common on Malaysian receipts that omit the RM glyph
    // or where it was garbled.
    source = AmountParseSource.totalKeywordFallback;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (!totalKeywordHints.hasMatch(line)) continue;
      if (discountOrSummaryHints.hasMatch(line)) continue;
      final isNearBottom = i >= bottomThreshold;
      final inFooterZone =
          layout?.isReliable == true && layout!.zoneAt(i) == ReceiptLineZone.footer;
      var values = _bareDecimalValues(line);
      if (values.isEmpty && i + 1 < lines.length) {
        // OCR often splits the "TOTAL" label and its value across lines.
        final next = lines[i + 1];
        if (!discountOrSummaryHints.hasMatch(next)) {
          values = _bareDecimalValues(next);
        }
      }
      final base =
          _fallbackBaseScore + (isNearBottom ? _bottomPositionBoost : 0.0) +
              (inFooterZone ? _footerZoneBoost : 0.0);
      for (final value in values) {
        candidates.add((value: value, score: adjust(base, value)));
      }
    }
  }

  if (candidates.isEmpty) {
    return const AmountParseResult(
      amount: null,
      confidence: 0.0,
      source: AmountParseSource.none,
      failureReason: noAmountPatternFailure,
    );
  }

  // Cluster consensus: a value that appears as a candidate multiple times
  // (e.g. on both the TOTAL and BAYARAN lines) gets a score boost. Uses exact
  // double equality — safe here because both candidates parsed the same OCR
  // string literal with no arithmetic rounding.
  final valueCounts = <double, int>{};
  for (final c in candidates) {
    valueCounts[c.value] = (valueCounts[c.value] ?? 0) + 1;
  }
  final boosted = candidates.map((c) {
    final count = valueCounts[c.value] ?? 1;
    return count >= 2
        ? (value: c.value, score: c.score + _clusterConsensusBoost)
        : c;
  }).toList();
  candidates
    ..clear()
    ..addAll(boosted);

  candidates.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    return b.value.compareTo(a.value);
  });

  final best = candidates.first;
  final confidence = (best.score.clamp(0.0, 2.0)) / 2.0;

  return AmountParseResult(
    amount: best.value,
    confidence: confidence,
    source: source,
  );
}
