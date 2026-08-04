import 'package:intl/intl.dart';

import '../models/transaction_view.dart';

/// Distinct categories across [items], highest-spend first — shared by
/// [HistoryDay.categories] and [HistoryWeek.categories].
List<String> _categoriesBySpend(List<TransactionView> items) {
  final totals = <String, double>{};
  for (final t in items) {
    totals.update(
      t.effectiveCategory,
      (v) => v + (t.amountMyr ?? 0),
      ifAbsent: () => t.amountMyr ?? 0,
    );
  }
  return (totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
      .map((e) => e.key)
      .toList();
}

/// One calendar day's receipts inside a [HistoryWeek].
class HistoryDay {
  const HistoryDay({required this.date, required this.label, required this.items});

  final DateTime date;
  final String label;
  final List<TransactionView> items;

  double get total => items.fold(0.0, (s, t) => s + (t.amountMyr ?? 0));

  /// Distinct categories, highest-spend first — for the day row's avatar stack.
  List<String> get categories => _categoriesBySpend(items);
}

/// One calendar week (Monday–Sunday), older than the current week, grouped
/// into its constituent [days].
class HistoryWeek {
  const HistoryWeek({required this.weekStart, required this.label, required this.days});

  final DateTime weekStart;
  final String label;
  final List<HistoryDay> days;

  List<TransactionView> get items => days.expand((d) => d.items).toList();
  int get count => items.length;
  double get total => items.fold(0.0, (s, t) => s + (t.amountMyr ?? 0));

  /// Distinct categories across the week, highest-spend first — mirrors
  /// [mapCategories]'s totals-then-sort approach in `dashboard_aggregates.dart`.
  List<String> get categories => _categoriesBySpend(items);
}

/// Everything the Receipt History screen needs to render: today's receipts
/// (always shown expanded), this week's total (for the summary card), and
/// older receipts bucketed into weeks-of-days.
class ReceiptHistoryData {
  const ReceiptHistoryData({
    required this.today,
    required this.thisWeekCount,
    required this.thisWeekTotal,
    required this.weeks,
  });

  final List<TransactionView> today;
  final int thisWeekCount;
  final double thisWeekTotal;
  final List<HistoryWeek> weeks;
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Monday of the calendar week containing [date].
DateTime weekStartFor(DateTime date) {
  final d = _dateOnly(date);
  return d.subtract(Duration(days: d.weekday - DateTime.monday));
}

/// Buckets [rows] into today / this-week-total / older weeks-of-days, newest
/// first throughout. [rows] is expected pre-sorted newest-first (as
/// `TransactionRepository.watchAll()` returns), but this doesn't rely on it.
ReceiptHistoryData buildReceiptHistory(List<TransactionView> rows, DateTime now) {
  final visible = rows.where((t) => t.includeInCharts).toList();
  final today = _dateOnly(now);
  final currentWeekStart = weekStartFor(now);
  final lastWeekStart = currentWeekStart.subtract(const Duration(days: 7));

  final todayItems = <TransactionView>[];
  final thisWeekItems = <TransactionView>[];
  final byWeek = <DateTime, Map<DateTime, List<TransactionView>>>{};

  for (final t in visible) {
    final d = _dateOnly(t.occurredAt);
    if (d == today) todayItems.add(t);
    final ws = weekStartFor(t.occurredAt);
    if (ws == currentWeekStart) thisWeekItems.add(t);
    if (ws.isBefore(currentWeekStart)) {
      byWeek.putIfAbsent(ws, () => {}).putIfAbsent(d, () => []).add(t);
    }
  }

  final weekStarts = byWeek.keys.toList()..sort((a, b) => b.compareTo(a));
  final weeks = weekStarts.map((ws) {
    final dayMap = byWeek[ws]!;
    final days = dayMap.keys.toList()..sort((a, b) => b.compareTo(a));
    final historyDays = days.map((d) {
      final items = dayMap[d]!
        ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
      return HistoryDay(
        date: d,
        label: DateFormat('EEEE · d/M').format(d),
        items: items,
      );
    }).toList();

    final weekEnd = ws.add(const Duration(days: 6));
    final rangeLabel = '${DateFormat('d/M').format(ws)} – ${DateFormat('d/M').format(weekEnd)}';
    final label = ws == lastWeekStart ? 'Last Week · $rangeLabel' : rangeLabel;

    return HistoryWeek(weekStart: ws, label: label, days: historyDays);
  }).toList();

  return ReceiptHistoryData(
    today: todayItems,
    thisWeekCount: thisWeekItems.length,
    thisWeekTotal: thisWeekItems.fold(0.0, (s, t) => s + (t.amountMyr ?? 0)),
    weeks: weeks,
  );
}
