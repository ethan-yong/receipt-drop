import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_drop/domain/logic/category_matcher.dart';
import 'package:receipt_drop/domain/logic/merchant_extractor.dart';
import 'package:receipt_drop/domain/logic/receipt_layout_analyzer.dart';
import 'package:receipt_drop/domain/models/ocr_line.dart';
import 'package:receipt_drop/domain/models/receipt_line_zone.dart';

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

  test('skips OCR scene junk without a real word in the fallback', () {
    // Handheld photos against busy backgrounds put stray-character lines
    // above the header; none contains a 3+ letter run, the merchant does.
    final ocr = '- : a a ~~ . ;\noo a\nUl }\nRESTORAN ANWAR MAJU\nINVOICE';
    expect(extractMerchant(ocr, categories), 'RESTORAN ANWAR MAJU');
  });

  test('strips edge junk from the winning merchant line', () {
    // Scene characters glued onto the header line itself must not survive
    // into the stored merchant (they leak into every downstream title).
    final ocr = '\\ RESTORAN ANWAR MAU.\nINVOICE\nRM 64.80';
    expect(extractMerchant(ocr, categories), 'RESTORAN ANWAR MAU');
  });

  test('returns null for empty OCR text', () {
    expect(extractMerchant('', categories), isNull);
  });

  test('returns null for whitespace-only OCR text', () {
    expect(extractMerchant('   \n  \n', categories), isNull);
  });

  group('extractMerchantCandidates', () {
    test('ranks a business-keyword line above a plain positional line', () {
      final ocr = '- : a a ~~ . ;\nRESTORAN ANWAR MAJU\nSOME OTHER TEXT HERE';
      final candidates = extractMerchantCandidates(ocr, categories);
      expect(candidates, isNotEmpty);
      expect(candidates.first.text, 'RESTORAN ANWAR MAJU');
      expect(candidates.first.source, 'keyword');
      expect(candidates.length, greaterThan(1));
    });

    test(
        'does not let a short OCR-noise fragment outrank the actual '
        '(badly garbled) merchant header — real regression fixture', () {
      // Real pytesseract output from a poor-quality (32% confidence) scan
      // of a "RESTORAN ANWAR MAJU" receipt — a genuine production log, not
      // a synthetic fixture. Tesseract shattered "RESTORAN" into "RES
      // TORAN" and "ANWAR" into "ANN mn", so the business-keyword pass
      // ('restoran') can't match it — the header line only surfaces via
      // the position-tier fallback (pass 3), alongside short noise
      // fragments like "mel" that must not outrank it.
      const ocr = '\\\n'
          '=, XN i\n'
          'sf.\n'
          'y\n'
          'mel\n'
          'i saaseee\n'
          'JU\n'
          '\\ [| RES TORAN ANN mn .\n'
          '"REG.NO.: ..ceee\n'
          'NO.1-A NADAYU28,JLN PJS 11/7\n'
          '| -BANDAR SUNWAY 47500 SELANGOR.\n'
          'he INVOICE\n'
          '| +44 MOBILE PAY 23%.\n'
          '| TAXNO, | :346131\n'
          ', TABLENO 3:62';
      final candidates = extractMerchantCandidates(ocr, categories);
      expect(candidates, isNotEmpty);
      expect(candidates.first.text, isNot('mel'));
      expect(candidates.first.text, contains('TORAN'));
    });

    test('resolves the exact garbled-OCR example from the request', () {
      // "RESTORAN ANWAR MAU" is what pytesseract actually produces for the
      // real "Restoran Anwar Maju" — this must surface as the top candidate
      // so Google Places enrichment gets a usable query.
      final ocr = 'RESTORAN ANWAR MAU\nTAX INVOICE\nRM 42.50';
      final candidates = extractMerchantCandidates(ocr, categories);
      expect(candidates.first.text, 'RESTORAN ANWAR MAU');
      expect(candidates.first.confidence, greaterThan(0.7));
    });

    test('excludes phone number lines from candidates', () {
      final ocr = 'JOE\'S CORNER STORE\nTel: 012-345 6789\nRM 5.00';
      final candidates = extractMerchantCandidates(ocr, categories);
      expect(
        candidates.any((c) => c.text.contains('012')),
        isFalse,
      );
      expect(candidates.first.text, "JOE'S CORNER STORE");
    });

    test('excludes date lines from candidates', () {
      final ocr = 'KEDAI RUNCIT BAHAGIA\n12/05/2026 14:30\nRM 8.90';
      final candidates = extractMerchantCandidates(ocr, categories);
      expect(candidates.any((c) => c.text.contains('12/05/2026')), isFalse);
    });

    test('excludes address lines from candidates', () {
      final ocr =
          'RESTORAN SEDAP\nJalan Bukit Bintang\n55100 Kuala Lumpur\nRM 20.00';
      final candidates = extractMerchantCandidates(ocr, categories);
      expect(candidates.any((c) => c.text.contains('Jalan')), isFalse);
      expect(candidates.any((c) => c.text.contains('55100')), isFalse);
      expect(candidates.first.text, 'RESTORAN SEDAP');
    });

    test('excludes tax ID lines from candidates', () {
      final ocr = 'KOPITIAM AMAN\nGST Reg No: 123456789012\nSST No: 98765';
      final candidates = extractMerchantCandidates(ocr, categories);
      expect(
        candidates.any((c) => c.text.toLowerCase().contains('gst reg')),
        isFalse,
      );
    });

    test('extractMerchant still returns the top candidate\'s text', () {
      final ocr = 'RESTORAN ANWAR MAJU\nTAX INVOICE\nRM 12.00';
      final candidates = extractMerchantCandidates(ocr, categories);
      expect(extractMerchant(ocr, categories), candidates.first.text);
    });

    test('returns an empty list for empty OCR text', () {
      expect(extractMerchantCandidates('', categories), isEmpty);
    });

    test('returns an empty list for whitespace-only OCR text', () {
      expect(extractMerchantCandidates('   \n  \n', categories), isEmpty);
    });

    test('scans up to 15 lines, not just 8', () {
      final filler = List.generate(10, (i) => 'FILLER LINE NUMBER $i').join('\n');
      final ocr = '$filler\nRESTORAN ANWAR MAJU\nRM 10.00';
      final candidates = extractMerchantCandidates(ocr, categories);
      expect(candidates.any((c) => c.text == 'RESTORAN ANWAR MAJU'), isTrue);
    });
  });

  group('extractMerchantCandidates with ocrLines (large-text signal)', () {
    test(
        'prefers a visually large-font line with no keyword over a longer '
        'small-font one, once height data is supplied', () {
      const ocr = 'Welcome valued customer to our humble shop today\n'
          'ZOOMCO\n'
          'Item A RM 5.00\n'
          'Item B RM 3.00';

      // Without height data: the longer "Welcome..." line wins via the
      // plain letter-count fallback (pass 3) — proving the assertion below
      // is genuinely due to the large-text signal, not a coincidence.
      final withoutHeights = extractMerchantCandidates(ocr, categories);
      expect(withoutHeights.first.text, isNot('ZOOMCO'));

      final ocrLines = [
        const OcrLine(
          text: 'Welcome valued customer to our humble shop today',
          heightRatio: 0.03,
        ),
        const OcrLine(text: 'ZOOMCO', heightRatio: 0.10),
        const OcrLine(text: 'Item A RM 5.00', heightRatio: 0.025),
        const OcrLine(text: 'Item B RM 3.00', heightRatio: 0.025),
      ];
      final withHeights = extractMerchantCandidates(
        ocr,
        categories,
        ocrLines: ocrLines,
      );
      expect(withHeights.first.text, 'ZOOMCO');
      expect(withHeights.first.source, 'largeText');
    });

    test('a category-keyword match still wins over a large-text line', () {
      const ocr = "BIG LOGO TEXT\nMCDONALD'S SUNWAY\nTOTAL RM 10.00";
      final ocrLines = [
        const OcrLine(text: 'BIG LOGO TEXT', heightRatio: 0.12),
        const OcrLine(text: "MCDONALD'S SUNWAY", heightRatio: 0.03),
        const OcrLine(text: 'TOTAL RM 10.00', heightRatio: 0.025),
      ];
      final candidates = extractMerchantCandidates(
        ocr,
        categories,
        ocrLines: ocrLines,
      );
      expect(candidates.first.text, "MCDONALD'S SUNWAY");
      expect(candidates.first.source, 'header');
    });

    test(
        'does not promote a large-font phone number line via the '
        'large-text pass', () {
      const ocr = "Tel: 012-345 6789\nJOE'S CORNER STORE\nTOTAL RM 5.00";
      final ocrLines = [
        const OcrLine(text: 'Tel: 012-345 6789', heightRatio: 0.15),
        const OcrLine(text: "JOE'S CORNER STORE", heightRatio: 0.03),
        const OcrLine(text: 'TOTAL RM 5.00', heightRatio: 0.025),
      ];
      final candidates = extractMerchantCandidates(
        ocr,
        categories,
        ocrLines: ocrLines,
      );
      expect(candidates.any((c) => c.text.contains('012')), isFalse);
    });

    test('ignores ocrLines entirely when null or empty (fully additive)', () {
      const ocr = "MCDONALD'S SUNWAY\nTOTAL RM 10.00";
      final withNull = extractMerchantCandidates(ocr, categories);
      final withEmpty =
          extractMerchantCandidates(ocr, categories, ocrLines: const []);
      expect(withNull.first.text, withEmpty.first.text);
    });

    test('layout zones suppress business-word merchant hit inside body', () {
      const ocr =
          'MY RESTORAN\n'
          'Kopitiam Fried Rice  RM 12.00\n'
          'Teh Tarik           RM 3.00\n'
          'Subtotal            RM 15.00\n'
          'TOTAL               RM 15.00';
      final texts = ocr.split('\n');
      final ocrLines = [
        for (final t in texts) OcrLine(text: t, heightRatio: 0.02),
      ];
      final withoutLayout =
          extractMerchantCandidates(ocr, categories, ocrLines: ocrLines);
      final layout = analyzeReceiptLayout(ocr, ocrLines);
      final withLayout = extractMerchantCandidates(
        ocr,
        categories,
        ocrLines: ocrLines,
        layout: layout,
      );
      expect(withoutLayout.any((c) => c.text.contains('Kopitiam')), isTrue);
      expect(withLayout.any((c) => c.text.contains('Kopitiam')), isFalse);
    });

    test('unreliable layout matches omitting layout entirely', () {
      const ocr = "MCDONALD'S SUNWAY\nTOTAL RM 10.00";
      final baseline = extractMerchantCandidates(ocr, categories);
      final withUnreliable = extractMerchantCandidates(
        ocr,
        categories,
        layout: const ReceiptLayoutAnalysis(
          zones: [ReceiptLineZone.body],
          isReliable: false,
        ),
      );
      expect(withUnreliable.map((c) => c.text).toList(),
          baseline.map((c) => c.text).toList());
    });
  });
}
