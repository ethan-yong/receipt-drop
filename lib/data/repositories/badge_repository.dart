import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/config/env.dart';

class BadgeState {
  const BadgeState({required this.progress, required this.earned, this.earnedAt});

  final double progress;
  final bool earned;
  final DateTime? earnedAt;
}

/// Reads/writes per-user badge progress in `user_badges`. Progress itself is
/// computed client-side from the transaction stream (see
/// `domain/logic/badge_progress.dart`, mirroring `dashboard_aggregates.dart`'s
/// pure-function pattern) and synced here on view, both for cross-device
/// continuity and so the leaderboard's security-definer function can read
/// badge counts without touching raw transactions.
class BadgeRepository {
  BadgeRepository._();

  static const _uuid = Uuid();

  static String? get _userId =>
      Env.hasSupabaseConfig ? Supabase.instance.client.auth.currentUser?.id : null;

  static Future<Map<String, BadgeState>> getUserBadgeStates() async {
    final userId = _userId;
    if (userId == null) return const {};
    try {
      final rows = await Supabase.instance.client
          .from('user_badges')
          .select('badge_id, progress, earned, earned_at')
          .eq('user_id', userId);
      final result = <String, BadgeState>{};
      for (final row in rows) {
        result[row['badge_id'] as String] = BadgeState(
          progress: (row['progress'] as num).toDouble(),
          earned: row['earned'] as bool,
          earnedAt: row['earned_at'] == null
              ? null
              : DateTime.parse(row['earned_at'] as String),
        );
      }
      return result;
    } on Object {
      return const {};
    }
  }

  /// Real-time stream of all achievement rows for the current user.
  /// Emits a new list whenever the Postgres trigger updates user_badges after
  /// a receipt mutation. Returns an empty stream when not signed in.
  static Stream<List<Map<String, dynamic>>> streamAll() {
    final userId = _userId;
    if (userId == null) return Stream.value([]);
    return Supabase.instance.client
        .from('user_badges')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId);
  }

  /// Upserts one badge's progress; no-ops silently without a signed-in user
  /// (e.g. demo/skip-auth mode) since there's nowhere to persist to yet.
  static Future<void> saveBadgeState(
    String badgeId, {
    required double progress,
    required bool earned,
  }) async {
    final userId = _userId;
    if (userId == null) return;
    try {
      await Supabase.instance.client.from('user_badges').upsert({
        'id': _uuid.v4(),
        'user_id': userId,
        'badge_id': badgeId,
        'progress': progress,
        'earned': earned,
        if (earned) 'earned_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id,badge_id');
    } on Object {
      // Best-effort cloud sync.
    }
  }
}
