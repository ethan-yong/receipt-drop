import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_drop/domain/logic/category_matcher.dart';
import 'package:receipt_drop/domain/logic/category_matcher_bundled.dart';
import 'package:receipt_drop/domain/models/category_preference_hint.dart';
import 'package:receipt_drop/domain/models/ocr_line.dart';
import 'package:receipt_drop/domain/models/receipt_understanding.dart';
import 'package:receipt_drop/features/share/receipt_parse_pipeline.dart';

const _fixtureConfidence = ReceiptUnderstandingConfidence(
  merchant: 0,
  address: 0,
  category: 0,
  lineItems: 0.9,
);

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
      'a brand keyword within the wider 15-line scan is now picked as the '
      'merchant itself, earning full (0.85) category confidence', () {
    // Merchant extraction's scan depth (merchantScanLines) and
    // guessWithConfidence's OCR-body scan depth (scanLines) are both 15, so
    // any category keyword within that window is caught by BOTH — meaning
    // it always becomes the top merchant candidate too, which is strictly
    // better than the old 8-line window (where a brand this deep was missed
    // by merchant extraction and only earned the weaker 0.55 OCR-body-only
    // tier; see test/category_matcher_test.dart for that tier in isolation).
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
    expect(result.merchantRaw, contains('Petron'));
    expect(result.categoryGuess, 'Transport');
    expect(result.categoryConfidence, 0.85);
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

  test('parseReceiptOcrText populates ranked merchantCandidates and ocrHeaderText', () {
    const ocrText = '''
RESTORAN ANWAR MAJU
Tel: 03-12345678
TOTAL RM 21.70
''';
    final result = parseReceiptOcrText(
      filePath: '/tmp/candidates.png',
      ocrText: ocrText,
      categories: categories,
    );

    expect(result.merchantCandidates, isNotEmpty);
    expect(result.merchantCandidates.first.text, result.merchantRaw);
    expect(result.ocrHeaderText, isNotNull);
    expect(result.ocrHeaderText, contains('RESTORAN ANWAR MAJU'));

    final json = result.toJson();
    expect(json['merchantCandidates'], isA<List>());
    expect((json['merchantCandidates'] as List).first, isA<Map>());
    expect(json['ocrHeaderText'], result.ocrHeaderText);
  });

  test('ocrHeaderText is null for empty OCR text', () {
    final result = parseReceiptOcrText(
      filePath: '/tmp/empty.png',
      ocrText: '',
      categories: categories,
    );
    expect(result.merchantCandidates, isEmpty);
    expect(result.ocrHeaderText, isNull);
    expect(result.toJson().containsKey('ocrHeaderText'), isFalse);
  });

  test('ocrLines threads through to merchantCandidates/merchantRaw '
      '(large-text signal end-to-end)', () {
    const ocrText = 'Welcome valued customer to our humble shop today\n'
        'QUIRKENDALE\n'
        'Item A RM 5.00\n'
        'TOTAL RM 5.00';
    final ocrLines = [
      const OcrLine(
        text: 'Welcome valued customer to our humble shop today',
        heightRatio: 0.03,
      ),
      const OcrLine(text: 'QUIRKENDALE', heightRatio: 0.12),
      const OcrLine(text: 'Item A RM 5.00', heightRatio: 0.025),
      const OcrLine(text: 'TOTAL RM 5.00', heightRatio: 0.025),
    ];

    final withoutHeights = parseReceiptOcrText(
      filePath: '/tmp/large_text.png',
      ocrText: ocrText,
      categories: categories,
    );
    expect(withoutHeights.merchantRaw, isNot('QUIRKENDALE'));

    final withHeights = parseReceiptOcrText(
      filePath: '/tmp/large_text.png',
      ocrText: ocrText,
      categories: categories,
      ocrLines: ocrLines,
    );
    expect(withHeights.merchantRaw, 'QUIRKENDALE');
    expect(withHeights.merchantCandidates.first.source, 'largeText');
  });

  group('LLM understanding line items', () {
    // Real regression fixture: RESTORAN ANWAR MAJU receipt where the LLM
    // read "1 Limau Ais Bungkus 3.00 -Z" as RM 93.00 — a digit-transcription
    // hallucination no prompt wording alone can fully prevent.
    const ocrText = '''
RESTORAN ANWAR MAJU
1 Rsb Biasa 7.00 -Z
3 Teh O Limau Ais 8.70 -Z
1 Limau Ais Bungkus 3.00 -Z
TOTAL : RM 18.70
''';

    test('drops an LLM item priced above the receipt total', () {
      final understanding = ReceiptUnderstanding(
        merchantName: 'Restoran Anwar Maju',
        merchantSearchQueries: const ['Restoran Anwar Maju'],
        addressText: null,
        locationClues: const [],
        vendorCategory: 'food_and_drink',
        googlePlaceTypes: const ['restaurant'],
        lineItems: const [
          ReceiptUnderstandingLineItem(
            name: 'Rsb Biasa',
            price: 7.00,
            quantity: 1,
          ),
          ReceiptUnderstandingLineItem(
            name: 'Teh O Limau Ais',
            price: 8.70,
            quantity: 3,
          ),
          // Hallucinated: printed price is RM 3.00, not RM 93.00.
          ReceiptUnderstandingLineItem(
            name: 'Limau Ais Bungkus',
            price: 93.00,
            quantity: 1,
          ),
        ],
        confidence: _fixtureConfidence,
      );

      final result = parseReceiptOcrText(
        filePath: '/tmp/anwar_maju.png',
        ocrText: ocrText,
        categories: categories,
        understanding: understanding,
      );

      expect(
        result.lineItems.map((it) => it.name),
        ['Rsb Biasa', 'Teh O Limau Ais'],
      );
      expect(
        result.lineItems.any((it) => it.name == 'Limau Ais Bungkus'),
        isFalse,
      );
    });

    test('surfaces a leading-column quantity the LLM read correctly', () {
      final understanding = ReceiptUnderstanding(
        merchantName: 'Restoran Anwar Maju',
        merchantSearchQueries: const ['Restoran Anwar Maju'],
        addressText: null,
        locationClues: const [],
        vendorCategory: 'food_and_drink',
        googlePlaceTypes: const ['restaurant'],
        lineItems: const [
          ReceiptUnderstandingLineItem(
            name: 'Teh O Limau Ais',
            price: 8.70,
            quantity: 3,
          ),
        ],
        confidence: _fixtureConfidence,
      );

      final result = parseReceiptOcrText(
        filePath: '/tmp/anwar_maju2.png',
        ocrText: ocrText,
        categories: categories,
        understanding: understanding,
      );

      final tehO =
          result.lineItems.firstWhere((it) => it.name == 'Teh O Limau Ais');
      expect(tehO.quantity, 3);
    });
  });

  group('OCR cleanup: prefers cleaned text/lines when present', () {
    // Deliberately garbled beyond what the amount regex (\d+\.\d{2}) can
    // match at all — proves the heuristic pass actually switched its input,
    // not just tolerated noise it already handled.
    const garbledOcrText = '''
RESTQRAN ANWAR MAJU
T0TAL RM 4Z.5O
''';
    const cleanedOcrText = '''
RESTORAN ANWAR MAJU
TOTAL RM 42.50
''';

    test('uses cleanedOcrText for amount extraction when raw text is'
        ' unparseable', () {
      final understanding = ReceiptUnderstanding(
        merchantName: null,
        merchantSearchQueries: const [],
        addressText: null,
        locationClues: const [],
        vendorCategory: null,
        googlePlaceTypes: const [],
        lineItems: const [],
        confidence: _fixtureConfidence,
        cleanedLines: cleanedOcrText.trim().split('\n'),
        cleanedOcrText: cleanedOcrText,
      );

      final withoutCleanup = parseReceiptOcrText(
        filePath: '/tmp/garbled.png',
        ocrText: garbledOcrText,
        categories: categories,
      );
      expect(withoutCleanup.needsAmount, isTrue);

      final withCleanup = parseReceiptOcrText(
        filePath: '/tmp/garbled.png',
        ocrText: garbledOcrText,
        categories: categories,
        understanding: understanding,
      );
      expect(withCleanup.amountMyr, 42.50);
      expect(withCleanup.needsAmount, isFalse);
    });

    test('never replaces the persisted raw ocrText with cleaned text', () {
      final understanding = ReceiptUnderstanding(
        merchantName: null,
        merchantSearchQueries: const [],
        addressText: null,
        locationClues: const [],
        vendorCategory: null,
        googlePlaceTypes: const [],
        lineItems: const [],
        confidence: _fixtureConfidence,
        cleanedLines: cleanedOcrText.trim().split('\n'),
        cleanedOcrText: cleanedOcrText,
      );

      final result = parseReceiptOcrText(
        filePath: '/tmp/garbled.png',
        ocrText: garbledOcrText,
        categories: categories,
        understanding: understanding,
      );

      // raw_ocr_text immutability: ReceiptParseResult.ocrText is what gets
      // persisted as transactions.raw_ocr_text — it must stay the true OCR
      // output even though the heuristics above ran against cleaned text.
      expect(result.ocrText, garbledOcrText);
    });

    test('pairs cleanedLines with original height_ratio for merchant'
        ' extraction', () {
      const ocrLines = [
        OcrLine(text: 'RESTQRAN ANWAR MAJU', heightRatio: 0.12),
        OcrLine(text: 'T0TAL RM 4Z.5O', heightRatio: 0.04),
      ];
      final understanding = ReceiptUnderstanding(
        merchantName: null,
        merchantSearchQueries: const [],
        addressText: null,
        locationClues: const [],
        vendorCategory: null,
        googlePlaceTypes: const [],
        lineItems: const [],
        confidence: _fixtureConfidence,
        cleanedLines: const ['RESTORAN ANWAR MAJU', 'TOTAL RM 42.50'],
        cleanedOcrText: cleanedOcrText,
      );

      final result = parseReceiptOcrText(
        filePath: '/tmp/garbled.png',
        ocrText: garbledOcrText,
        categories: categories,
        ocrLines: ocrLines,
        understanding: understanding,
      );

      // The large-font header line ("RESTORAN...") wins the merchant slot,
      // and it's the *cleaned* spelling, not the garbled OCR original.
      expect(result.merchantRaw, contains('RESTORAN'));
    });

    test('falls back to raw ocrLines when cleanedLines length mismatches',
        () {
      const ocrLines = [
        OcrLine(text: 'RESTQRAN ANWAR MAJU', heightRatio: 0.12),
        OcrLine(text: 'T0TAL RM 4Z.5O', heightRatio: 0.04),
      ];
      final understanding = ReceiptUnderstanding(
        merchantName: null,
        merchantSearchQueries: const [],
        addressText: null,
        locationClues: const [],
        vendorCategory: null,
        googlePlaceTypes: const [],
        lineItems: const [],
        confidence: _fixtureConfidence,
        // Mismatched length vs ocrLines — must not throw, must fall back.
        cleanedLines: const ['RESTORAN ANWAR MAJU'],
        cleanedOcrText: cleanedOcrText,
      );

      expect(
        () => parseReceiptOcrText(
          filePath: '/tmp/garbled.png',
          ocrText: garbledOcrText,
          categories: categories,
          ocrLines: ocrLines,
          understanding: understanding,
        ),
        returnsNormally,
      );
    });
  });

  group('categoryPreferenceHint', () {
    final testCategories = CategoryConfig.fromJson({
      'version': 'test',
      'default_category': 'Others',
      'rules': [
        {
          'category': 'Food & Drink',
          'any_of': ['cafe', 'restoran'],
        },
      ],
    });

    test(
        'overrides a low-confidence default guess once corroborated at '
        'least twice', () {
      final result = parseReceiptOcrText(
        filePath: '/tmp/unknown.png',
        ocrText: 'UNKNOWN MERCHANT\nNo keyword on this receipt\n',
        categories: testCategories,
        categoryPreferenceHint: const CategoryPreferenceHint(
          category: 'Groceries',
          correctionCount: 2,
        ),
      );

      expect(result.categoryGuess, 'Groceries');
      expect(result.categoryConfidence, categoryPreferenceConfidence);
    });

    test('does not override when the corroboration gate is not met', () {
      final result = parseReceiptOcrText(
        filePath: '/tmp/unknown.png',
        ocrText: 'UNKNOWN MERCHANT\nNo keyword on this receipt\n',
        categories: testCategories,
        categoryPreferenceHint: const CategoryPreferenceHint(
          category: 'Groceries',
          correctionCount: 1,
        ),
      );

      expect(result.categoryGuess, testCategories.defaultCategory);
    });

    test('does not override a confident merchant-keyword hit', () {
      final result = parseReceiptOcrText(
        filePath: '/tmp/cafe.png',
        ocrText: 'ROCK CAFE SDN BHD\nNo other keyword here\n',
        categories: testCategories,
        categoryPreferenceHint: const CategoryPreferenceHint(
          category: 'Groceries',
          correctionCount: 5,
        ),
      );

      expect(result.categoryGuess, 'Food & Drink');
    });

    test('a null hint changes nothing (today\'s baseline behavior)', () {
      final result = parseReceiptOcrText(
        filePath: '/tmp/unknown.png',
        ocrText: 'UNKNOWN MERCHANT\nNo keyword on this receipt\n',
        categories: testCategories,
      );

      expect(result.categoryGuess, testCategories.defaultCategory);
    });
  });
}
