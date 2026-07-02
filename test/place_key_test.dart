import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_drop/core/utils/place_key.dart';

void main() {
  test('uses place_id when present', () {
    expect(effectivePlaceKey('ChIJxxx', 3.07, 101.60), 'pid:ChIJxxx');
  });

  test('uses geohash precision 8 when place_id null', () {
    final k = effectivePlaceKey(null, 3.0738, 101.6063);
    expect(k.startsWith('gh8:'), isTrue);
  });
}
