import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_drop/domain/logic/map_pin_layout.dart';

void main() {
  group('groupOverlappingKeys', () {
    test('far-apart points stay as singleton groups', () {
      final groups = groupOverlappingKeys({
        'a': (x: 0, y: 0),
        'b': (x: 200, y: 200),
      });
      expect(groups, hasLength(2));
      expect(groups.every((g) => g.length == 1), isTrue);
      final keys = groups.expand((g) => g).toSet();
      expect(keys, {'a', 'b'});
    });

    test('points within threshold collapse into one group', () {
      final groups = groupOverlappingKeys({
        'a': (x: 0, y: 0),
        'b': (x: 30, y: 10),
      });
      expect(groups, hasLength(1));
      expect(groups.single.toSet(), {'a', 'b'});
    });

    test('transitive chaining merges A-B-C when A and C alone are far', () {
      // A—B close, B—C close, A—C far (beyond default 52px).
      final groups = groupOverlappingKeys({
        'a': (x: 0, y: 0),
        'b': (x: 40, y: 0),
        'c': (x: 80, y: 0),
      });
      expect(groups, hasLength(1));
      expect(groups.single.toSet(), {'a', 'b', 'c'});
    });

    test('empty input returns empty list', () {
      expect(groupOverlappingKeys(const {}), isEmpty);
    });

    test('custom threshold keeps near points separate', () {
      final groups = groupOverlappingKeys({
        'a': (x: 0, y: 0),
        'b': (x: 30, y: 0),
      }, thresholdPx: 20);
      expect(groups, hasLength(2));
    });

    test('mixed place:/friend: prefixes group when within threshold', () {
      final groups = groupOverlappingKeys({
        'place:abc': (x: 0, y: 0),
        'friend:xyz': (x: 20, y: 10),
      });
      expect(groups, hasLength(1));
      expect(groups.single.toSet(), {'place:abc', 'friend:xyz'});
    });

    test('mixed place:/friend: prefixes stay separate when far apart', () {
      final groups = groupOverlappingKeys({
        'place:abc': (x: 0, y: 0),
        'friend:xyz': (x: 200, y: 200),
      });
      expect(groups, hasLength(2));
      expect(groups.every((g) => g.length == 1), isTrue);
      final keys = groups.expand((g) => g).toSet();
      expect(keys, {'place:abc', 'friend:xyz'});
    });
  });

  group('spiderfyOffsets', () {
    test('returns empty for count <= 0', () {
      expect(spiderfyOffsets(0), isEmpty);
      expect(spiderfyOffsets(-1), isEmpty);
    });

    test('single pin sits at origin', () {
      expect(spiderfyOffsets(1), [(x: 0.0, y: 0.0)]);
    });

    test('returns one offset per pin at the expected radius', () {
      const base = 44.0;
      final offsets = spiderfyOffsets(4, baseRadius: base);
      expect(offsets, hasLength(4));
      // count=4 → radius = base + (4-2)*6 = 56
      const expectedRadius = base + 12;
      for (final o in offsets) {
        final mag = math.sqrt(o.x * o.x + o.y * o.y);
        expect(mag, closeTo(expectedRadius, 1e-9));
      }
    });

    test('default baseRadius is 44', () {
      final offsets = spiderfyOffsets(2);
      expect(offsets, hasLength(2));
      for (final o in offsets) {
        final mag = math.sqrt(o.x * o.x + o.y * o.y);
        expect(mag, closeTo(44.0, 1e-9));
      }
    });

    test('first offset is at the top and angles are evenly spaced', () {
      final offsets = spiderfyOffsets(3, baseRadius: 50);
      // count=3 → radius = 50 + (3-2)*6 = 56; first at −π/2 (top).
      const radius = 56.0;
      expect(offsets[0].x, closeTo(0, 1e-9));
      expect(offsets[0].y, closeTo(-radius, 1e-9));

      // Angular spacing should be 2π/3.
      double angleOf(ScreenPoint p) => math.atan2(p.y, p.x);
      final a0 = angleOf(offsets[0]);
      final a1 = angleOf(offsets[1]);
      final a2 = angleOf(offsets[2]);
      double delta(double from, double to) {
        var d = to - from;
        while (d < 0) {
          d += 2 * math.pi;
        }
        while (d >= 2 * math.pi) {
          d -= 2 * math.pi;
        }
        return d;
      }

      expect(delta(a0, a1), closeTo(2 * math.pi / 3, 1e-9));
      expect(delta(a1, a2), closeTo(2 * math.pi / 3, 1e-9));
    });
  });
}
