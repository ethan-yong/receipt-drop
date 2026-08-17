import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_drop/widgets/receipt_carousel_physics.dart';

void main() {
  group('computeTargetPage', () {
    const width = 300.0;

    test('under-threshold release stays on current page', () {
      expect(
        computeTargetPage(
          currentPage: 0,
          dragDeltaPx: -30,
          velocityPxPerSec: 0,
          viewportWidthPx: width,
          pageCount: 5,
        ),
        0,
      );
    });

    test('slow left swipe advances one page', () {
      expect(
        computeTargetPage(
          currentPage: 0,
          dragDeltaPx: -70,
          velocityPxPerSec: -100,
          viewportWidthPx: width,
          pageCount: 5,
        ),
        1,
      );
    });

    test('slow right swipe goes back one page', () {
      expect(
        computeTargetPage(
          currentPage: 2,
          dragDeltaPx: 70,
          velocityPxPerSec: 100,
          viewportWidthPx: width,
          pageCount: 5,
        ),
        1,
      );
    });

    test('fast left fling skips multiple pages', () {
      final target = computeTargetPage(
        currentPage: 0,
        dragDeltaPx: -80,
        velocityPxPerSec: -2800,
        viewportWidthPx: width,
        pageCount: 6,
      );
      expect(target, greaterThanOrEqualTo(2));
      expect(target, lessThanOrEqualTo(kMaxSkipPages));
    });

    test('caps skip at kMaxSkipPages', () {
      final target = computeTargetPage(
        currentPage: 0,
        dragDeltaPx: -200,
        velocityPxPerSec: -20000,
        viewportWidthPx: width,
        pageCount: 20,
      );
      expect(target, lessThanOrEqualTo(kMaxSkipPages));
    });

    test('wraps forward past the last page', () {
      final target = computeTargetPage(
        currentPage: 4,
        dragDeltaPx: -70,
        velocityPxPerSec: -100,
        viewportWidthPx: width,
        pageCount: 5,
      );
      expect(target, 0);
    });

    test('wraps backward before the first page', () {
      final target = computeTargetPage(
        currentPage: 0,
        dragDeltaPx: 70,
        velocityPxPerSec: 100,
        viewportWidthPx: width,
        pageCount: 5,
      );
      expect(target, 4);
    });

    test('single page always returns 0', () {
      expect(
        computeTargetPage(
          currentPage: 0,
          dragDeltaPx: -200,
          velocityPxPerSec: -5000,
          viewportWidthPx: width,
          pageCount: 1,
        ),
        0,
      );
    });

    test('strong velocity alone can commit without large dx', () {
      final target = computeTargetPage(
        currentPage: 0,
        dragDeltaPx: -20,
        velocityPxPerSec: -1200,
        viewportWidthPx: width,
        pageCount: 5,
      );
      expect(target, greaterThanOrEqualTo(1));
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

  group('pageBlend', () {
    test('integer offset shows a single card', () {
      final b = pageBlend(pageOffset: 2.0, pageCount: 5);
      expect(b.from, 2);
      expect(b.to, 2);
      expect(b.t, 0);
    });

    test('fractional offset blends adjacent cards', () {
      final b = pageBlend(pageOffset: 1.4, pageCount: 5);
      expect(b.from, 1);
      expect(b.to, 2);
      expect(b.t, closeTo(0.4, 1e-9));
      expect(b.direction, 1);
    });

    test('wraps at the end of the list', () {
      final b = pageBlend(pageOffset: 4.3, pageCount: 5);
      expect(b.from, 4);
      expect(b.to, 0);
      expect(b.t, closeTo(0.3, 1e-9));
    });

    test('negative offsets wrap correctly', () {
      final b = pageBlend(pageOffset: -0.25, pageCount: 5);
      expect(b.from, 4);
      expect(b.to, 0);
      expect(b.t, closeTo(0.75, 1e-9));
    });
  });

  group('pageBlendDirected', () {
    test('backward fling swaps from/to and inverts t', () {
      final b = pageBlendDirected(
        pageOffset: 1.4,
        pageCount: 5,
        direction: -1,
      );
      expect(b.from, 2);
      expect(b.to, 1);
      expect(b.t, closeTo(0.6, 1e-9));
      expect(b.direction, -1);
    });
  });
}
