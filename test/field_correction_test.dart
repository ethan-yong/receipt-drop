import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_drop/core/utils/text_normalize.dart';
import 'package:receipt_drop/domain/models/field_correction.dart';

void main() {
  group('FieldCorrection JSON roundtrip', () {
    test('roundtrips every field', () {
      const correction = FieldCorrection(
        field: FieldCorrection.fieldLineItemPrice,
        predictedValue: '7.00',
        confirmedValue: '9.50',
        merchantRaw: 'SF CAFE SDN BHD',
        confidence: 0.6,
        correctionType: null,
        lineItemIndex: 0,
      );

      final restored = FieldCorrection.tryFromJson(correction.toJson());

      expect(restored, isNotNull);
      expect(restored!.field, correction.field);
      expect(restored.predictedValue, correction.predictedValue);
      expect(restored.confirmedValue, correction.confirmedValue);
      expect(restored.merchantRaw, correction.merchantRaw);
      expect(restored.confidence, correction.confidence);
      expect(restored.lineItemIndex, correction.lineItemIndex);
    });

    test('tryFromJson rejects malformed input', () {
      expect(FieldCorrection.tryFromJson(null), isNull);
      expect(FieldCorrection.tryFromJson('not a map'), isNull);
      expect(FieldCorrection.tryFromJson({'field': 'merchant'}), isNull);
    });

    test('formatAmount always uses two decimal places', () {
      expect(FieldCorrection.formatAmount(7), '7.00');
      expect(FieldCorrection.formatAmount(9.5), '9.50');
      expect(FieldCorrection.formatAmount(12.345), '12.35');
    });
  });

  group('normalizeForCompare', () {
    test('lowercases and collapses punctuation/whitespace runs', () {
      expect(normalizeForCompare('SF   Cafe, Sdn. Bhd.'), 'sf cafe sdn bhd');
    });

    test('two visually-different-but-equivalent strings normalize the same',
        () {
      expect(
        normalizeForCompare('99 Speedmart (Cheras)'),
        normalizeForCompare('99  SPEEDMART   CHERAS'),
      );
    });
  });
}
