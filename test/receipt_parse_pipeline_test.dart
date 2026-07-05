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

  test('ocrServiceConfidence 0.95 is squashed before blending', () {
    // Use a receipt with no extractable items so no subtotal cross-check fires
    // (that would raise ocrConfidence to 0.85+ and obscure the calibration
    // signal). With ocrConfidence ≈ 0.675 (TOTAL keyword only):
    //   uncalibrated blend = 0.6×0.675 + 0.4×0.95 ≈ 0.785
    //   calibrated blend   = 0.6×0.675 + 0.4×0.832 ≈ 0.738
    // Assert < 0.76 so code that skips calibration (producing 0.785) trips this.
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
    expect(result.combinedConfidence, lessThan(0.76));
    expect(result.combinedConfidence, greaterThan(0.6));
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
