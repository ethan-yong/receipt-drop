import 'avatar_mood.dart';

/// Generates a leaderboard row's descriptive label from mood + streak,
/// replacing Impact Drops' hand-authored per-mock-person labels ("Spiky
/// Streak", "Calm Week", ...) with the same vocabulary picked from real
/// data instead.
String leaderboardLabel({required AvatarMood mood, required int streak}) {
  if (streak == 0) return 'Quiet Mode';
  if (streak >= 7) {
    return switch (mood) {
      AvatarMood.spiky => 'Spiky Streak',
      AvatarMood.active => 'Active Tracker',
      AvatarMood.calm => 'Calm Week',
      AvatarMood.balanced => 'Consistent Observer',
    };
  }
  return switch (mood) {
    AvatarMood.spiky => 'Spiky Days',
    AvatarMood.active => 'Active Tracker',
    AvatarMood.calm => 'Calm Streak',
    AvatarMood.balanced => 'Steady Logger',
  };
}
