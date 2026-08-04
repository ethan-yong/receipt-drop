import '../models/insight_candidate.dart';
import '../models/transaction_view.dart';
import '../../core/utils/place_key.dart';
import 'badge_progress.dart';

/// Minimum category confidence for rows without a user-confirmed category.
/// Rows with [TransactionView.categoryUser] set always pass regardless.
const kMinCategoryConfidenceForInsights = 0.4;

/// Spike multiplier vs weekday baseline before emitting.
const kSpikeMultiplierThreshold = 2.0;

/// Minimum historical samples per weekday for a reliable baseline.
const kMinWeekdayBaselineSamples = 3;

/// Minimum absolute week-over-week category delta (MYR) to emit a shift.
const kMinCategoryShiftAmount = 20.0;

/// Minimum relative week-over-week category delta to emit a shift.
const kMinCategoryShiftRatio = 0.4;

/// Visits to the same place within [kHabitWindowDays] to emit a habit.
const kHabitMinVisits = 3;
const kHabitWindowDays = 7;

/// Minimum streak days before the streak agent fires (not day 1).
const kMinStreakDays = 3;

/// Minimum absolute projected overshoot vs prior month to emit a forecast.
const kMinForecastDeltaMyr = 30.0;

/// Minimum relative projected overshoot vs prior month.
const kMinForecastDeltaRatio = 0.15;

/// Filters rows the detectors may use — charts inclusion + optional confidence gate.
List<TransactionView> insightEligibleRows(
  List<TransactionView> rows, {
  double minCategoryConfidence = kMinCategoryConfidenceForInsights,
}) {
  return rows.where((t) {
    if (!t.includeInCharts) return false;
    if (t.pipelineStatus == 'needs_review') return false;
    final userCat = t.categoryUser?.trim();
    if (userCat != null && userCat.isNotEmpty) return true;
    final conf = t.categoryConfidence;
    if (conf == null) return true; // unknown confidence: keep (legacy rows)
    return conf >= minCategoryConfidence;
  }).toList();
}

/// Runs all five detectors and returns a severity-sorted candidate pool.
List<InsightCandidate> detectInsightCandidates(
  List<TransactionView> rows, {
  DateTime? now,
  Set<String> suppressedFactKeys = const {},
}) {
  final clock = now ?? DateTime.now();
  final eligible = insightEligibleRows(rows);
  final pool = <InsightCandidate>[
    ...detectSpendingSpikes(eligible, now: clock),
    ...detectCategoryShifts(eligible, now: clock),
    ...detectHabits(eligible, now: clock),
    ...detectStreakMotivation(eligible, now: clock),
    ...detectForecast(eligible, now: clock),
  ];
  final filtered = [
    for (final c in pool)
      if (!suppressedFactKeys.contains(c.factKey)) c,
  ];
  filtered.sort((a, b) => b.severity.compareTo(a.severity));
  return filtered;
}

// ---------------------------------------------------------------------------
// Supporting aggregates
// ---------------------------------------------------------------------------

/// Average spend for each weekday (DateTime.weekday 1=Mon … 7=Sun), using
/// all rows strictly before [before] (exclusive). Only weekdays with at least
/// [kMinWeekdayBaselineSamples] samples are included.
Map<int, double> weekdaySpendBaselines(
  List<TransactionView> rows, {
  required DateTime before,
}) {
  final sums = <int, double>{};
  final counts = <int, int>{};
  for (final t in rows) {
    if (!t.includeInCharts) continue;
    if (!t.occurredAt.isBefore(before)) continue;
    final wd = t.occurredAt.weekday;
    sums[wd] = (sums[wd] ?? 0) + (t.amountMyr ?? 0);
    counts[wd] = (counts[wd] ?? 0) + 1;
  }
  final result = <int, double>{};
  for (final e in sums.entries) {
    final n = counts[e.key] ?? 0;
    if (n >= kMinWeekdayBaselineSamples) {
      result[e.key] = e.value / n;
    }
  }
  return result;
}

/// Category totals for the calendar week containing [anchor] (Mon–Sun local).
Map<String, double> categoryTotalsForWeek(
  List<TransactionView> rows,
  DateTime anchor,
) {
  final monday = _mondayOf(anchor);
  final nextMonday = monday.add(const Duration(days: 7));
  final map = <String, double>{};
  for (final t in rows) {
    if (!t.includeInCharts) continue;
    if (t.occurredAt.isBefore(monday) || !t.occurredAt.isBefore(nextMonday)) {
      continue;
    }
    map.update(
      t.effectiveCategory,
      (v) => v + (t.amountMyr ?? 0),
      ifAbsent: () => t.amountMyr ?? 0,
    );
  }
  return map;
}

/// Place visit counts within the last [windowDays] ending at [now].
List<({String placeKey, String displayName, int visits, double total})>
    placeVisitFrequency(
  List<TransactionView> rows, {
  required DateTime now,
  int windowDays = kHabitWindowDays,
}) {
  final start = DateTime(now.year, now.month, now.day)
      .subtract(Duration(days: windowDays - 1));
  final map = <String, ({String name, int visits, double total})>{};
  for (final t in rows) {
    if (!t.includeInCharts) continue;
    if (t.occurredAt.isBefore(start)) continue;
    final lat = t.placeLat;
    final lng = t.placeLng;
    final String key;
    if (lat != null && lng != null) {
      key = effectivePlaceKey(t.placeGooglePlaceId, lat, lng);
    } else {
      final name = t.displayPlace;
      if (name == 'No place') continue;
      key = 'name:${name.toLowerCase()}';
    }
    final existing = map[key];
    map[key] = (
      name: t.displayPlace,
      visits: (existing?.visits ?? 0) + 1,
      total: (existing?.total ?? 0) + (t.amountMyr ?? 0),
    );
  }
  return [
    for (final e in map.entries)
      (
        placeKey: e.key,
        displayName: e.value.name,
        visits: e.value.visits,
        total: e.value.total,
      ),
  ]..sort((a, b) => b.visits.compareTo(a.visits));
}

/// Projects end-of-month spend from the current pace vs prior month total.
({double projected, double priorTotal, double currentTotal, double ratio})?
    monthPaceForecast(
  List<TransactionView> rows,
  DateTime now,
) {
  final start = DateTime(now.year, now.month);
  final end = DateTime(now.year, now.month + 1);
  final prevStart = DateTime(now.year, now.month - 1);
  final daysInMonth = end.difference(start).inDays;
  final elapsed = now.difference(start).inDays + 1;
  if (elapsed < 3 || daysInMonth <= 0) return null;

  double sumRange(DateTime from, DateTime to) => rows
      .where(
        (t) =>
            t.includeInCharts &&
            !t.occurredAt.isBefore(from) &&
            t.occurredAt.isBefore(to),
      )
      .fold(0.0, (a, t) => a + (t.amountMyr ?? 0));

  final current = sumRange(start, end);
  final prior = sumRange(prevStart, start);
  if (prior <= 0 || current <= 0) return null;

  final projected = (current / elapsed) * daysInMonth;
  return (
    projected: projected,
    priorTotal: prior,
    currentTotal: current,
    ratio: projected / prior,
  );
}

DateTime _mondayOf(DateTime d) {
  final day = DateTime(d.year, d.month, d.day);
  return day.subtract(Duration(days: day.weekday - 1));
}

String _dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

const _weekdayNames = {
  1: 'Monday',
  2: 'Tuesday',
  3: 'Wednesday',
  4: 'Thursday',
  5: 'Friday',
  6: 'Saturday',
  7: 'Sunday',
};

// ---------------------------------------------------------------------------
// Detectors
// ---------------------------------------------------------------------------

/// Spending Spike: today's (or recent calendar day's) spend vs weekday baseline.
List<InsightCandidate> detectSpendingSpikes(
  List<TransactionView> rows, {
  required DateTime now,
}) {
  final todayStart = DateTime(now.year, now.month, now.day);
  final todayRows = rows.where((t) {
    final d = DateTime(t.occurredAt.year, t.occurredAt.month, t.occurredAt.day);
    return d == todayStart;
  }).toList();
  if (todayRows.isEmpty) return const [];

  final todayTotal =
      todayRows.fold<double>(0, (a, t) => a + (t.amountMyr ?? 0));
  if (todayTotal <= 0) return const [];

  final baselines = weekdaySpendBaselines(rows, before: todayStart);
  final baseline = baselines[now.weekday];
  if (baseline == null || baseline <= 0) return const [];

  final multiplier = todayTotal / baseline;
  if (multiplier < kSpikeMultiplierThreshold) return const [];

  final weekdayName = _weekdayNames[now.weekday] ?? 'day';
  final severity = ((multiplier - kSpikeMultiplierThreshold) / 3).clamp(0.3, 1.0);
  return [
    InsightCandidate(
      type: 'spending_spike',
      factKey: 'spike:${now.weekday}:${_dayKey(todayStart)}',
      facts: {
        'weekday': weekdayName,
        'today_total': double.parse(todayTotal.toStringAsFixed(2)),
        'baseline': double.parse(baseline.toStringAsFixed(2)),
        'multiplier': double.parse(multiplier.toStringAsFixed(1)),
      },
      severity: severity,
      templateHint:
          'Today\'s spend is ${multiplier.toStringAsFixed(1)}x your usual $weekdayName',
    ),
  ];
}

/// Category Shift: week-over-week category spend change.
List<InsightCandidate> detectCategoryShifts(
  List<TransactionView> rows, {
  required DateTime now,
}) {
  final thisWeek = categoryTotalsForWeek(rows, now);
  final lastWeek = categoryTotalsForWeek(
    rows,
    now.subtract(const Duration(days: 7)),
  );
  if (thisWeek.isEmpty || lastWeek.isEmpty) return const [];

  final candidates = <InsightCandidate>[];
  final categories = {...thisWeek.keys, ...lastWeek.keys};
  for (final cat in categories) {
    if (cat == 'Unclassified') continue;
    final cur = thisWeek[cat] ?? 0;
    final prev = lastWeek[cat] ?? 0;
    if (prev <= 0) continue;
    final delta = cur - prev;
    final ratio = (delta.abs() / prev);
    if (delta.abs() < kMinCategoryShiftAmount) continue;
    if (ratio < kMinCategoryShiftRatio) continue;

    final direction = delta > 0 ? 'up' : 'down';
    final pct = (ratio * 100).round();
    final monday = _mondayOf(now);
    candidates.add(
      InsightCandidate(
        type: 'category_shift',
        factKey: 'shift:$cat:${_dayKey(monday)}',
        facts: {
          'category': cat,
          'direction': direction,
          'this_week': double.parse(cur.toStringAsFixed(2)),
          'last_week': double.parse(prev.toStringAsFixed(2)),
          'percent_change': pct,
        },
        severity: (ratio).clamp(0.3, 1.0),
        templateHint: '$cat is $direction $pct% vs last week',
      ),
    );
  }
  candidates.sort((a, b) => b.severity.compareTo(a.severity));
  return candidates.take(2).toList();
}

/// Habit: same place visited N+ times in the last week.
List<InsightCandidate> detectHabits(
  List<TransactionView> rows, {
  required DateTime now,
}) {
  final places = placeVisitFrequency(rows, now: now);
  final candidates = <InsightCandidate>[];
  for (final p in places) {
    if (p.visits < kHabitMinVisits) continue;
    candidates.add(
      InsightCandidate(
        type: 'habit',
        factKey: 'habit:${p.placeKey}:${_dayKey(DateTime(now.year, now.month, now.day))}',
        facts: {
          'place_name': p.displayName,
          'visits': p.visits,
          'window_days': kHabitWindowDays,
          'total_spend': double.parse(p.total.toStringAsFixed(2)),
        },
        severity: ((p.visits - kHabitMinVisits + 1) / 5).clamp(0.3, 0.9),
        templateHint:
            'You visited ${p.displayName} ${p.visits} times in the last $kHabitWindowDays days',
      ),
    );
  }
  return candidates.take(2).toList();
}

/// Streak / Motivation: celebrate a meaningful logging streak.
List<InsightCandidate> detectStreakMotivation(
  List<TransactionView> rows, {
  required DateTime now,
}) {
  final streak = currentDailyStreak(rows);
  if (streak < kMinStreakDays) return const [];

  // Milestone-ish severity bumps at 3, 7, 14, 30.
  final severity = streak >= 30
      ? 0.95
      : streak >= 14
          ? 0.8
          : streak >= 7
              ? 0.65
              : 0.45;

  return [
    InsightCandidate(
      type: 'streak',
      factKey: 'streak:$streak:${_dayKey(DateTime(now.year, now.month, now.day))}',
      facts: {
        'streak_days': streak,
      },
      severity: severity,
      templateHint: 'You\'ve logged receipts $streak days in a row',
    ),
  ];
}

/// Forecast: current-month pace projects meaningfully above prior month.
List<InsightCandidate> detectForecast(
  List<TransactionView> rows, {
  required DateTime now,
}) {
  final pace = monthPaceForecast(rows, now);
  if (pace == null) return const [];
  if (pace.ratio < 1 + kMinForecastDeltaRatio) return const [];
  final overshoot = pace.projected - pace.priorTotal;
  if (overshoot < kMinForecastDeltaMyr) return const [];

  final pct = ((pace.ratio - 1) * 100).round();
  return [
    InsightCandidate(
      type: 'forecast',
      factKey: 'forecast:${now.year}-${now.month.toString().padLeft(2, '0')}',
      facts: {
        'projected': double.parse(pace.projected.toStringAsFixed(2)),
        'prior_month': double.parse(pace.priorTotal.toStringAsFixed(2)),
        'current_so_far': double.parse(pace.currentTotal.toStringAsFixed(2)),
        'percent_over': pct,
      },
      severity: ((pace.ratio - 1) / 0.5).clamp(0.3, 0.95),
      templateHint:
          'At this pace you\'re heading ~$pct% above last month\'s total',
    ),
  ];
}

/// Non-LLM fallback: turn the top candidates into template strings for soft-launch.
List<CuratedInsight> templateCurate(
  List<InsightCandidate> candidates, {
  int maxInsights = 3,
  DateTime? now,
}) {
  final clock = now ?? DateTime.now();
  final selected = candidates.take(maxInsights).toList();
  return [
    for (var i = 0; i < selected.length; i++)
      CuratedInsight(
        id: 'local-${selected[i].factKey.hashCode.abs()}-$i',
        type: selected[i].type,
        factKey: selected[i].factKey,
        body: selected[i].templateHint ??
            'Something interesting about your spending',
        rank: i,
        createdAt: clock,
      ),
  ];
}
