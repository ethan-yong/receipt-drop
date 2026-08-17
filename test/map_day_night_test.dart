import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_drop/domain/logic/map_day_night.dart';

void main() {
  group('isMapNightMode', () {
    DateTime at(int hour, [int minute = 0]) =>
        DateTime(2026, 8, 14, hour, minute);

    test('night before 06:00', () {
      expect(isMapNightMode(at(5, 59)), isTrue);
      expect(isMapNightMode(at(0)), isTrue);
    });

    test('day from 06:00 through 17:59', () {
      expect(isMapNightMode(at(6)), isFalse);
      expect(isMapNightMode(at(12)), isFalse);
      expect(isMapNightMode(at(17, 59)), isFalse);
    });

    test('night from 18:00 onward', () {
      expect(isMapNightMode(at(18)), isTrue);
      expect(isMapNightMode(at(23)), isTrue);
    });
  });

  group('untilNextMapStyleChange', () {
    test('before 06:00 waits until 06:00 same day', () {
      final now = DateTime(2026, 8, 14, 5, 30);
      final wait = untilNextMapStyleChange(now);
      expect(now.add(wait), DateTime(2026, 8, 14, 6));
    });

    test('during day waits until 18:00 same day', () {
      final now = DateTime(2026, 8, 14, 12);
      final wait = untilNextMapStyleChange(now);
      expect(now.add(wait), DateTime(2026, 8, 14, 18));
    });

    test('after 18:00 waits until 06:00 next day', () {
      final now = DateTime(2026, 8, 14, 20);
      final wait = untilNextMapStyleChange(now);
      expect(now.add(wait), DateTime(2026, 8, 15, 6));
    });

    test('duration is always positive', () {
      for (final hour in [0, 5, 6, 12, 17, 18, 23]) {
        final wait = untilNextMapStyleChange(DateTime(2026, 8, 14, hour));
        expect(wait.isNegative, isFalse, reason: 'hour $hour');
        expect(wait > Duration.zero, isTrue, reason: 'hour $hour');
      }
    });
  });
}
