import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_drop/features/save_success/save_success_screen.dart';

void main() {
  group('variantForReceiptCount', () {
    test('0 and 1 receipts is single', () {
      expect(variantForReceiptCount(0), CargoVariant.single);
      expect(variantForReceiptCount(1), CargoVariant.single);
    });

    test('2 through 5 receipts is stack', () {
      expect(variantForReceiptCount(2), CargoVariant.stack);
      expect(variantForReceiptCount(5), CargoVariant.stack);
    });

    test('6 and above is bag', () {
      expect(variantForReceiptCount(6), CargoVariant.bag);
      expect(variantForReceiptCount(100), CargoVariant.bag);
    });
  });

  group('savedLabelForReceiptCount', () {
    test('0 and 1 receipts reads "Saved"', () {
      expect(savedLabelForReceiptCount(0), 'Saved');
      expect(savedLabelForReceiptCount(1), 'Saved');
    });

    test('2 or more receipts reads "N receipts saved"', () {
      expect(savedLabelForReceiptCount(2), '2 receipts saved');
      expect(savedLabelForReceiptCount(12), '12 receipts saved');
    });
  });
}
