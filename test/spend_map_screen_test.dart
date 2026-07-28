import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_drop/domain/models/transaction_view.dart';
import 'package:receipt_drop/features/map/spend_map_screen.dart';

TransactionView _tx({
  required String id,
  double? placeLat,
  double? placeLng,
  String syncStatus = 'synced',
}) {
  return TransactionView(
    id: id,
    occurredAt: DateTime(2026, 7, 28),
    amountMyr: 10,
    needsAmount: false,
    merchantRaw: 'Test Merchant',
    categoryGuess: 'Food & Drink',
    categoryUser: null,
    placeName: null,
    placeGooglePlaceId: null,
    placeLat: placeLat,
    placeLng: placeLng,
    syncStatus: syncStatus,
    pipelineStatus: 'provisional',
    localThumbnailPath: null,
  );
}

void main() {
  group('mapRelevantFingerprint', () {
    test('is stable across calls for the same rows', () {
      final rows = [
        _tx(id: 'a', placeLat: 3.1, placeLng: 101.6),
        _tx(id: 'b', placeLat: 3.2, placeLng: 101.7),
      ];
      expect(mapRelevantFingerprint(rows), mapRelevantFingerprint(rows));
    });

    test('ignores rows with no location', () {
      final withPlaceless = [
        _tx(id: 'a', placeLat: 3.1, placeLng: 101.6),
        _tx(id: 'b'), // no location
      ];
      final withoutPlaceless = [
        _tx(id: 'a', placeLat: 3.1, placeLng: 101.6),
      ];
      expect(
        mapRelevantFingerprint(withPlaceless),
        mapRelevantFingerprint(withoutPlaceless),
      );
    });

    test('changes when a new location-bearing transaction is added', () {
      final before = [_tx(id: 'a', placeLat: 3.1, placeLng: 101.6)];
      final after = [
        _tx(id: 'a', placeLat: 3.1, placeLng: 101.6),
        _tx(id: 'b', placeLat: 3.2, placeLng: 101.7),
      ];
      expect(
        mapRelevantFingerprint(before),
        isNot(mapRelevantFingerprint(after)),
      );
    });

    test('changes when a row\'s sync status transitions', () {
      final pending = [
        _tx(id: 'a', placeLat: 3.1, placeLng: 101.6, syncStatus: 'pending'),
      ];
      final synced = [
        _tx(id: 'a', placeLat: 3.1, placeLng: 101.6, syncStatus: 'synced'),
      ];
      expect(
        mapRelevantFingerprint(pending),
        isNot(mapRelevantFingerprint(synced)),
      );
    });

    test('changes when a location-bearing transaction is removed', () {
      final before = [
        _tx(id: 'a', placeLat: 3.1, placeLng: 101.6),
        _tx(id: 'b', placeLat: 3.2, placeLng: 101.7),
      ];
      final after = [_tx(id: 'a', placeLat: 3.1, placeLng: 101.6)];
      expect(
        mapRelevantFingerprint(before),
        isNot(mapRelevantFingerprint(after)),
      );
    });
  });
}
