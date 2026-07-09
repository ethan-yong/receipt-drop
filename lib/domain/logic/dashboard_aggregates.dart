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
  });

  final String placeKey;
  final String displayName;
  final double lat;
  final double lng;
  final double totalSpend;
  final int visitCount;
  final List<TransactionView> transactions;
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
