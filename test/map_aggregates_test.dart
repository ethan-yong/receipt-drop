import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_drop/domain/logic/map_aggregates.dart';
import 'package:receipt_drop/domain/models/transaction_view.dart';

TransactionView _tx({
  required String id,
  double? amount,
  double? lat,
  double? lng,
  String? category,
  DateTime? occurredAt,
}) {
  return TransactionView.fromOutbox(
    id: id,
    occurredAt: occurredAt ?? DateTime(2026, 7, 1),
    amountMyr: amount,
    needsAmount: false,
    merchantRaw: null,
    categoryGuess: category,
    categoryUser: null,
    placeName: null,
    placeGooglePlaceId: null,
    placeLat: lat,
    placeLng: lng,
    syncStatus: 'synced',
    pipelineStatus: 'done',
  );
}

void main() {
  group('heatCells', () {
    test('returns empty for rows without location or amount', () {
      final cells = heatCells([
        _tx(id: 'a', amount: 10),
        _tx(id: 'b', lat: 3.1, lng: 101.6),
      ]);
      expect(cells, isEmpty);
    });

    test('buckets nearby spends into the same geohash cell', () {
      // ~100m apart: same precision-5 cell (~4.9km x 4.9km).
      final cells = heatCells([
        _tx(id: 'a', amount: 10, lat: 3.1390, lng: 101.6869),
        _tx(id: 'b', amount: 30, lat: 3.1395, lng: 101.6872),
      ]);
      expect(cells, hasLength(1));
      expect(cells.single.intensity, 1.0);
    });

    test('sqrt-scales intensity against the busiest cell', () {
      final cells = heatCells([
        _tx(id: 'a', amount: 100, lat: 3.1390, lng: 101.6869),
        _tx(id: 'b', amount: 25, lat: 5.4141, lng: 100.3288), // Penang
      ]);
      expect(cells, hasLength(2));
      final byIntensity = cells.map((c) => c.intensity).toList()..sort();
      expect(byIntensity.last, 1.0);
      expect(byIntensity.first, closeTo(0.5, 0.0001)); // sqrt(25/100)
    });

    test('cell centroid is near the contributing points', () {
      final cells = heatCells([
        _tx(id: 'a', amount: 10, lat: 3.1390, lng: 101.6869),
      ]);
      expect(cells.single.lat, closeTo(3.1390, 0.05));
      expect(cells.single.lng, closeTo(101.6869, 0.05));
    });
  });

  group('mapCategories', () {
    test('always starts with All categories', () {
      expect(mapCategories(const []), ['All categories']);
    });

    test('orders distinct categories by spend, ignoring non-geo rows', () {
      final cats = mapCategories([
        _tx(id: 'a', amount: 10, lat: 3.1, lng: 101.6, category: 'Transport'),
        _tx(id: 'b', amount: 50, lat: 3.1, lng: 101.6, category: 'Groceries'),
        _tx(id: 'c', amount: 20, lat: 3.1, lng: 101.6, category: 'Groceries'),
        _tx(id: 'd', amount: 999, category: 'Shopping'), // no location
      ]);
      expect(cats, ['All categories', 'Groceries', 'Transport']);
    });

    test('falls back to Unclassified for rows without a category', () {
      final cats = mapCategories([
        _tx(id: 'a', amount: 10, lat: 3.1, lng: 101.6),
      ]);
      expect(cats, ['All categories', 'Unclassified']);
    });
  });

  group('mapClusters', () {
    test('dominantCategory is highest receipt count, not highest spend', () {
      // Two cheap Transport receipts beat one expensive Food receipt.
      final clusters = mapClusters([
        _tx(id: 'a', amount: 100, lat: 3.1390, lng: 101.6869, category: 'Food'),
        _tx(id: 'b', amount: 10, lat: 3.1390, lng: 101.6869, category: 'Transport'),
        _tx(id: 'c', amount: 10, lat: 3.1390, lng: 101.6869, category: 'Transport'),
      ]);
      expect(clusters, hasLength(1));
      expect(clusters.single.dominantCategory, 'Transport');
      expect(clusters.single.dominantCategoryCount, 2);
      expect(clusters.single.visitCount, 3);
    });

    test('tie on count is broken by most recent occurredAt', () {
      final clusters = mapClusters([
        _tx(
          id: 'a',
          amount: 10,
          lat: 3.1390,
          lng: 101.6869,
          category: 'Food',
          occurredAt: DateTime(2026, 7, 1),
        ),
        _tx(
          id: 'b',
          amount: 10,
          lat: 3.1390,
          lng: 101.6869,
          category: 'Transport',
          occurredAt: DateTime(2026, 7, 3),
        ),
      ]);
      expect(clusters.single.dominantCategory, 'Transport');
      expect(clusters.single.dominantCategoryCount, 1);
    });
  });

  group('bucketClusters', () {
    // a/b share a geohash-8 place cell (w283cgqn); c is a different place
    // cell (w283cgwg) but all three share the same geohash-5 bucket
    // (w283c), verified directly against geohashAt.
    test('counts receipts and distinct places per geohash bucket', () {
      final buckets = bucketClusters([
        _tx(id: 'a', amount: 10, lat: 3.1390, lng: 101.6869, category: 'Food'),
        _tx(id: 'b', amount: 20, lat: 3.1391, lng: 101.6870, category: 'Food'),
        _tx(id: 'c', amount: 5, lat: 3.1400, lng: 101.6880, category: 'Transport'),
      ], 5);
      expect(buckets, hasLength(1));
      expect(buckets.single.receiptCount, 3);
      expect(buckets.single.placeCount, 2);
      expect(buckets.single.dominantCategory, 'Food');
      expect(buckets.single.dominantCategoryCount, 2);
    });

    test('single-receipt bucket carries that receipt category', () {
      final buckets = bucketClusters([
        _tx(
          id: 'a',
          amount: 10,
          lat: 3.1390,
          lng: 101.6869,
          category: 'Groceries',
        ),
      ], 5);
      expect(buckets, hasLength(1));
      expect(buckets.single.receiptCount, 1);
      expect(buckets.single.dominantCategory, 'Groceries');
      expect(buckets.single.dominantCategoryCount, 1);
    });

    test('splits into separate buckets for far-apart points', () {
      final buckets = bucketClusters([
        _tx(id: 'a', amount: 10, lat: 3.1390, lng: 101.6869),
        _tx(id: 'b', amount: 10, lat: 5.4141, lng: 100.3288), // Penang
      ], 5);
      expect(buckets, hasLength(2));
    });

    test('empty input yields no buckets', () {
      expect(bucketClusters(const [], 5), isEmpty);
    });

    test('bucket lat/lng equal the single transaction coordinates, not the geohash cell midpoint', () {
      // Precision 3 cells are ~156km wide; the geometric cell midpoint is
      // far from any particular point inside the cell. Using the real
      // transaction coordinate keeps the bubble (and tap-to-zoom target)
      // on the pin the user actually sees.
      const lat = 3.1390;
      const lng = 101.6869;
      final buckets = bucketClusters([
        _tx(id: 'a', amount: 10, lat: lat, lng: lng),
      ], 3);
      expect(buckets, hasLength(1));
      expect(buckets.single.lat, lat);
      expect(buckets.single.lng, lng);
    });

    test('bucket lat/lng are the arithmetic mean of the transactions in the bucket', () {
      final buckets = bucketClusters([
        _tx(id: 'a', amount: 10, lat: 3.1390, lng: 101.6869),
        _tx(id: 'b', amount: 20, lat: 3.1410, lng: 101.6889),
      ], 5);
      expect(buckets, hasLength(1));
      expect(buckets.single.lat, closeTo((3.1390 + 3.1410) / 2, 1e-9));
      expect(buckets.single.lng, closeTo((101.6869 + 101.6889) / 2, 1e-9));
    });
  });

  group('zoomBucketPrecision', () {
    test('individual-pin precision at high zoom', () {
      expect(zoomBucketPrecision(16), individualPinPrecision);
      expect(zoomBucketPrecision(15), individualPinPrecision);
    });

    test('coarsens as zoom decreases', () {
      expect(zoomBucketPrecision(14), 6);
      expect(zoomBucketPrecision(12), 5);
      expect(zoomBucketPrecision(10), 4);
      expect(zoomBucketPrecision(8), 3);
      expect(zoomBucketPrecision(6), 2);
      expect(zoomBucketPrecision(3), 1);
    });
  });

  group('boundsChangedMaterially', () {
    const base = (minLat: 3.0, minLng: 101.0, maxLat: 3.2, maxLng: 101.2);

    test('identical bounds are not a material change', () {
      expect(boundsChangedMaterially(base, base), isFalse);
    });

    test('tiny settle-jitter is not a material change', () {
      const jittered = (
        minLat: 3.001,
        minLng: 101.001,
        maxLat: 3.201,
        maxLng: 101.201,
      );
      expect(boundsChangedMaterially(base, jittered), isFalse);
    });

    test('panning far away is a material change', () {
      const farAway = (
        minLat: 8.0,
        minLng: 106.0,
        maxLat: 8.2,
        maxLng: 106.2,
      );
      expect(boundsChangedMaterially(base, farAway), isTrue);
    });

    test('zooming out enough is a material change', () {
      const zoomedOut = (
        minLat: 2.0,
        minLng: 100.0,
        maxLat: 4.2,
        maxLng: 102.2,
      );
      expect(boundsChangedMaterially(base, zoomedOut), isTrue);
    });
  });

  group('expandBounds', () {
    const base = (minLat: 3.0, minLng: 101.0, maxLat: 3.2, maxLng: 101.2);

    test('expands span by the default 1.5x factor around the center', () {
      final expanded = expandBounds(base);
      expect(expanded.minLat, closeTo(2.95, 1e-9));
      expect(expanded.maxLat, closeTo(3.25, 1e-9));
      expect(expanded.minLng, closeTo(100.95, 1e-9));
      expect(expanded.maxLng, closeTo(101.25, 1e-9));
    });

    test('respects a custom factor', () {
      final expanded = expandBounds(base, factor: 2.0);
      expect(expanded.maxLat - expanded.minLat, closeTo(0.4, 1e-9));
      expect(expanded.maxLng - expanded.minLng, closeTo(0.4, 1e-9));
    });

    test('clamps latitude at the pole instead of exceeding 90', () {
      const nearPole = (minLat: 89.0, minLng: 101.0, maxLat: 89.9, maxLng: 101.2);
      final expanded = expandBounds(nearPole);
      expect(expanded.maxLat, lessThanOrEqualTo(90.0));
    });

    test('clamps longitude at the antimeridian instead of exceeding 180', () {
      const nearDateline = (minLat: 3.0, minLng: 179.0, maxLat: 3.2, maxLng: 179.9);
      final expanded = expandBounds(nearDateline);
      expect(expanded.maxLng, lessThanOrEqualTo(180.0));
    });

    test('never inverts min/max even when clamped', () {
      const nearDateline = (minLat: 3.0, minLng: 179.5, maxLat: 3.2, maxLng: 179.9);
      final expanded = expandBounds(nearDateline);
      expect(expanded.minLng, lessThanOrEqualTo(expanded.maxLng));
    });

    test('degenerate zero-span box stays zero-span (no divide-by-zero)', () {
      const point = (minLat: 3.1, minLng: 101.6, maxLat: 3.1, maxLng: 101.6);
      final expanded = expandBounds(point);
      expect(expanded.maxLat - expanded.minLat, 0.0);
      expect(expanded.maxLng - expanded.minLng, 0.0);
    });
  });
}
