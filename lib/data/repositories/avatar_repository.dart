import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/env.dart';
import '../../domain/models/avatar_config.dart';

/// Reads/writes the user's avatar customization and top-badge order on
/// `profiles`. Single file (no `_io`/`_web` split) — pure Supabase calls,
/// identical on every platform, unlike the outbox-split transaction
/// repositories.
class AvatarRepository {
  AvatarRepository._();

  static AvatarConfig? _cachedConfig;
  static List<String>? _cachedTopBadgeOrder;

  static String? get _userId =>
      Env.hasSupabaseConfig
          ? Supabase.instance.client.auth.currentUser?.id
          : null;

  static Future<AvatarConfig> getAvatarConfig() async {
    if (_cachedConfig != null) return _cachedConfig!;
    final userId = _userId;
    if (userId == null) {
      return _cachedConfig = AvatarConfig.defaultConfig();
    }
    try {
      final row = await Supabase.instance.client
          .from('profiles')
          .select('avatar_config')
          .eq('id', userId)
          .maybeSingle();
      final json = row?['avatar_config'];
      _cachedConfig = json is Map<String, dynamic>
          ? AvatarConfig.fromJson(json)
          : AvatarConfig.defaultConfig();
    } on Object {
      _cachedConfig = AvatarConfig.defaultConfig();
    }
    return _cachedConfig!;
  }

  static Future<void> saveAvatarConfig(AvatarConfig config) async {
    _cachedConfig = config;
    final userId = _userId;
    if (userId == null) return;
    try {
      await Supabase.instance.client
          .from('profiles')
          .update({'avatar_config': config.toJson()})
          .eq('id', userId);
    } on Object {
      // Best-effort cloud sync; local cache above already reflects the change.
    }
  }

  static Future<List<String>> getTopBadgeOrder() async {
    if (_cachedTopBadgeOrder != null) return _cachedTopBadgeOrder!;
    final userId = _userId;
    if (userId == null) {
      return _cachedTopBadgeOrder = const [];
    }
    try {
      final row = await Supabase.instance.client
          .from('profiles')
          .select('top_badge_order')
          .eq('id', userId)
          .maybeSingle();
      final order = row?['top_badge_order'];
      _cachedTopBadgeOrder =
          order is List ? order.map((e) => e.toString()).toList() : const [];
    } on Object {
      _cachedTopBadgeOrder = const [];
    }
    return _cachedTopBadgeOrder!;
  }

  static Future<void> saveTopBadgeOrder(List<String> order) async {
    _cachedTopBadgeOrder = order;
    final userId = _userId;
    if (userId == null) return;
    try {
      await Supabase.instance.client
          .from('profiles')
          .update({'top_badge_order': order})
          .eq('id', userId);
    } on Object {
      // Best-effort cloud sync; local cache above already reflects the change.
    }
  }

  static String? _lastSyncedMood;

  /// Denormalizes the caller's own mood onto `profiles.current_mood` so
  /// friends can render this user's BlobAvatar in the feed/leaderboard
  /// without needing access to their raw transactions. No-ops when the
  /// mood hasn't actually changed since the last sync.
  static Future<void> syncCurrentMood(String mood) async {
    if (_lastSyncedMood == mood) return;
    _lastSyncedMood = mood;
    final userId = _userId;
    if (userId == null) return;
    try {
      await Supabase.instance.client
          .from('profiles')
          .update({'current_mood': mood})
          .eq('id', userId);
    } on Object {
      // Best-effort cloud sync.
    }
  }

  static int? _lastSyncedStreak;

  /// Denormalizes the caller's own current daily-logging streak onto
  /// `profiles.current_streak`, the friend leaderboard's primary ranking
  /// signal (see [currentDailyStreak] and migration
  /// 20260626000003_leaderboard.sql).
  static Future<void> syncCurrentStreak(int streak) async {
    if (_lastSyncedStreak == streak) return;
    _lastSyncedStreak = streak;
    final userId = _userId;
    if (userId == null) return;
    try {
      await Supabase.instance.client
          .from('profiles')
          .update({'current_streak': streak})
          .eq('id', userId);
    } on Object {
      // Best-effort cloud sync.
    }
  }

  static int? _lastSyncedBadgeCount;

  /// Denormalizes the caller's own earned-badge count onto
  /// `profiles.badge_count`, the friend leaderboard's tiebreaker signal.
  static Future<void> syncBadgeCount(int count) async {
    if (_lastSyncedBadgeCount == count) return;
    _lastSyncedBadgeCount = count;
    final userId = _userId;
    if (userId == null) return;
    try {
      await Supabase.instance.client
          .from('profiles')
          .update({'badge_count': count})
          .eq('id', userId);
    } on Object {
      // Best-effort cloud sync.
    }
  }

  /// Test helper: reset cached state.
  static void clearForTest() {
    _cachedConfig = null;
    _cachedTopBadgeOrder = null;
    _lastSyncedMood = null;
    _lastSyncedStreak = null;
    _lastSyncedBadgeCount = null;
  }
}
