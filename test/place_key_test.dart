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

  group('geohashBounds', () {
    test("centroid falls within the cell's own bounds", () {
      final hash = geohashAt(3.1390, 101.6869, 6);
      final box = geohashBounds(hash);
      final center = geohashCentroid(hash);
      expect(center.lat, inInclusiveRange(box.latMin, box.latMax));
      expect(center.lng, inInclusiveRange(box.lngMin, box.lngMax));
    });

    test('higher precision yields a smaller box', () {
      final coarse = geohashBounds(geohashAt(3.1390, 101.6869, 4));
      final fine = geohashBounds(geohashAt(3.1390, 101.6869, 8));
      final coarseLatSpan = coarse.latMax - coarse.latMin;
      final fineLatSpan = fine.latMax - fine.latMin;
      expect(fineLatSpan, lessThan(coarseLatSpan));
    });
  });
}
