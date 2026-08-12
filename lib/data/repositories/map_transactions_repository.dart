import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/env.dart';
import '../../domain/models/receipt_line_item.dart';
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
          lineItems: _parseLineItems(row['line_items']),
          remoteStoragePath: row['receipt_storage_path'] as String?,
        );
      }).toList();
    } on Object {
      return null;
    }
  }

  /// Parses the RPC's `line_items` jsonb array (`[]` when the receipt has
  /// none) into domain models. Returns `null`, not an empty list, when the
  /// column itself is absent so `TransactionView.lineItems == null` still
  /// distinguishes "not fetched" from "fetched, genuinely empty" elsewhere.
  static List<ReceiptLineItem>? _parseLineItems(Object? raw) {
    if (raw is! List) return null;
    return raw
        .cast<Map<String, dynamic>>()
        .map((r) => ReceiptLineItem(
              // Present after 20260812140000; null on older RPC payloads.
              id: r['id'] as String?,
              name: r['name'] as String,
              priceMyr: (r['price_myr'] as num).toDouble(),
              quantity: (r['quantity'] as num?)?.toInt(),
            ))
        .toList();
  }
}
