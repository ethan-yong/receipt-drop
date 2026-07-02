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
}
