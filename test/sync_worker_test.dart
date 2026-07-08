import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_drop/data/repositories/sync_worker_flutter.dart';

void main() {
  group('buildEnrichmentCompanion', () {
    test('maps a fully-populated enriched row', () {
      final companion = buildEnrichmentCompanion({
        'place_name': 'Restoran Anwar Maju',
        'place_google_place_id': 'ChIJ123',
        'place_lat': 3.139,
        'place_lng': 101.6869,
        'place_confidence': 0.93,
        'place_status': 'guess',
        'merchant_normalized': 'Restoran Anwar Maju',
        'pipeline_status': 'enriched',
      });

      expect(companion.placeName.value, 'Restoran Anwar Maju');
      expect(companion.placeGooglePlaceId.value, 'ChIJ123');
      expect(companion.placeLat.value, 3.139);
      expect(companion.placeLng.value, 101.6869);
      expect(companion.placeConfidence.value, 0.93);
      expect(companion.placeStatus.value, 'guess');
      expect(companion.merchantNormalized.value, 'Restoran Anwar Maju');
      expect(companion.pipelineStatus.value, 'enriched');
    });

    test('coerces integer lat/lng/confidence without throwing', () {
      // Postgrest can serialize a whole-number numeric column as an int
      // (e.g. lat exactly 3) rather than a double.
      final companion = buildEnrichmentCompanion({
        'place_name': 'Somewhere',
        'place_lat': 3,
        'place_lng': 101,
        'place_confidence': 1,
        'place_status': 'guess',
        'pipeline_status': 'enriched',
      });
      expect(companion.placeLat.value, 3.0);
      expect(companion.placeLng.value, 101.0);
      expect(companion.placeConfidence.value, 1.0);
    });

    test('defaults place_status and pipeline_status when null', () {
      final companion = buildEnrichmentCompanion({
        'place_name': null,
        'place_status': null,
        'pipeline_status': null,
      });
      expect(companion.placeStatus.value, 'none');
      expect(companion.pipelineStatus.value, 'provisional');
    });

    test('maps a failed-enrichment row with no place fields', () {
      final companion = buildEnrichmentCompanion({
        'place_name': null,
        'place_google_place_id': null,
        'place_lat': null,
        'place_lng': null,
        'place_confidence': null,
        'place_status': 'none',
        'merchant_normalized': 'Some Merchant',
        'pipeline_status': 'failed_enrichment',
      });
      expect(companion.placeName.value, isNull);
      expect(companion.placeLat.value, isNull);
      expect(companion.pipelineStatus.value, 'failed_enrichment');
      expect(companion.merchantNormalized.value, 'Some Merchant');
    });
  });
}
