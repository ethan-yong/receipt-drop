import '../models/ocr_line.dart';
import '../models/receipt_line_zone.dart';

/// How the paid amount was found: an explicit `RM x.xx` match, a bare number
/// on/near a total-keyword line, or not at all.
enum AmountParseSource { rmPrefixed, totalKeywordFallback, none }

/// [AmountParseResult.failureReason] when no amount pattern matched at all.
const noAmountPatternFailure = 'no_amount_pattern';

/// One ranked amount candidate — mirrors [MerchantCandidate]'s multi-candidate
/// shape so the UI can offer "did you mean RM X?" when the top pick is
/// ambiguous/suspicious.
class AmountCandidate {
  const AmountCandidate({
    required this.value,
    required this.score,
    required this.source,
    this.lineIndex,
    this.ocrConfidence,
    this.digitCorrected = false,
    this.corroborated = false,
  });

  final double value;
  final double score;
  final AmountParseSource source;
  final int? lineIndex;

  /// Underlying OCR line/word confidence for the matched span, when available.
  final double? ocrConfidence;
  final bool digitCorrected;

  /// True when item-subtotal cross-check boosted this candidate.
  final bool corroborated;

  Map<String, dynamic> toJson() => {
        'value': value,
        'score': score,
        'source': source.name,
        if (lineIndex != null) 'lineIndex': lineIndex,
        if (ocrConfidence != null) 'ocrConfidence': ocrConfidence,
        'digitCorrected': digitCorrected,
        'corroborated': corroborated,
      };
}

class AmountParseResult {
  const AmountParseResult({
    required this.amount,
    required this.confidence,
    required this.source,
    this.failureReason,
    this.candidates = const [],
    this.suspicious = false,
    this.alternative,
  });

  final double? amount;
  final double confidence;
  final AmountParseSource source;

  /// Machine-readable reason when [source] is [AmountParseSource.none].
  /// A parse *failure* is reported as such — never disguised as a low
  /// confidence score.
  final String? failureReason;

  /// Full ranked candidate list (already computed; exposed for UI alternatives).
  final List<AmountCandidate> candidates;

  /// True when the top pick has low OCR confidence, no cross-check
  /// corroboration, and a meaningfully different runner-up exists.
  final bool suspicious;

  /// Runner-up when [suspicious] (or when top-2 are close); null otherwise.
  final AmountCandidate? alternative;
}

/// Below this, the parser's own scoring says the picked amount is a guess
/// (e.g. only a plain "RM x.xx" match with no "total"/"tunai" context, or worse).
const lowOcrConfidenceThreshold = 0.5;

/// Provisional OCR-confidence floor for suspicious-result classification.
/// Tune via batch evaluation before treating as final.
const suspiciousOcrConfidenceFloor = 0.45;

/// Minimum absolute difference (MYR) between top and runner-up to treat as
/// a "meaningfully different" alternative.
const meaningfulAmountDeltaMyr = 0.50;

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

/// Max OCR-confidence penalty (analogous to [_largestItemMimicryPenalty]).
const _ocrConfidenceMaxPenalty = 0.20;

/// Extra penalty when any digit in the match was digit-corrected.
const _digitCorrectedPenalty = 0.10;

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

({double score, bool corroborated}) _crossCheckAdjust(
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
        (value - itemsSubtotalMyr).abs() <= itemsSubtotalExactToleranceMyr;
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
  return (score: adjusted, corroborated: matchesSubtotal);
}

/// Reconstructs word char spans from a `" ".join(words)` line (server always
/// joins with a single space). Returns null when words don't reconstruct to
/// [lineText] (e.g. after LLM cleanup rewrote the line).
List<({int start, int end, OcrWord word})>? _wordSpans(
  String lineText,
  List<OcrWord>? words,
) {
  if (words == null || words.isEmpty) return null;
  final joined = words.map((w) => w.text).join(' ');
  if (joined != lineText) return null;
  final spans = <({int start, int end, OcrWord word})>[];
  var cursor = 0;
  for (var i = 0; i < words.length; i++) {
    if (i > 0) cursor += 1;
    final start = cursor;
    final end = start + words[i].text.length;
    spans.add((start: start, end: end, word: words[i]));
    cursor = end;
  }
  return spans;
}

/// OCR reliability signal for a regex match span on [lineIndex].
/// Missing confidence data → neutral (zero penalty contribution).
({double penalty, double? ocrConfidence, bool digitCorrected})
    _ocrConfidenceSignal({
  required List<OcrLine>? ocrLines,
  required int lineIndex,
  required int matchStart,
  required int matchEnd,
  required String lineText,
}) {
  if (ocrLines == null ||
      lineIndex < 0 ||
      lineIndex >= ocrLines.length) {
    return (penalty: 0.0, ocrConfidence: null, digitCorrected: false);
  }
  final ocrLine = ocrLines[lineIndex];
  // Index alignment: ocrLines[i].text should match lines[i]. If not, treat
  // confidence as unavailable rather than misattributing.
  if (ocrLine.text.trim() != lineText.trim() && ocrLine.text != lineText) {
    // Still allow line-level confidence when text matches after trim, or
    // fall through to line confidence only.
  }

  final spans = _wordSpans(ocrLine.text, ocrLine.words);
  if (spans != null) {
    final overlapping = [
      for (final s in spans)
        if (s.start < matchEnd && s.end > matchStart) s.word,
    ];
    if (overlapping.isNotEmpty) {
      final minConf = overlapping
          .map((w) => w.confidence)
          .reduce((a, b) => a < b ? a : b);
      final corrected = overlapping.any((w) => w.digitCorrected);
      final penalty = (1.0 - minConf) * _ocrConfidenceMaxPenalty +
          (corrected ? _digitCorrectedPenalty : 0.0);
      return (
        penalty: penalty,
        ocrConfidence: minConf,
        digitCorrected: corrected,
      );
    }
  }

  final lineConf = ocrLine.confidence;
  if (lineConf == null) {
    return (penalty: 0.0, ocrConfidence: null, digitCorrected: false);
  }
  return (
    penalty: (1.0 - lineConf) * _ocrConfidenceMaxPenalty,
    ocrConfidence: lineConf,
    digitCorrected: false,
  );
}


/// Ranked amount candidates — prefer this over [parseRmAmountFromOcr] when
/// the caller can use alternatives / suspicious-result classification.
List<AmountCandidate> parseRmAmountCandidates(
  String raw, {
  double? itemsSubtotalMyr,
  double? largestItemPriceMyr,
  int lineItemCount = 0,
  ReceiptLayoutAnalysis? layout,
  List<OcrLine>? ocrLines,
}) {
  final lines = raw.split(RegExp(r'\r?\n'));
  final candidates = <AmountCandidate>[];

  final bottomThreshold = (lines.length * 0.8).floor();

  void addRmMatch(int i, String line, RegExpMatch m) {
    final value = double.tryParse(m.group(1)!.replaceAll(',', ''));
    if (value == null) return;
    final isNearBottom = i >= bottomThreshold;
    final inFooterZone =
        layout?.isReliable == true && layout!.zoneAt(i) == ReceiptLineZone.footer;
    var score = 1.0;
    if (isNearBottom) score += _bottomPositionBoost;
    if (inFooterZone) score += _footerZoneBoost;
    if (discountOrSummaryHints.hasMatch(line)) score -= 0.45;
    if (totalKeywordHints.hasMatch(line)) score += 0.35;

    final ocr = _ocrConfidenceSignal(
      ocrLines: ocrLines,
      lineIndex: i,
      matchStart: m.start,
      matchEnd: m.end,
      lineText: line,
    );
    score -= ocr.penalty;

    final cross = _crossCheckAdjust(
      score,
      value,
      itemsSubtotalMyr: itemsSubtotalMyr,
      largestItemPriceMyr: largestItemPriceMyr,
      lineItemCount: lineItemCount,
    );
    candidates.add(AmountCandidate(
      value: value,
      score: cross.score,
      source: AmountParseSource.rmPrefixed,
      lineIndex: i,
      ocrConfidence: ocr.ocrConfidence,
      digitCorrected: ocr.digitCorrected,
      corroborated: cross.corroborated,
    ));
  }

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    for (final m in _rmRegex.allMatches(line)) {
      addRmMatch(i, line, m);
    }
  }

  if (candidates.isEmpty) {
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (!totalKeywordHints.hasMatch(line)) continue;
      if (discountOrSummaryHints.hasMatch(line)) continue;
      final isNearBottom = i >= bottomThreshold;
      final inFooterZone =
          layout?.isReliable == true && layout!.zoneAt(i) == ReceiptLineZone.footer;

      void addBare(int lineIdx, String srcLine, Match m) {
        final value = double.tryParse(m.group(1)!.replaceAll(',', ''));
        if (value == null) return;
        final base =
            _fallbackBaseScore + (isNearBottom ? _bottomPositionBoost : 0.0) +
                (inFooterZone ? _footerZoneBoost : 0.0);
        final ocr = _ocrConfidenceSignal(
          ocrLines: ocrLines,
          lineIndex: lineIdx,
          matchStart: m.start,
          matchEnd: m.end,
          lineText: srcLine,
        );
        final cross = _crossCheckAdjust(
          base - ocr.penalty,
          value,
          itemsSubtotalMyr: itemsSubtotalMyr,
          largestItemPriceMyr: largestItemPriceMyr,
          lineItemCount: lineItemCount,
        );
        candidates.add(AmountCandidate(
          value: value,
          score: cross.score,
          source: AmountParseSource.totalKeywordFallback,
          lineIndex: lineIdx,
          ocrConfidence: ocr.ocrConfidence,
          digitCorrected: ocr.digitCorrected,
          corroborated: cross.corroborated,
        ));
      }

      for (final m in _bareDecimalRegex.allMatches(line)) {
        addBare(i, line, m);
      }
      if (!_bareDecimalRegex.hasMatch(line) && i + 1 < lines.length) {
        final next = lines[i + 1];
        if (!discountOrSummaryHints.hasMatch(next)) {
          for (final m in _bareDecimalRegex.allMatches(next)) {
            addBare(i + 1, next, m);
          }
        }
      }
    }
  }

  if (candidates.isEmpty) return const [];

  final valueCounts = <double, int>{};
  for (final c in candidates) {
    valueCounts[c.value] = (valueCounts[c.value] ?? 0) + 1;
  }
  final boosted = [
    for (final c in candidates)
      (valueCounts[c.value] ?? 1) >= 2
          ? AmountCandidate(
              value: c.value,
              score: c.score + _clusterConsensusBoost,
              source: c.source,
              lineIndex: c.lineIndex,
              ocrConfidence: c.ocrConfidence,
              digitCorrected: c.digitCorrected,
              corroborated: c.corroborated,
            )
          : c,
  ];
  boosted.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    return b.value.compareTo(a.value);
  });
  return boosted;
}

/// Picks the paid total from raw receipt OCR text.
///
/// Tier (a): score every `RM x.xx` occurrence by keyword context, position,
/// and semantic cross-check against extracted items. Tier (b), only when no
/// RM token survived OCR: bare decimals on (or immediately after) a
/// total-keyword line. Tier (c): honest `0.0` failure — never the old `0.1`
/// lie. After both tiers, a cluster consensus pass boosts any value that
/// appears as a candidate more than once.
///
/// Prefer [parseRmAmountCandidates] when alternatives are needed; this
/// wrapper preserves the single-winner contract for existing callers.
AmountParseResult parseRmAmountFromOcr(
  String raw, {
  double? itemsSubtotalMyr,
  double? largestItemPriceMyr,
  int lineItemCount = 0,
  ReceiptLayoutAnalysis? layout,
  List<OcrLine>? ocrLines,
}) {
  final candidates = parseRmAmountCandidates(
    raw,
    itemsSubtotalMyr: itemsSubtotalMyr,
    largestItemPriceMyr: largestItemPriceMyr,
    lineItemCount: lineItemCount,
    layout: layout,
    ocrLines: ocrLines,
  );

  if (candidates.isEmpty) {
    return const AmountParseResult(
      amount: null,
      confidence: 0.0,
      source: AmountParseSource.none,
      failureReason: noAmountPatternFailure,
    );
  }

  final best = candidates.first;
  final confidence = (best.score.clamp(0.0, 2.0)) / 2.0;

  AmountCandidate? alternative;
  var suspicious = false;
  if (candidates.length >= 2) {
    final runnerUp = candidates[1];
    final meaningfullyDifferent =
        (best.value - runnerUp.value).abs() >= meaningfulAmountDeltaMyr;
    final ocrLow = best.ocrConfidence != null &&
        best.ocrConfidence! < suspiciousOcrConfidenceFloor;
    if (ocrLow && !best.corroborated && meaningfullyDifferent) {
      suspicious = true;
      alternative = runnerUp;
    } else if (meaningfullyDifferent &&
        (best.score - runnerUp.score).abs() < 0.15) {
      // Close scores with different values — surface alternative without
      // forcing the suspicious/review-queue path.
      alternative = runnerUp;
    }
  }

  return AmountParseResult(
    amount: best.value,
    confidence: confidence,
    source: best.source,
    candidates: candidates,
    suspicious: suspicious,
    alternative: alternative,
  );
}
