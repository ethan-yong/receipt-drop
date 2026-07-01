import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/env.dart';

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

/// Google Places search via the `places-proxy` Supabase Edge Function.
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
}
