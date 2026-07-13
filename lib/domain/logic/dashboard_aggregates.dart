import 'dart:math' as math;

import 'package:intl/intl.dart';

import '../models/transaction_view.dart';
import '../../core/utils/place_key.dart';

class MonthSummary {
  const MonthSummary({
    required this.total,
    required this.deltaPercent,
    required this.hasPreviousMonth,
  });

  final double total;
  final double? deltaPercent;
  final bool hasPreviousMonth;
}

class CategorySlice {
  const CategorySlice({
    required this.category,
    required this.amount,
    required this.colorIndex,
  });

  final String category;
  final double amount;
  final int colorIndex;
}

class WeekPoint {
  const WeekPoint({required this.label, required this.amount});

  final String label;
  final double amount;
}

class TopPlaceRow {
  const TopPlaceRow({
    required this.displayName,
    required this.visitCount,
    required this.totalSpend,
    required this.placeKey,
  });

  final String displayName;
  final int visitCount;
  final double totalSpend;
  final String placeKey;
}

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
  });

  final String placeKey;
  final String displayName;
  final double lat;
  final double lng;
  final double totalSpend;
  final int visitCount;
  final List<TransactionView> transactions;

  /// Highest-spend category among this place's transactions, computed once
  /// here rather than per marker per animation frame.
  final String dominantCategory;
}

/// Coarser-than-place aggregation for zoomed-out map cluster bubbles (e.g.
/// "42 receipts" / "15 places"), bucketed by geohash cell instead of exact
/// place identity.
class GeoBucket {
  const GeoBucket({
    required this.bucketKey,
    required this.lat,
    required this.lng,
    required this.receiptCount,
    required this.placeCount,
    required this.dominantCategory,
  });

  final String bucketKey;
  final double lat;
  final double lng;
  final int receiptCount;
  final int placeCount;
  final String dominantCategory;
}

/// Geohash precision at which a place-level cluster is itself the finest
/// grain the map ever shows (matches `effectivePlaceKey`'s geohash-8 fallback
/// in `place_key.dart`). At or above this, render individual place pins via
/// [mapClusters] instead of [bucketClusters].
const individualPinPrecision = 8;

/// Geohash precision to use for cluster bubbles at a given camera zoom.
/// Thresholds line up with standard geohash cell sizes: precision 8 (~38m,
/// individual place territory) down to precision 3 (~156km, country-scale).
int zoomBucketPrecision(double zoom) {
  if (zoom >= 15) return individualPinPrecision;
  if (zoom >= 12) return 6;
  if (zoom >= 9) return 5;
  if (zoom >= 6) return 4;
  return 3;
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

MonthSummary monthSummary(
  List<TransactionView> rows,
  DateTime month,
) {
  final start = DateTime(month.year, month.month);
  final end = DateTime(month.year, month.month + 1);
  final prevStart = DateTime(month.year, month.month - 1);
  final prevEnd = start;

  double sumRange(DateTime from, DateTime to) {
    return rows
        .where(
          (t) =>
              t.includeInCharts &&
              !t.occurredAt.isBefore(from) &&
              t.occurredAt.isBefore(to),
        )
        .fold(0.0, (a, t) => a + (t.amountMyr ?? 0));
  }

  final current = sumRange(start, end);
  final previous = sumRange(prevStart, prevEnd);
  double? delta;
  if (previous > 0) {
    delta = ((current - previous) / previous) * 100;
  }
  return MonthSummary(
    total: current,
    deltaPercent: delta,
    hasPreviousMonth: previous > 0,
  );
}

List<CategorySlice> categoryBreakdown(
  List<TransactionView> rows,
  DateTime month,
) {
  final start = DateTime(month.year, month.month);
  final end = DateTime(month.year, month.month + 1);
  final map = <String, double>{};
  for (final t in rows) {
    if (!t.includeInCharts) continue;
    if (t.occurredAt.isBefore(start) || !t.occurredAt.isBefore(end)) {
      continue;
    }
    map.update(
      t.effectiveCategory,
      (v) => v + (t.amountMyr ?? 0),
      ifAbsent: () => t.amountMyr ?? 0,
    );
  }
  final entries = map.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return List.generate(
    entries.length,
    (i) => CategorySlice(
      category: entries[i].key,
      amount: entries[i].value,
      colorIndex: i,
    ),
  );
}

List<WeekPoint> weeklyTrend(
  List<TransactionView> rows,
  DateTime month,
) {
  final start = DateTime(month.year, month.month);
  final end = DateTime(month.year, month.month + 1);
  final filtered = rows.where((t) {
    return t.includeInCharts &&
        !t.occurredAt.isBefore(start) &&
        t.occurredAt.isBefore(end);
  }).toList();

  final buckets = <int, double>{};
  for (final t in filtered) {
    final week = ((t.occurredAt.day - 1) ~/ 7);
    buckets.update(week, (v) => v + (t.amountMyr ?? 0), ifAbsent: () => t.amountMyr ?? 0);
  }
  final keys = buckets.keys.toList()..sort();
  return keys
      .map(
        (w) => WeekPoint(
          label: 'W${w + 1}',
          amount: buckets[w]!,
        ),
      )
      .toList();
}

List<TopPlaceRow> topPlaces(
  List<TransactionView> rows,
  DateTime month,
) {
  final start = DateTime(month.year, month.month);
  final end = DateTime(month.year, month.month + 1);
  final map = <String, ({String name, double total, int count})>{};

  for (final t in rows) {
    if (!t.includeInCharts) continue;
    if (t.occurredAt.isBefore(start) || !t.occurredAt.isBefore(end)) {
      continue;
    }
    final lat = t.placeLat;
    final lng = t.placeLng;
    if (lat == null || lng == null) continue;
    final key = effectivePlaceKey(t.placeGooglePlaceId, lat, lng);
    final existing = map[key];
    map[key] = (
      name: t.displayPlace,
      total: (existing?.total ?? 0) + (t.amountMyr ?? 0),
      count: (existing?.count ?? 0) + 1,
    );
  }

  final list = map.entries
      .map(
        (e) => TopPlaceRow(
          placeKey: e.key,
          displayName: e.value.name,
          visitCount: e.value.count,
          totalSpend: e.value.total,
        ),
      )
      .toList()
    ..sort((a, b) => b.totalSpend.compareTo(a.totalSpend));
  return list.take(5).toList();
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
    return MapPlaceCluster(
      placeKey: e.key,
      displayName: txs.first.displayPlace,
      lat: lat,
      lng: lng,
      totalSpend: total,
      visitCount: txs.length,
      transactions: txs,
      dominantCategory: _dominantCategory(txs),
    );
  }).toList();
}

String _dominantCategory(List<TransactionView> txs) {
  final totals = <String, double>{};
  for (final t in txs) {
    totals.update(
      t.effectiveCategory,
      (v) => v + (t.amountMyr ?? 0),
      ifAbsent: () => t.amountMyr ?? 0,
    );
  }
  if (totals.isEmpty) return 'Unclassified';
  return totals.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
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
    final center = geohashCentroid(e.key);
    final placeKeys = <String>{
      for (final t in txs)
        effectivePlaceKey(t.placeGooglePlaceId, t.placeLat!, t.placeLng!),
    };
    return GeoBucket(
      bucketKey: e.key,
      lat: center.lat,
      lng: center.lng,
      receiptCount: txs.length,
      placeCount: placeKeys.length,
      dominantCategory: _dominantCategory(txs),
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
