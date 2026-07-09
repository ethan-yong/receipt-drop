import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_drop/domain/logic/category_matcher_bundled.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('matches first keyword rule', () async {
    final cfg = await loadBundledCategoryConfig();
    final guess = cfg.guessForMerchant('7-ELEVEN SUNWAY');
    expect(guess.category, 'Food & Drink');
  });

  test('falls back to default', () async {
    final cfg = await loadBundledCategoryConfig();
    final guess = cfg.guessForMerchant('UNKNOWN MERCHANT XYZ');
    expect(guess.category, 'Others');
  });

  test('matches newly added Shopping category', () async {
    final cfg = await loadBundledCategoryConfig();
    final guess = cfg.guessForMerchant('UNIQLO KLCC');
    expect(guess.category, 'Shopping');
  });

  test('matches newly added Groceries brand', () async {
    final cfg = await loadBundledCategoryConfig();
    final guess = cfg.guessForMerchant('99 SPEEDMART G-15');
    expect(guess.category, 'Groceries');
  });

  test('matches newly added Transport brand', () async {
    final cfg = await loadBundledCategoryConfig();
    final guess = cfg.guessForMerchant('RAPIDKL MRT KAJANG LINE');
    expect(guess.category, 'Transport');
  });

  group('guessWithConfidence', () {
    test('returns 0.85 when keyword is in merchant name', () async {
      final cfg = await loadBundledCategoryConfig();
      final result = cfg.guessWithConfidence('STARBUCKS KLCC', '');
      expect(result.category, 'Food & Drink');
      expect(result.confidence, 0.85);
    });

    test('returns 0.55 and correct category when brand only appears in OCR body',
        () async {
      final cfg = await loadBundledCategoryConfig();
      const ocrText = '''
LOREM IPSUM SDN BHD
Petron Station
RM 80.00
TOTAL RM 80.00
''';
      final result =
          cfg.guessWithConfidence('LOREM IPSUM SDN BHD', ocrText);
      expect(result.category, 'Transport');
      expect(result.confidence, 0.55);
    });

    test('returns defaultCategory and 0.10 when nothing matches', () async {
      final cfg = await loadBundledCategoryConfig();
      const ocrText = 'XYZ ENTERPRISE\nRECEIPT NO: 12345\nTOTAL RM 5.00';
      final result = cfg.guessWithConfidence('XYZ ENTERPRISE', ocrText);
      expect(result.category, cfg.defaultCategory);
      expect(result.confidence, 0.10);
    });
  });
}
