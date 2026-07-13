import 'badge_catalog.dart';
import '../models/transaction_view.dart';

const _coffeeKeywords = ['coffee', 'cafe', 'starbucks', 'tealive', 'kopitiam', 'latte', 'boba'];

/// A catalog entry joined with the signed-in user's live progress.
typedef BadgeEntry = ({BadgeDef badge, int progress, bool earned, int tier});
// tier: 0 = none earned, 1/2/3 = highest earned tier

List<BadgeEntry> computeBadgeEntries(BadgeCatalog catalog, List<TransactionView> rows) {
  return catalog.badges.map((b) {
    final progress = badgeProgress(b.id, rows);
    var tier = 0;
    for (var i = b.tierGoals.length - 1; i >= 0; i--) {
      if (progress >= b.tierGoals[i]) {
        tier = i + 1;
        break;
      }
    }
    return (badge: b, progress: progress, earned: tier >= 1, tier: tier);
  }).toList();
}

int badgeProgress(String badgeId, List<TransactionView> rows) {
  switch (badgeId) {
    case 'food_explorer':
      return rows.where((t) => t.effectiveCategory == 'Food & Drink').length;
    case 'cafe_hopper':
      return rows
          .where(
            (t) => _coffeeKeywords.any(
              (k) => (t.merchantRaw ?? '').toLowerCase().contains(k),
            ),
          )
          .length;
    case 'grocery_planner':
      return rows.where((t) => t.effectiveCategory == 'Groceries').length;
    case 'digital_tracker':
      return 0; // share-count tracking not wired yet
    case 'receipt_collector':
      return rows.length;
    case 'category_explorer':
      return rows.map((t) => t.effectiveCategory).toSet().length;
    default:
      return 0;
  }
}

/// Consecutive days up to and including today (or, if nothing's logged yet
/// today, up to yesterday) with at least one transaction. Denormalized onto
/// `profiles.current_streak` for the friend leaderboard; friends' raw
/// transactions are never readable cross-user (see `SocialRepository`).
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
    if (streak > 3650) break;
  }
  return streak;
}
