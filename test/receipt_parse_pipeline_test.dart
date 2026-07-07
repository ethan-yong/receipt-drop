import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_drop/domain/logic/category_matcher.dart';
import 'package:receipt_drop/domain/logic/category_matcher_bundled.dart';
import 'package:receipt_drop/features/share/receipt_parse_pipeline.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CategoryConfig categories;

  setUpAll(() async {
    categories = await loadBundledCategoryConfig();
  });

  test('parseReceiptOcrText extracts total amount and merchant', () {
    const ocrText = '''
ROCK CAFE SDN BHD
123 JALAN EXAMPLE
Tel: 03-12345678

Item A                    RM 12.00
Item B                    RM 30.50

TOTAL                     RM 42.50
Thank you
''';

    final result = parseReceiptOcrText(
      filePath: '/tmp/rock_cafe.png',
      ocrText: ocrText,
      categories: categories,
    );

    expect(result.amountMyr, 42.50);
    expect(result.needsAmount, isFalse);
    expect(result.merchantRaw, contains('ROCK CAFE'));
    expect(result.categoryGuess, isNotEmpty);
    expect(result.impactLevel, 'med');
    expect(result.lowConfidence, isFalse);
  });

  test('parseReceiptOcrText marks needsAmount when no RM total found', () {
    const ocrText = '''
UNKNOWN SHOP
Receipt #12345
No price on this scan
''';

    final result = parseReceiptOcrText(
      filePath: '/tmp/blank.png',
      ocrText: ocrText,
      categories: categories,
    );

    expect(result.amountMyr, isNull);
    expect(result.needsAmount, isTrue);
    expect(result.ocrConfidence, lessThan(0.5));
    expect(result.impactLevel, 'low');
  });

  test('parseReceiptOcrText prefers total line over change line', () {
    const ocrText = '''
7-ELEVEN SUNWAY
Subtotal                  RM 18.00
TUNAI                     RM 20.00
Baki                      RM 2.00
TOTAL                     RM 18.00
''';

    final result = parseReceiptOcrText(
      filePath: '/tmp/7eleven.png',
      ocrText: ocrText,
      categories: categories,
    );

    expect(result.amountMyr, 18.00);
    expect(result.merchantRaw, contains('7-ELEVEN'));
    expect(result.categoryGuess, 'Food & Drink');
  });

  test('mimeFromPath maps common extensions', () {
    expect(mimeFromPath('receipt.png'), 'image/png');
    expect(mimeFromPath('receipt.JPG'), 'image/jpeg');
    expect(mimeFromPath('receipt.jpeg'), 'image/jpeg');
    expect(mimeFromPath('receipt.webp'), 'image/webp');
    expect(mimeFromPath('receipt.pdf'), 'application/pdf');
  });

  test('toJson omits ocrText by default', () {
    final result = parseReceiptOcrText(
      filePath: '/data/local/tmp/receipt-drop-receipts/sample.png',
      ocrText: 'SECRET OCR TEXT\nTOTAL RM 10.00',
      categories: categories,
    );

    final json = result.toJson();
    expect(json['file'], 'sample.png');
    expect(json.containsKey('ocrText'), isFalse);
    expect(json['amountMyr'], 10.0);

    final withOcr = result.toJson(includeOcrText: true);
    expect(withOcr['ocrText'], contains('SECRET OCR TEXT'));
  });

  test('parseReceiptOcrText includes lineItems for an itemized fixture', () {
    const ocrText = '''
ROCK CAFE SDN BHD
Latte                      RM 12.50
Croissant                  RM 7.90
TOTAL                      RM 20.40
''';
    final result = parseReceiptOcrText(
      filePath: '/tmp/rock_cafe_items.png',
      ocrText: ocrText,
      categories: categories,
    );

    expect(result.lineItems.length, greaterThanOrEqualTo(2));
    final json = result.toJson();
    expect(json['lineItems'], isA<List>());
    expect((json['lineItems'] as List).length, greaterThanOrEqualTo(2));
    expect(json['itemsMatchTotal'], isTrue);
  });

  test('parseReceiptOcrText yields empty lineItems when no item rows found',
      () {
    const ocrText = '''
UNKNOWN SHOP
Receipt #12345
No price on this scan
''';
    final result = parseReceiptOcrText(
      filePath: '/tmp/blank2.png',
      ocrText: ocrText,
      categories: categories,
    );

    expect(result.lineItems, isEmpty);
    final json = result.toJson();
    expect(json['lineItems'], isEmpty);
  });

  test('parse failure reports reason and zero confidence in JSON', () {
    final result = parseReceiptOcrText(
      filePath: '/tmp/blank3.png',
      ocrText: 'UNKNOWN SHOP\nNo totals here',
      categories: categories,
    );

    expect(result.needsAmount, isTrue);
    expect(result.ocrConfidence, 0.0);
    expect(result.combinedConfidence, 0.0);
    expect(result.amountSource, 'none');
    expect(result.parseFailureReason, 'no_amount_pattern');

    final json = result.toJson();
    expect(json['parseFailureReason'], 'no_amount_pattern');
    expect(json['amountSource'], 'none');
    expect(json['combinedConfidence'], 0.0);
  });

  test('combinedConfidence is min-gated by scan quality', () {
    const ocrText = '''
ROCK CAFE SDN BHD
Latte                      RM 12.50
Croissant                  RM 7.90
TOTAL                      RM 20.40
''';
    final goodScan = parseReceiptOcrText(
      filePath: '/tmp/scan.png',
      ocrText: ocrText,
      categories: categories,
      ocrServiceConfidence: 0.95,
    );
    final badScan = parseReceiptOcrText(
      filePath: '/tmp/scan.png',
      ocrText: ocrText,
      categories: categories,
      ocrServiceConfidence: 0.2,
    );

    // Same parse, worse scan: the combined score must drop and stay within
    // the ceiling margin of the scan quality.
    expect(goodScan.ocrConfidence, badScan.ocrConfidence);
    expect(badScan.combinedConfidence, lessThan(goodScan.combinedConfidence));
    expect(
      badScan.combinedConfidence,
      lessThanOrEqualTo(0.2 + combinedScanCeilingMargin),
    );
    expect(badScan.lowConfidence, isTrue);
  });

  test('ocrServiceConfidence blends in as-is (already service-calibrated)', () {
    // The OCR service sigmoid-calibrates its mean word confidence before
    // returning it. Re-squashing it here double-calibrated the value
    // (0.34 -> 0.036) and capped combined confidence at ~0.29 forever, so the
    // blend must use the service value untouched.
    const ocrText = '''
CAFE
TOTAL RM 20.00
Thank you for visiting us today.
We appreciate your business.
''';
    final result = parseReceiptOcrText(
      filePath: '/tmp/calibration.png',
      ocrText: ocrText,
      categories: categories,
      ocrServiceConfidence: 0.95,
    );
    final expected = combinedExtractionWeight * result.ocrConfidence +
        combinedScanWeight * 0.95;
    expect(result.combinedConfidence, closeTo(expected, 0.001));
    // The old double calibration produced ~0.74 here; the as-is blend ~0.785.
    expect(result.combinedConfidence, greaterThan(0.76));
  });

  test('mediocre-but-readable scan with a clean parse clears the review bar', () {
    // rock_cafe regression: a handheld photo scores ~0.36 scan confidence but
    // parses perfectly (items subtotal == RM-prefixed total). The old double
    // calibration crushed this to ~0.29 combined, review-flagging every such
    // receipt regardless of parse quality.
    const ocrText = '''
RESTORAN ANWAR MAJU
1 Rsb Biasa 7.00 -Z
3 Teh O Limau Ais 8.70 -Z
1 Ayam Goreng 6.00 -Z
TOTAL : RM 21.70
''';
    final result = parseReceiptOcrText(
      filePath: '/tmp/rock_cafe.jpeg',
      ocrText: ocrText,
      categories: categories,
      ocrServiceConfidence: 0.36,
    );
    expect(result.amountMyr, 21.70);
    expect(result.combinedConfidence, greaterThanOrEqualTo(0.5));
    expect(result.lowConfidence, isFalse);
  });

  test('categoryConfidence is 0.85 when brand keyword is in merchant name', () {
    const ocrText = '''
STARBUCKS KLCC
Latte                      RM 18.00
TOTAL                      RM 18.00
''';
    final result = parseReceiptOcrText(
      filePath: '/tmp/starbucks.png',
      ocrText: ocrText,
      categories: categories,
    );
    expect(result.categoryGuess, 'Food & Drink');
    expect(result.categoryConfidence, 0.85);
  });

  test(
      'categoryConfidence is 0.55 and correct category when brand only in OCR body',
      () {
    // Place the recognisable brand on line 9 so the merchant extractor
    // (which only scans the first 8 non-empty lines for brand matching)
    // falls back to "LOREM IPSUM SDN BHD", while guessWithConfidence's
    // 15-line OCR body scan catches "Petron" on line 9.
    const ocrText = '''
LOREM IPSUM SDN BHD
Company Reg: 123456
Tel: 03-12345678
Receipt No: R001
Date: 2026-07-05
Item 1              RM 30.00
Item 2              RM 50.00
TOTAL               RM 80.00
Petron self-service kiosk
''';
    final result = parseReceiptOcrText(
      filePath: '/tmp/petron.png',
      ocrText: ocrText,
      categories: categories,
    );
    expect(result.categoryGuess, 'Transport');
    expect(result.categoryConfidence, greaterThanOrEqualTo(0.50));
    expect(result.categoryConfidence, lessThan(0.80));
  });

  test('mamak receipt with tax-code suffixes and no RM prefix parses', () {
    // The original failure case: every item is "name  price -Z" and the
    // total line has no readable RM prefix.
    const ocrText = '''
RESTORAN MAMAK BISTRO
Mee Goreng                 7.00 -Z
Nasi Kandar                11.00 -Z
JUMLAH                     18.00
''';
    final result = parseReceiptOcrText(
      filePath: '/tmp/mamak.png',
      ocrText: ocrText,
      categories: categories,
    );

    expect(result.needsAmount, isFalse);
    expect(result.amountMyr, 18.00);
    expect(result.amountSource, 'totalKeywordFallback');
    expect(result.lineItems, hasLength(2));
    expect(result.itemsSubtotalMyr, 18.00);
    expect(result.itemsMatchTotal, isTrue);
    // Fallback-sourced amounts always route to double-checking.
    expect(result.lowConfidence, isTrue);
    expect(result.parseFailureReason, isNull);
  });
}
