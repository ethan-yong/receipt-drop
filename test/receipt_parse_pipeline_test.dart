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
}
