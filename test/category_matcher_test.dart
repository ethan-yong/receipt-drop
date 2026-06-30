import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_drop/domain/logic/category_matcher.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('matches first keyword rule', () async {
    final cfg = await CategoryConfig.loadBundled();
    final guess = cfg.guessForMerchant('7-ELEVEN SUNWAY');
    expect(guess.category, 'Food & Drink');
  });

  test('falls back to default', () async {
    final cfg = await CategoryConfig.loadBundled();
    final guess = cfg.guessForMerchant('UNKNOWN MERCHANT XYZ');
    expect(guess.category, 'Others');
  });
}
