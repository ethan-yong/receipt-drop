import '../models/transaction_view.dart';
import 'impact_level.dart';

/// Mirrors Impact Drops' avatar mood states, now derived from real spend
/// behavior instead of one in-memory ritual session.
enum AvatarMood { calm, active, spiky, balanced }

extension AvatarMoodX on AvatarMood {
  String get label {
    switch (this) {
      case AvatarMood.calm:
        return 'Calm';
      case AvatarMood.active:
        return 'Active';
      case AvatarMood.spiky:
        return 'Spiky';
      case AvatarMood.balanced:
        return 'Balanced';
    }
  }
}

/// Parses a friend's denormalized `profiles.current_mood` value (see
/// `SocialRepository.getFriendFeed`); falls back to `balanced` for a friend
/// who hasn't synced a mood yet (null) or an unrecognized value.
AvatarMood moodFromName(String? name) {
  for (final m in AvatarMood.values) {
    if (m.name == name) return m;
  }
  return AvatarMood.balanced;
}

/// Rows from [rows] that occurred on the same calendar day as [now].
/// The prototype's `deriveAvatarState` operates over one ritual session's
/// drops; the real app has no "session," so today's transactions are used
/// as the closest equivalent window.
List<TransactionView> todaysTransactions(
  List<TransactionView> rows,
  DateTime now,
) {
  final today = DateTime(now.year, now.month, now.day);
  return rows.where((t) {
    if (!t.includeInCharts) return false;
    final d = DateTime(t.occurredAt.year, t.occurredAt.month, t.occurredAt.day);
    return d == today;
  }).toList();
}

/// Port of Impact Drops' `deriveAvatarState`, keyed off each transaction's
/// derived impact level rather than the mock's flat `impact` field.
AvatarMood deriveAvatarMood(List<TransactionView> todaysRows) {
  final high = todaysRows
      .where((t) => t.effectiveImpactLevel == ImpactLevel.high)
      .length;
  final count = todaysRows.length;
  if (count == 0) return AvatarMood.calm;
  if (high >= 2) return AvatarMood.spiky;
  if (count >= 4) return AvatarMood.active;
  if (high == 0 && count <= 2) return AvatarMood.calm;
  return AvatarMood.balanced;
}
