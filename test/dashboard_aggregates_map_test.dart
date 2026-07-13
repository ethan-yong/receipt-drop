import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_drop/domain/logic/dashboard_aggregates.dart';
import 'package:receipt_drop/domain/models/transaction_view.dart';

TransactionView _tx({
  required String id,
  double? amount,
  double? lat,
  double? lng,
  String? category,
}) {
  return TransactionView.fromOutbox(
    id: id,
    occurredAt: DateTime(2026, 7, 1),
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
    test('computes dominantCategory once per place, highest spend wins', () {
      final clusters = mapClusters([
        _tx(id: 'a', amount: 100, lat: 3.1390, lng: 101.6869, category: 'Food'),
        _tx(id: 'b', amount: 10, lat: 3.1390, lng: 101.6869, category: 'Transport'),
      ]);
      expect(clusters, hasLength(1));
      expect(clusters.single.dominantCategory, 'Food');
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
    });

    test('splits into separate buckets for far-apart points', () {
      final buckets = bucketClusters([
        _tx(id: 'a', amount: 10, lat: 3.1390, lng: 101.6869),
        _tx(id: 'b', amount: 10, lat: 5.4141, lng: 100.3288), // Penang
      ], 5);
      expect(buckets, hasLength(2));
    });

    test('dominant category is the highest-spend category in the bucket', () {
      final buckets = bucketClusters([
        _tx(id: 'a', amount: 100, lat: 3.1390, lng: 101.6869, category: 'Food'),
        _tx(id: 'b', amount: 10, lat: 3.1391, lng: 101.6870, category: 'Transport'),
      ], 5);
      expect(buckets.single.dominantCategory, 'Food');
    });

    test('empty input yields no buckets', () {
      expect(bucketClusters(const [], 5), isEmpty);
    });
  });

  group('zoomBucketPrecision', () {
    test('individual-pin precision at high zoom', () {
      expect(zoomBucketPrecision(16), individualPinPrecision);
      expect(zoomBucketPrecision(15), individualPinPrecision);
    });

    test('coarsens as zoom decreases', () {
      expect(zoomBucketPrecision(13), 6);
      expect(zoomBucketPrecision(10), 5);
      expect(zoomBucketPrecision(7), 4);
      expect(zoomBucketPrecision(3), 3);
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
}
