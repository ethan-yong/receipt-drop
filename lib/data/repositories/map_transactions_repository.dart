import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/env.dart';
import '../../domain/models/transaction_view.dart';

/// Viewport-bounded spend transactions for the map, backed by the
/// `get_map_transactions_in_bounds` PostGIS RPC — fetched only on
/// `onCameraIdle`, never during a drag, so the map's own-place clustering
/// scales with what's visible instead of the user's entire history.
class MapTransactionsRepository {
  static String? get _userId =>
      Env.hasSupabaseConfig ? Supabase.instance.client.auth.currentUser?.id : null;

  /// Returns `null` on failure (e.g. offline) rather than an empty list, so
  /// the caller can tell "fetch failed, keep last-known-good clusters" apart
  /// from "fetch succeeded, this viewport genuinely has no spend here."
  static Future<List<TransactionView>?> fetchInBounds({
    required double minLat,
    required double minLng,
    required double maxLat,
    required double maxLng,
    required DateTime startAt,
    required DateTime endAt,
    String? category,
  }) async {
    if (_userId == null) return const [];
    try {
      final rows = await Supabase.instance.client.rpc(
        'get_map_transactions_in_bounds',
        params: {
          'min_lat': minLat,
          'min_lng': minLng,
          'max_lat': maxLat,
          'max_lng': maxLng,
          'start_at': startAt.toIso8601String(),
          'end_at': endAt.toIso8601String(),
          'category': category,
        },
      ) as List;
      return rows.map((r) {
        final row = r as Map<String, dynamic>;
        return TransactionView.fromOutbox(
          id: row['id'] as String,
          occurredAt: DateTime.parse(row['occurred_at'] as String),
          amountMyr: (row['amount_myr'] as num?)?.toDouble(),
          needsAmount: false,
          merchantRaw: row['merchant_raw'] as String?,
          categoryGuess: row['category_guess'] as String?,
          categoryUser: row['category_user'] as String?,
          placeName: row['place_name'] as String?,
          placeGooglePlaceId: row['place_google_place_id'] as String?,
          placeLat: (row['lat'] as num?)?.toDouble(),
          placeLng: (row['lng'] as num?)?.toDouble(),
          syncStatus: 'synced',
          pipelineStatus: 'enriched',
        );
      }).toList();
    } on Object {
      return null;
    }
  }
}
