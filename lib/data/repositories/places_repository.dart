import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/env.dart';
import '../../domain/logic/merchant_extractor.dart';

class PlaceResult {
  const PlaceResult({
    required this.id,
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
  });

  final String id;
  final String name;
  final String address;
  final double lat;
  final double lng;
}

/// A ranked nearby place candidate returned by the [places-proxy] edge
/// function's `nearby_candidates` mode.
class PlaceCandidate {
  const PlaceCandidate({
    required this.id,
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
    required this.distanceMeters,
    required this.confidence,
  });

  final String id;
  final String name;
  final String address;
  final double lat;
  final double lng;
  final double distanceMeters;
  final double confidence;

  PlaceResult toPlaceResult() =>
      PlaceResult(id: id, name: name, address: address, lat: lat, lng: lng);
}

/// Google Places search and nearby-candidate ranking via the
/// `places-proxy` Supabase Edge Function.
class PlacesRepository {
  PlacesRepository._();

  static Future<List<PlaceResult>> search(
    String query, {
    double? lat,
    double? lng,
  }) async {
    if (!Env.hasSupabaseConfig) return const [];
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    try {
      final body = <String, dynamic>{'query': trimmed};
      if (lat != null && lng != null) {
        body['lat'] = lat;
        body['lng'] = lng;
      }

      final response = await Supabase.instance.client.functions.invoke(
        'places-proxy',
        body: body,
      );

      if (response.status != 200) return const [];

      final data = response.data;
      if (data is! Map<String, dynamic>) return const [];
      final places = data['places'];
      if (places is! List) return const [];

      return places.map((raw) {
        final place = raw as Map<String, dynamic>;
        final displayName = place['displayName'];
        final name = displayName is Map
            ? displayName['text'] as String? ?? ''
            : displayName?.toString() ?? '';
        final location = place['location'] as Map<String, dynamic>?;
        final id = (place['id'] as String?) ?? '';
        return PlaceResult(
          id: id.replaceFirst('places/', ''),
          name: name,
          address: place['formattedAddress'] as String? ?? '',
          lat: (location?['latitude'] as num?)?.toDouble() ?? 0,
          lng: (location?['longitude'] as num?)?.toDouble() ?? 0,
        );
      }).where((p) => p.name.isNotEmpty).toList();
    } on Object {
      return const [];
    }
  }

  static Future<List<PlaceCandidate>> fetchNearbyCandidates({
    required double lat,
    required double lng,
    List<MerchantCandidate> candidates = const [],
    String? merchantName,
    String? category,
    int limit = 5,
  }) async {
    if (!Env.hasSupabaseConfig) return const [];
    try {
      final body = <String, dynamic>{
        'mode': 'nearby_candidates',
        'lat': lat,
        'lng': lng,
        'limit': limit,
      };
      if (candidates.isNotEmpty) {
        body['candidates'] = candidates
            .map((c) => {'text': c.text, 'confidence': c.confidence, 'source': c.source})
            .toList();
      }
      if (merchantName != null && merchantName.trim().isNotEmpty) {
        body['query'] = merchantName.trim();
      }
      if (category != null) body['category'] = category;

      final response = await Supabase.instance.client.functions.invoke(
        'places-proxy',
        body: body,
      );
      if (response.status != 200) return const [];

      final data = response.data;
      if (data is! Map<String, dynamic>) return const [];
      final raw = data['candidates'];
      if (raw is! List) return const [];

      return parseCandidates(raw);
    } on Object {
      return const [];
    }
  }

  /// Google Places photos of a venue (Google-Maps-style venue photos, not
  /// receipt scans), via the `places-proxy` Edge Function's `place_photos`
  /// mode — server-cached (`place_photos_cache` + the `place-photos` Storage
  /// bucket) so repeat calls for the same place don't re-hit Google's billed
  /// Photo Media endpoint. Returns an empty list on failure or when the
  /// place has no photos.
  ///
  /// The edge function returns Storage-relative paths (not absolute URLs) so
  /// Docker-internal hosts like `kong:8000` never leak to the device. We
  /// rebuild each public URL against this client's Supabase origin.
  static Future<List<String>> fetchPlacePhotos(String placeGooglePlaceId) async {
    if (!Env.hasSupabaseConfig || placeGooglePlaceId.trim().isEmpty) {
      return const [];
    }
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'places-proxy',
        body: {'mode': 'place_photos', 'placeId': placeGooglePlaceId},
      );
      if (response.status != 200) return const [];

      final data = response.data;
      if (data is! Map<String, dynamic>) return const [];
      final refs = data['photoUrls'];
      if (refs is! List) return const [];

      final storage = Supabase.instance.client.storage.from('place-photos');
      return refs
          .whereType<String>()
          .map((ref) => storage.getPublicUrl(_placePhotoStoragePath(ref)))
          .toList();
    } on Object {
      return const [];
    }
  }

  /// Normalizes an edge-function photo ref into a bucket-relative path.
  /// Accepts bare paths (`ChIJ…/0.jpg`) and any absolute public URL that
  /// already points at the `place-photos` bucket (stale cache entries).
  @visibleForTesting
  static String placePhotoStoragePath(String ref) => _placePhotoStoragePath(ref);

  static String _placePhotoStoragePath(String ref) {
    const marker = '/storage/v1/object/public/place-photos/';
    final idx = ref.indexOf(marker);
    if (idx >= 0) return ref.substring(idx + marker.length);
    if (ref.startsWith('place-photos/')) {
      return ref.substring('place-photos/'.length);
    }
    return ref;
  }

  /// Parses the raw `candidates` array from the `places-proxy` nearby response.
  /// Exposed for unit testing; callers should use [fetchNearbyCandidates].
  @visibleForTesting
  static List<PlaceCandidate> parseCandidates(List<dynamic> raw) {
    return raw
        .cast<Map<String, dynamic>>()
        .where((c) =>
            c['name'] != null &&
            (c['name'] as String).isNotEmpty &&
            c['lat'] != null &&
            c['lng'] != null)
        .map((c) => PlaceCandidate(
              id: (c['id'] as String?) ?? '',
              name: c['name'] as String,
              address: (c['address'] as String?) ?? '',
              lat: (c['lat'] as num).toDouble(),
              lng: (c['lng'] as num).toDouble(),
              distanceMeters:
                  (c['distanceMeters'] as num?)?.toDouble() ?? 0,
              confidence: (c['confidence'] as num?)?.toDouble() ?? 0,
            ))
        .toList();
  }
}
