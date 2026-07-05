import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_drop/domain/logic/category_matcher.dart';
import 'package:receipt_drop/domain/logic/merchant_extractor.dart';

void main() {
  final categories = CategoryConfig.fromJson({
    'version': 'test',
    'default_category': 'Others',
    'rules': [
      {
        'category': 'Food & Drink',
        'any_of': ['mcdonald'],
      },
    ],
  });

  test('prefers a known brand line over an earlier logo/banner line', () {
    final ocr = "*** WELCOME ***\nMCDONALD'S SUNWAY\nTAX INVOICE\nRM 12.90";
    expect(extractMerchant(ocr, categories), "MCDONALD'S SUNWAY");
  });

  test('skips boilerplate lines when there is no brand match', () {
    final ocr =
        'TAX INVOICE\nGST REG NO: 12345678\n'
        "JOE'S CORNER STORE\nRM 5.00";
    expect(extractMerchant(ocr, categories), "JOE'S CORNER STORE");
  });

  test('falls back to the first line when everything looks like boilerplate', () {
    final ocr = 'TAX INVOICE\nGST NO 12345\n12345\n67890';
    expect(extractMerchant(ocr, categories), 'TAX INVOICE');
  });

  test('returns null for empty OCR text', () {
    expect(extractMerchant('', categories), isNull);
  });

  test('returns null for whitespace-only OCR text', () {
    expect(extractMerchant('   \n  \n', categories), isNull);
  });
}
