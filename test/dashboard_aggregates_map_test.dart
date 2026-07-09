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
}
