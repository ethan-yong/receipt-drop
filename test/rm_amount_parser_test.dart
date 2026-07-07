import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_drop/domain/logic/rm_amount_parser.dart';

void main() {
  test('picks total paid over change line', () {
    const ocr = '''
7-ELEVEN MALAYSIA
Total RM 12.50
Tunai RM 20.00
Baki RM 7.50
''';
    final r = parseRmAmountFromOcr(ocr);
    expect(r.amount, 12.50);
    expect(r.confidence, greaterThan(0.5));
    expect(r.source, AmountParseSource.rmPrefixed);
    expect(r.failureReason, isNull);
  });

  test('reports a parse failure as failure, not as a confidence score', () {
    const ocr = 'NO MONEY HERE';
    final r = parseRmAmountFromOcr(ocr);
    expect(r.amount, isNull);
    expect(r.confidence, 0.0);
    expect(r.source, AmountParseSource.none);
    expect(r.failureReason, noAmountPatternFailure);
  });

  test('falls back to bare number on a TOTAL line when RM is missing', () {
    const ocr = '''
RESTORAN MAMAK
Teh Tarik 2.50
TOTAL 25.90
''';
    final r = parseRmAmountFromOcr(ocr);
    expect(r.amount, 25.90);
    expect(r.source, AmountParseSource.totalKeywordFallback);
    // Fallback amounts are deliberately capped below the low-confidence
    // threshold so they always surface for double-checking.
    expect(r.confidence, lessThan(lowOcrConfidenceThreshold));
  });

  test('fallback reads the value from the line after the JUMLAH label', () {
    const ocr = '''
KEDAI KOPI
JUMLAH
64.80
''';
    final r = parseRmAmountFromOcr(ocr);
    expect(r.amount, 64.80);
    expect(r.source, AmountParseSource.totalKeywordFallback);
  });

  test('fallback skips discount/summary lines', () {
    const ocr = '''
KEDAI RUNCIT
SUBTOTAL 10.00
TOTAL 12.00
''';
    final r = parseRmAmountFromOcr(ocr);
    // SUBTOTAL matches both total and discount hints and must be skipped.
    expect(r.amount, 12.00);
  });

  test('subtotal agreement boosts a candidate over a larger stray value', () {
    const ocr = '''
MAMAK CORNER
RM 15.50
RM 64.80
''';
    final r = parseRmAmountFromOcr(ocr, itemsSubtotalMyr: 15.50);
    // Without the cross-check the tie broke toward the larger 64.80.
    expect(r.amount, 15.50);
  });

  test('exact items consensus lifts a penalized cash-line total', () {
    // rock_cafe regression: the TOTAL line was OCR-mangled, so the amount can
    // only come off the CASH line (-0.45 penalty). With many extracted items
    // summing exactly to the candidate, the consensus boost must carry the
    // confidence past the review threshold anyway.
    const ocr = 'CASH : RM 64.80';
    final many = parseRmAmountFromOcr(
      ocr,
      itemsSubtotalMyr: 64.80,
      lineItemCount: 9,
    );
    expect(many.amount, 64.80);
    expect(many.confidence, closeTo(0.625, 0.001));

    // Two items agreeing is a weaker coincidence — no extra consensus boost.
    final few = parseRmAmountFromOcr(
      ocr,
      itemsSubtotalMyr: 64.80,
      lineItemCount: 2,
    );
    expect(few.amount, 64.80);
    expect(few.confidence, closeTo(0.525, 0.001));
  });

  test('candidate equal to the largest single item is penalized', () {
    const ocr = '''
CAFE
Latte RM 12.50
RM 20.40
''';
    final r = parseRmAmountFromOcr(
      ocr,
      itemsSubtotalMyr: 20.40,
      largestItemPriceMyr: 12.50,
      lineItemCount: 2,
    );
    // 20.40 agrees with the items sum (+boost); 12.50 merely mirrors the
    // biggest item row (-penalty).
    expect(r.amount, 20.40);
    expect(r.confidence, greaterThan(0.5));
  });

  test('BAYARAN keyword boosts amount confidence like TOTAL', () {
    // BAYARAN is a Malaysian payment keyword that should now trigger the
    // +0.35 totalKeywordHints boost, raising confidence above the 0.5 threshold.
    const ocr = '''
KEDAI MAKAN
Nasi Lemak RM 7.50
BAYARAN RM 25.00
''';
    final r = parseRmAmountFromOcr(ocr);
    expect(r.amount, 25.00);
    expect(r.source, AmountParseSource.rmPrefixed);
    expect(r.confidence, greaterThan(0.5));
  });

  test('bottom-position breaks tie between equal-scored candidates', () {
    // Without position signal, 25.00 would win (larger value breaks score ties).
    // With position signal, 15.00 near the bottom gets +0.15 and wins.
    const ocr = '''
RESTAURANT ABC
RM 25.00
Filler line
Filler line
Filler line
RM 15.00
''';
    final r = parseRmAmountFromOcr(ocr);
    expect(r.amount, 15.00);
  });

  test('cluster consensus promotes a repeated value over a higher single value', () {
    // RM 20.40 appears twice, RM 64.80 once. Without cluster consensus, 64.80
    // wins on position (it's near the bottom). With consensus, 20.40 gets +0.20
    // twice and wins.
    const ocr = '''
MAMAK CORNER
Roti RM 5.00
RM 20.40
RM 20.40
RM 64.80
''';
    final r = parseRmAmountFromOcr(ocr);
    expect(r.amount, 20.40);
  });

  test('SST gap candidate scores higher than vague-gap candidate', () {
    // Both candidates agree with the subtotal (within 12% allowance), but
    // 106.00 is exactly 6% above 100.00 (SST-valid) while 110.00 is 10% above.
    // The SST candidate should receive the stronger _subtotalAgreementSstBoost.
    const sstOcr = '''
RESTAURANT SST
RM 106.00
''';
    final sstResult = parseRmAmountFromOcr(
      sstOcr,
      itemsSubtotalMyr: 100.00,
    );

    const vagueOcr = '''
RESTAURANT VAGUE
RM 110.00
''';
    final vagueResult = parseRmAmountFromOcr(
      vagueOcr,
      itemsSubtotalMyr: 100.00,
    );

    expect(sstResult.amount, 106.00);
    expect(vagueResult.amount, 110.00);
    expect(sstResult.confidence, greaterThan(vagueResult.confidence));
  });
}
