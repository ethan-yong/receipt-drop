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
