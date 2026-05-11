import 'package:flutter_test/flutter_test.dart';
import 'package:puggy_bank/domain/logic/rm_amount_parser.dart';

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
  });

  test('returns null amount when no RM pattern', () {
    const ocr = 'NO MONEY HERE';
    final r = parseRmAmountFromOcr(ocr);
    expect(r.amount, isNull);
    expect(r.confidence, lessThan(0.3));
  });
}
