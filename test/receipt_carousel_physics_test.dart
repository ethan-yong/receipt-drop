import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_drop/widgets/receipt_carousel_physics.dart';

void main() {
  group('wrapIndex', () {
    test('in-range index passes through', () {
      expect(wrapIndex(2, 5), 2);
    });

    test('wraps forward past the end', () {
      expect(wrapIndex(5, 5), 0);
      expect(wrapIndex(7, 5), 2);
    });

    test('wraps backward before zero', () {
      expect(wrapIndex(-1, 5), 4);
      expect(wrapIndex(-6, 5), 4);
    });

    test('zero pageCount never throws', () {
      expect(wrapIndex(3, 0), 0);
    });
  });

  group('shortestPageDelta', () {
    test('forward short path', () {
      expect(shortestPageDelta(0, 2, 5), 2);
    });

    test('wraps the long way the other direction', () {
      expect(shortestPageDelta(0, 4, 5), -1);
    });

    test('zero when same', () {
      expect(shortestPageDelta(3, 3, 5), 0);
    });
  });

  group('roundToNearestPage / nearestRealIndex', () {
    test('rounds to the nearer integer page', () {
      expect(roundToNearestPage(2.3), 2);
      expect(roundToNearestPage(2.7), 3);
    });

    test('nearestRealIndex wraps the rounded page into range', () {
      expect(nearestRealIndex(4.6, 5), 0);
      expect(nearestRealIndex(-0.6, 5), 4);
    });

    test('nearestRealIndex on a single-page carousel is always 0', () {
      expect(nearestRealIndex(37.2, 1), 0);
    });
  });

  group('cardSlotWidth / cardExtentPx', () {
    test('slot width is a fraction of the viewport', () {
      expect(cardSlotWidth(300), closeTo(300 * kCardWidthFraction, 1e-9));
    });

    test('extent adds the inter-card gap', () {
      expect(
        cardExtentPx(300),
        closeTo(300 * kCardWidthFraction + kCardSpacingPx, 1e-9),
      );
    });
  });

  group('pxDeltaToPages / pxVelocityToPagesPerSecond', () {
    const width = 300.0;

    test('left drag (negative px) advances (positive pages)', () {
      final pages = pxDeltaToPages(deltaPx: -50, viewportWidth: width);
      expect(pages, greaterThan(0));
    });

    test('right drag (positive px) goes back (negative pages)', () {
      final pages = pxDeltaToPages(deltaPx: 50, viewportWidth: width);
      expect(pages, lessThan(0));
    });

    test('moving exactly one card extent equals one page', () {
      final extent = cardExtentPx(width);
      final pages = pxDeltaToPages(deltaPx: -extent, viewportWidth: width);
      expect(pages, closeTo(1.0, 1e-9));
    });

    test('velocity conversion follows the same sign convention', () {
      final pages = pxVelocityToPagesPerSecond(
        velocityPxPerSec: -3000,
        viewportWidth: width,
      );
      expect(pages, greaterThan(0));
    });

    test('zero/negative viewport width does not divide by zero', () {
      expect(
        () => pxDeltaToPages(deltaPx: -50, viewportWidth: 0),
        returnsNormally,
      );
    });
  });

  group('visibleSlots', () {
    test('single page always returns just index 0', () {
      final slots = visibleSlots(offset: 0.4, pageCount: 1);
      expect(slots, hasLength(1));
      expect(slots.single.index, 0);
    });

    test('on an integer offset, the center slot has zero delta', () {
      final slots = visibleSlots(offset: 2.0, pageCount: 10);
      final center = slots.firstWhere((s) => s.index == 2);
      expect(center.delta, 0);
    });

    test('straddling neighbors have correctly-signed fractional deltas', () {
      final slots = visibleSlots(offset: 1.4, pageCount: 10);
      final left = slots.firstWhere((s) => s.index == 1);
      final right = slots.firstWhere((s) => s.index == 2);
      expect(left.delta, closeTo(-0.4, 1e-9));
      expect(right.delta, closeTo(0.6, 1e-9));
    });

    test('window is capped at 2*windowRadius+1 for a long list', () {
      final slots = visibleSlots(offset: 5.0, pageCount: 100, windowRadius: 2);
      expect(slots, hasLength(5));
    });

    test('small pageCount dedupes aliasing candidates by nearest delta', () {
      final slots = visibleSlots(offset: 0.3, pageCount: 2, windowRadius: 2);
      final indices = slots.map((s) => s.index).toSet();
      expect(indices, {0, 1});
      expect(slots, hasLength(2));
    });

    test('boundary wrap gives the wrapped neighbor a small signed delta', () {
      // pageCount=5, offset near the top of the list: index 0 should be
      // "just ahead" (small positive delta), not far away unwrapped.
      final slots = visibleSlots(offset: 4.3, pageCount: 5);
      final wrapped = slots.firstWhere((s) => s.index == 0);
      expect(wrapped.delta, closeTo(0.7, 1e-9));
    });
  });

  group('cardTransformForDelta', () {
    const extent = 320.0;

    test('centered card is full scale, full opacity, no offset', () {
      final t = cardTransformForDelta(delta: 0, cardExtentPx: extent);
      expect(t.dx, 0);
      expect(t.scale, 1.0);
      expect(t.opacity, 1.0);
      expect(t.zOrder, 0);
    });

    test('dx scales with delta and the card extent', () {
      final t = cardTransformForDelta(delta: 1.0, cardExtentPx: extent);
      expect(t.dx, closeTo(extent, 1e-9));
    });

    test('scale/opacity shrink monotonically with distance', () {
      final near = cardTransformForDelta(delta: 0.5, cardExtentPx: extent);
      final far = cardTransformForDelta(delta: 1.2, cardExtentPx: extent);
      expect(far.scale, lessThan(near.scale));
      expect(far.opacity, lessThan(near.opacity));
    });

    test('scale/opacity bottom out beyond the falloff radius', () {
      final atRadius = cardTransformForDelta(
        delta: kPeekFalloffRadius,
        cardExtentPx: extent,
      );
      final beyond = cardTransformForDelta(
        delta: kPeekFalloffRadius + 5,
        cardExtentPx: extent,
      );
      expect(atRadius.scale, closeTo(kPeekMinScale, 1e-9));
      expect(beyond.scale, closeTo(kPeekMinScale, 1e-9));
      expect(atRadius.opacity, closeTo(kPeekMinOpacity, 1e-9));
      expect(beyond.opacity, closeTo(kPeekMinOpacity, 1e-9));
    });
  });

  group('clampOffsetTravel', () {
    test('passes through values within the cap', () {
      expect(
        clampOffsetTravel(offset: 2.0, flingStart: 0.0, maxPages: 6),
        2.0,
      );
    });

    test('clamps forward travel at the cap', () {
      expect(
        clampOffsetTravel(offset: 10.0, flingStart: 0.0, maxPages: 6),
        6.0,
      );
    });

    test('clamps backward travel at the cap', () {
      expect(
        clampOffsetTravel(offset: -10.0, flingStart: 0.0, maxPages: 6),
        -6.0,
      );
    });
  });

  group('frictionShouldHandoffToSpring', () {
    test('low velocity hands off immediately regardless of travel', () {
      expect(
        frictionShouldHandoffToSpring(
          velocityPagesPerSec: 0.1,
          offset: 0.2,
          flingStart: 0.0,
        ),
        isTrue,
      );
    });

    test('strong velocity within the travel cap keeps gliding', () {
      expect(
        frictionShouldHandoffToSpring(
          velocityPagesPerSec: 3.0,
          offset: 1.0,
          flingStart: 0.0,
        ),
        isFalse,
      );
    });

    test('travel cap forces handoff even at high velocity', () {
      expect(
        frictionShouldHandoffToSpring(
          velocityPagesPerSec: 5.0,
          offset: 6.5,
          flingStart: 0.0,
          maxPages: 6,
        ),
        isTrue,
      );
    });
  });
}
