import 'dart:math' as math;

import 'package:intl/intl.dart';

import '../models/transaction_view.dart';
import '../../core/utils/place_key.dart';

class MapPlaceCluster {
  const MapPlaceCluster({
    required this.placeKey,
    required this.displayName,
    required this.lat,
    required this.lng,
    required this.totalSpend,
    required this.visitCount,
    required this.transactions,
    required this.dominantCategory,
    required this.dominantCategoryCount,
  });

  final String placeKey;
  final String displayName;
  final double lat;
  final double lng;
  final double totalSpend;
  final int visitCount;
  final List<TransactionView> transactions;

  /// Category shown on the place pin: highest receipt *count* at this place;
  /// ties broken by the most recent [TransactionView.occurredAt] among the
  /// tied categories. Computed once in [mapClusters], not per marker frame.
  final String dominantCategory;

  /// Number of receipts in [dominantCategory] at this place — drives the
  /// pin's count badge (not [visitCount], which is the place total).
  final int dominantCategoryCount;
}

/// Coarser-than-place aggregation for zoomed-out map cluster bubbles (e.g.
/// "42 receipts"), bucketed by geohash cell instead of exact place identity.
class GeoBucket {
  const GeoBucket({
    required this.bucketKey,
    required this.lat,
    required this.lng,
    required this.receiptCount,
    required this.placeCount,
    required this.dominantCategory,
    required this.dominantCategoryCount,
  });

  final String bucketKey;
  final double lat;
  final double lng;
  final int receiptCount;
  final int placeCount;

  /// Same count+recency rule as [MapPlaceCluster.dominantCategory] — used when
  /// a bucket collapses to a single receipt so the pin can show that
  /// receipt's category emoji/border instead of a generic cluster face.
  final String dominantCategory;
  final int dominantCategoryCount;
}

/// Geohash precision at which a place-level cluster is itself the finest
/// grain the map ever shows (matches `effectivePlaceKey`'s geohash-8 fallback
/// in `place_key.dart`). At or above this, render individual place pins via
/// [mapClusters] instead of [bucketClusters].
const individualPinPrecision = 8;

/// Geohash precision to use for cluster bubbles at a given camera zoom.
/// Thresholds line up with standard geohash cell sizes: precision 8 (~38m,
/// individual place territory) down to precision 1 (~5,000km, country /
/// continent scale) so far-out zooms collapse into one or a few buckets.
int zoomBucketPrecision(double zoom) {
  if (zoom >= 15) return individualPinPrecision;
  if (zoom >= 13) return 6;
  if (zoom >= 11) return 5;
  if (zoom >= 9) return 4;
  if (zoom >= 7) return 3;
  if (zoom >= 5) return 2;
  return 1;
}

/// Lat/lng box, kept as a plain record (not `google_maps_flutter`'s
/// `LatLngBounds`) so this file stays free of Flutter/plugin dependencies.
typedef LatLngBox = ({
  double minLat,
  double minLng,
  double maxLat,
  double maxLng,
});

/// Whether the visible map region has moved enough since the last viewport
/// fetch to warrant a new one — guards against refetching on the tiny
/// settle-jitter that lands right at the `onCameraIdle` threshold.
bool boundsChangedMaterially(
  LatLngBox last,
  LatLngBox next, {
  double threshold = 0.3,
}) {
  final lastLatSpan = last.maxLat - last.minLat;
  final lastLngSpan = last.maxLng - last.minLng;
  if (lastLatSpan <= 0 || lastLngSpan <= 0) return true;

  final lastCenterLat = (last.minLat + last.maxLat) / 2;
  final lastCenterLng = (last.minLng + last.maxLng) / 2;
  final nextCenterLat = (next.minLat + next.maxLat) / 2;
  final nextCenterLng = (next.minLng + next.maxLng) / 2;
  final latDrift = (nextCenterLat - lastCenterLat).abs() / lastLatSpan;
  final lngDrift = (nextCenterLng - lastCenterLng).abs() / lastLngSpan;
  if (latDrift > threshold || lngDrift > threshold) return true;

  final nextLatSpan = next.maxLat - next.minLat;
  final nextLngSpan = next.maxLng - next.minLng;
  final latSpanRatio = nextLatSpan / lastLatSpan;
  final lngSpanRatio = nextLngSpan / lastLngSpan;
  if ((latSpanRatio - 1).abs() > threshold ||
      (lngSpanRatio - 1).abs() > threshold) {
    return true;
  }
  return false;
}

/// Expands a lat/lng box by [factor] around its own center, so a fetch
/// covers a margin beyond what's currently visible — a small pan afterward
/// already has data available instead of showing a loading gap. Clamped to
/// valid lat/lng ranges rather than wrapping at the poles/antimeridian, so
/// `minLat`/`minLng` never exceed `maxLat`/`maxLng` (required for the
/// bounding-box RPC query this feeds).
LatLngBox expandBounds(LatLngBox bounds, {double factor = 1.5}) {
  final latSpan = bounds.maxLat - bounds.minLat;
  final lngSpan = bounds.maxLng - bounds.minLng;
  final centerLat = (bounds.minLat + bounds.maxLat) / 2;
  final centerLng = (bounds.minLng + bounds.maxLng) / 2;
  final halfLat = (latSpan * factor) / 2;
  final halfLng = (lngSpan * factor) / 2;
  return (
    minLat: (centerLat - halfLat).clamp(-90.0, 90.0),
    minLng: (centerLng - halfLng).clamp(-180.0, 180.0),
    maxLat: (centerLat + halfLat).clamp(-90.0, 90.0),
    maxLng: (centerLng + halfLng).clamp(-180.0, 180.0),
  );
}

List<MapPlaceCluster> mapClusters(List<TransactionView> rows) {
  final map = <String, List<TransactionView>>{};
  for (final t in rows) {
    if (!t.includeInCharts) continue;
    final lat = t.placeLat;
    final lng = t.placeLng;
    if (lat == null || lng == null) continue;
    final key = effectivePlaceKey(t.placeGooglePlaceId, lat, lng);
    map.putIfAbsent(key, () => []).add(t);
  }
  return map.entries.map((e) {
    final txs = e.value;
    final lat = txs.first.placeLat!;
    final lng = txs.first.placeLng!;
    final total = txs.fold<double>(0, (a, t) => a + (t.amountMyr ?? 0));
    final dominant = _dominantCategoryByCount(txs);
    return MapPlaceCluster(
      placeKey: e.key,
      displayName: txs.first.displayPlace,
      lat: lat,
      lng: lng,
      totalSpend: total,
      visitCount: txs.length,
      transactions: txs,
      dominantCategory: dominant.category,
      dominantCategoryCount: dominant.count,
    );
  }).toList();
}

/// Highest receipt-count category; ties broken by the most recent
/// [TransactionView.occurredAt] among the tied categories.
({String category, int count}) _dominantCategoryByCount(
  List<TransactionView> txs,
) {
  if (txs.isEmpty) return (category: 'Unclassified', count: 0);

  final counts = <String, int>{};
  final latest = <String, DateTime>{};
  for (final t in txs) {
    final cat = t.effectiveCategory;
    counts.update(cat, (v) => v + 1, ifAbsent: () => 1);
    final prev = latest[cat];
    if (prev == null || t.occurredAt.isAfter(prev)) {
      latest[cat] = t.occurredAt;
    }
  }

  String? best;
  for (final entry in counts.entries) {
    if (best == null) {
      best = entry.key;
      continue;
    }
    final bestCount = counts[best]!;
    if (entry.value > bestCount) {
      best = entry.key;
    } else if (entry.value == bestCount) {
      final a = latest[entry.key]!;
      final b = latest[best]!;
      if (a.isAfter(b)) best = entry.key;
    }
  }
  return (category: best!, count: counts[best]!);
}

/// Groups geolocated rows into geohash-precision buckets for zoomed-out map
/// cluster bubbles — coarser than [mapClusters]' exact-place grouping.
/// Recompute only on zoom-bucket change or a materially-changed viewport
/// (see [boundsChangedMaterially]), never on every camera-move frame.
List<GeoBucket> bucketClusters(List<TransactionView> rows, int precision) {
  final buckets = <String, List<TransactionView>>{};
  for (final t in rows) {
    if (!t.includeInCharts) continue;
    final lat = t.placeLat;
    final lng = t.placeLng;
    if (lat == null || lng == null) continue;
    final key = geohashAt(lat, lng, precision);
    buckets.putIfAbsent(key, () => []).add(t);
  }
  return buckets.entries.map((e) {
    final txs = e.value;
    // Mean of the actual transaction coordinates — not the geohash cell's
    // geometric midpoint, which at coarse precision can be tens of km from
    // the real data and makes tap-to-zoom land far from the visible bubble.
    var latSum = 0.0;
    var lngSum = 0.0;
    for (final t in txs) {
      latSum += t.placeLat!;
      lngSum += t.placeLng!;
    }
    final placeKeys = <String>{
      for (final t in txs)
        effectivePlaceKey(t.placeGooglePlaceId, t.placeLat!, t.placeLng!),
    };
    final dominant = _dominantCategoryByCount(txs);
    return GeoBucket(
      bucketKey: e.key,
      lat: latSum / txs.length,
      lng: lngSum / txs.length,
      receiptCount: txs.length,
      placeCount: placeKeys.length,
      dominantCategory: dominant.category,
      dominantCategoryCount: dominant.count,
    );
  }).toList();
}

class HeatCell {
  const HeatCell({
    required this.geohash,
    required this.lat,
    required this.lng,
    required this.intensity,
  });

  final String geohash;
  final double lat;
  final double lng;

  /// 0..1, sqrt-scaled against the busiest cell so mid-spend cells stay
  /// visible instead of being washed out by one dominant hotspot.
  final double intensity;
}

/// Spend totals bucketed into geohash cells for the map's heat overlay.
List<HeatCell> heatCells(List<TransactionView> rows, {int precision = 5}) {
  final totals = <String, double>{};
  for (final t in rows) {
    final lat = t.placeLat;
    final lng = t.placeLng;
    if (lat == null || lng == null || t.amountMyr == null) continue;
    final cell = geohashAt(lat, lng, precision);
    totals[cell] = (totals[cell] ?? 0) + t.amountMyr!;
  }
  if (totals.isEmpty) return const [];

  final maxTotal = totals.values.reduce((a, b) => a > b ? a : b);
  return totals.entries.map((e) {
    final center = geohashCentroid(e.key);
    final ratio = maxTotal <= 0 ? 0.0 : e.value / maxTotal;
    return HeatCell(
      geohash: e.key,
      lat: center.lat,
      lng: center.lng,
      intensity: math.sqrt(ratio),
    );
  }).toList();
}

/// Category chip values for the map, derived from the geolocated rows in the
/// current time window (highest spend first) instead of a hardcoded list.
List<String> mapCategories(List<TransactionView> geoRows) {
  final totals = <String, double>{};
  for (final t in geoRows) {
    if (!t.includeInCharts) continue;
    if (t.placeLat == null || t.placeLng == null) continue;
    totals.update(
      t.effectiveCategory,
      (v) => v + (t.amountMyr ?? 0),
      ifAbsent: () => t.amountMyr ?? 0,
    );
  }
  final entries = totals.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return ['All categories', ...entries.map((e) => e.key)];
}

String dayGroupLabel(DateTime date, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final d = DateTime(date.year, date.month, date.day);
  final diff = today.difference(d).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return DateFormat('EEE, d MMM').format(date);
}
