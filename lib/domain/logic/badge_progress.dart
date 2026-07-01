import 'badge_catalog.dart';
import '../models/transaction_view.dart';

const _coffeeKeywords = ['coffee', 'cafe', 'starbucks', 'tealive', 'kopitiam', 'latte', 'boba'];

/// A catalog entry joined with the signed-in user's live progress, shared
/// between `badges_screen.dart` and `top_badges_grid.dart` so both compute
/// "earned" the same way.
typedef BadgeEntry = ({BadgeDef badge, int progress, bool earned});

List<BadgeEntry> computeBadgeEntries(BadgeCatalog catalog, List<TransactionView> rows) {
  return catalog.badges.map((b) {
    final progress = badgeProgress(b.id, rows);
    return (badge: b, progress: progress, earned: progress >= b.goal);
  }).toList();
}

/// One pure function per badge goal condition, mirroring
/// `dashboard_aggregates.dart`'s "pure functions over the transaction list"
/// pattern. Two goals (budget_buddy, smart_spender) describe features that
/// don't exist yet in this app (budgets, price comparison) and are honestly
/// stubbed at zero progress rather than faked.
int badgeProgress(String badgeId, List<TransactionView> rows) {
  switch (badgeId) {
    case 'savvy_shopper':
      return rows.where((t) => t.effectiveCategory == 'Others').length;
    case 'caffeine_club':
      return rows
          .where(
            (t) => _coffeeKeywords.any(
              (k) => (t.merchantRaw ?? '').toLowerCase().contains(k),
            ),
          )
          .length;
    case 'receipt_keeper':
      return rows.length;
    case 'budget_buddy':
      return 0;
    case 'streak_master':
      return longestDailyStreak(rows);
    case 'fuel_saver':
      return rows.where((t) => t.effectiveCategory == 'Transport').length;
    case 'explorer':
      return rows.map((t) => t.effectiveCategory).toSet().length;
    case 'early_bird':
      return rows.where((t) => t.occurredAt.hour < 9).length;
    case 'smart_spender':
      return 0;
    case 'category_master':
      return rows.where((t) => t.effectiveCategory != 'Unclassified').length;
    case 'no_spend_ninja':
      return currentNoSpendStreak(rows);
    case 'big_saver':
      return bestMonthTotal(rows).round();
    default:
      return 0;
  }
}

/// Longest run of consecutive calendar days containing at least one
/// transaction.
int longestDailyStreak(List<TransactionView> rows) {
  if (rows.isEmpty) return 0;
  final days = rows
      .map((t) => DateTime(t.occurredAt.year, t.occurredAt.month, t.occurredAt.day))
      .toSet()
      .toList()
    ..sort();

  var longest = 1;
  var current = 1;
  for (var i = 1; i < days.length; i++) {
    if (days[i].difference(days[i - 1]).inDays == 1) {
      current += 1;
      if (current > longest) longest = current;
    } else {
      current = 1;
    }
  }
  return longest;
}

/// Consecutive days up to (and including) yesterday with zero transactions.
int currentNoSpendStreak(List<TransactionView> rows) {
  final days = rows
      .map((t) => DateTime(t.occurredAt.year, t.occurredAt.month, t.occurredAt.day))
      .toSet();
  final today = DateTime.now();
  var streak = 0;
  var cursor = DateTime(today.year, today.month, today.day)
      .subtract(const Duration(days: 1));
  while (!days.contains(cursor)) {
    streak += 1;
    cursor = cursor.subtract(const Duration(days: 1));
    if (streak > 365) break; // guard against unbounded loop on empty history
  }
  return streak;
}

/// Consecutive days up to and including today (or, if nothing's logged yet
/// today, up to yesterday) with at least one transaction — the inverse of
/// [currentNoSpendStreak]. Denormalized onto `profiles.current_streak` to
/// rank the friend leaderboard, since friends' raw transactions are never
/// readable cross-user (see `SocialRepository`, migration
/// 20260626000003_leaderboard.sql).
int currentDailyStreak(List<TransactionView> rows) {
  final days = rows
      .map((t) => DateTime(t.occurredAt.year, t.occurredAt.month, t.occurredAt.day))
      .toSet();
  final today = DateTime.now();
  var cursor = DateTime(today.year, today.month, today.day);
  if (!days.contains(cursor)) {
    cursor = cursor.subtract(const Duration(days: 1));
    if (!days.contains(cursor)) return 0;
  }
  var streak = 0;
  while (days.contains(cursor)) {
    streak += 1;
    cursor = cursor.subtract(const Duration(days: 1));
    if (streak > 3650) break; // guard against unbounded loop on long history
  }
  return streak;
}

/// Highest total `amountMyr` tracked within any single calendar month.
double bestMonthTotal(List<TransactionView> rows) {
  final totals = <String, double>{};
  for (final t in rows) {
    if (!t.includeInCharts) continue;
    final key = '${t.occurredAt.year}-${t.occurredAt.month}';
    totals.update(key, (v) => v + (t.amountMyr ?? 0), ifAbsent: () => t.amountMyr ?? 0);
  }
  if (totals.isEmpty) return 0;
  return totals.values.reduce((a, b) => a > b ? a : b);
}
