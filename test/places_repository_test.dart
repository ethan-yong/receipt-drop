import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_drop/data/repositories/places_repository.dart';

void main() {
  group('PlacesRepository.parseCandidates', () {
    test('parses a valid list into PlaceCandidate objects', () {
      final raw = [
        {
          'id': 'places/abc123',
          'name': 'Mamak Corner',
          'address': '1 Jalan Test, KL',
          'lat': 3.1001,
          'lng': 101.6001,
          'distanceMeters': 45.0,
          'confidence': 0.9,
        },
        {
          'id': 'places/def456',
          'name': 'Restoran Nasi Lemak',
          'address': '2 Jalan Test, KL',
          'lat': 3.1002,
          'lng': 101.6002,
          'distanceMeters': 120.0,
          'confidence': 0.75,
        },
      ];

      final result = PlacesRepository.parseCandidates(raw);

      expect(result, hasLength(2));
      expect(result[0].id, 'places/abc123');
      expect(result[0].name, 'Mamak Corner');
      expect(result[0].address, '1 Jalan Test, KL');
      expect(result[0].lat, closeTo(3.1001, 0.0001));
      expect(result[0].lng, closeTo(101.6001, 0.0001));
      expect(result[0].distanceMeters, 45.0);
      expect(result[0].confidence, 0.9);
      expect(result[1].name, 'Restoran Nasi Lemak');
    });

    test('returns empty list for empty input', () {
      expect(PlacesRepository.parseCandidates([]), isEmpty);
    });

    test('filters out entries with empty name', () {
      final raw = [
        {
          'id': 'p1',
          'name': '',
          'address': '',
          'lat': 3.0,
          'lng': 101.0,
          'distanceMeters': 10.0,
          'confidence': 0.9,
        },
        {
          'id': 'p2',
          'name': 'Valid Place',
          'address': '',
          'lat': 3.0,
          'lng': 101.0,
          'distanceMeters': 20.0,
          'confidence': 0.8,
        },
      ];

      final result = PlacesRepository.parseCandidates(raw);

      expect(result, hasLength(1));
      expect(result[0].name, 'Valid Place');
    });

    test('filters out entries with null lat or lng', () {
      final raw = [
        {
          'id': 'p1',
          'name': 'No Lat',
          'lat': null,
          'lng': 101.0,
          'distanceMeters': 10.0,
          'confidence': 0.9,
        },
        {
          'id': 'p2',
          'name': 'No Lng',
          'lat': 3.0,
          'lng': null,
          'distanceMeters': 10.0,
          'confidence': 0.9,
        },
        {
          'id': 'p3',
          'name': 'Has Both',
          'lat': 3.0,
          'lng': 101.0,
          'distanceMeters': 20.0,
          'confidence': 0.8,
        },
      ];

      final result = PlacesRepository.parseCandidates(raw);

      expect(result, hasLength(1));
      expect(result[0].name, 'Has Both');
    });

    test('handles missing optional fields with safe defaults', () {
      final raw = [
        {'id': 'p1', 'name': 'Cafe', 'lat': 3.0, 'lng': 101.0},
      ];

      final result = PlacesRepository.parseCandidates(raw);

      expect(result, hasLength(1));
      expect(result[0].address, '');
      expect(result[0].distanceMeters, 0.0);
      expect(result[0].confidence, 0.0);
    });
  });

  group('PlaceCandidate.toPlaceResult', () {
    test('carries id, name, address, lat, lng into PlaceResult', () {
      const candidate = PlaceCandidate(
        id: 'ChIJabc',
        name: 'Test Cafe',
        address: '99 Jalan Test',
        lat: 3.1234,
        lng: 101.6789,
        distanceMeters: 55,
        confidence: 0.88,
      );

      final place = candidate.toPlaceResult();

      expect(place.id, 'ChIJabc');
      expect(place.name, 'Test Cafe');
      expect(place.address, '99 Jalan Test');
      expect(place.lat, 3.1234);
      expect(place.lng, 101.6789);
    });
  });
}
