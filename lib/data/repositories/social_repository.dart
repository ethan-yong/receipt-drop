import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/config/env.dart';
import '../../domain/logic/feed_line_generator.dart';
import '../../domain/models/transaction_view.dart';

class FeedPost {
  const FeedPost({
    required this.postId,
    required this.userId,
    required this.displayName,
    required this.avatarConfigJson,
    required this.currentMood,
    required this.line,
    required this.createdAt,
    required this.fireCount,
    required this.laughCount,
    required this.eyesCount,
  });

  final String postId;
  final String userId;
  final String? displayName;
  final Map<String, dynamic>? avatarConfigJson;
  final String? currentMood;
  final String line;
  final DateTime createdAt;
  final int fireCount;
  final int laughCount;
  final int eyesCount;

  FeedPost copyWith({int? fireCount, int? laughCount, int? eyesCount}) {
    return FeedPost(
      postId: postId,
      userId: userId,
      displayName: displayName,
      avatarConfigJson: avatarConfigJson,
      currentMood: currentMood,
      line: line,
      createdAt: createdAt,
      fireCount: fireCount ?? this.fireCount,
      laughCount: laughCount ?? this.laughCount,
      eyesCount: eyesCount ?? this.eyesCount,
    );
  }
}

enum FriendshipStatus { pending, accepted, declined, blocked }

class FriendshipView {
  const FriendshipView({
    required this.id,
    required this.requesterId,
    required this.addresseeId,
    required this.status,
    required this.createdAt,
    required this.otherUserId,
    required this.otherDisplayName,
    required this.otherAvatarConfigJson,
  });

  final String id;
  final String requesterId;
  final String addresseeId;
  final FriendshipStatus status;
  final DateTime createdAt;
  final String otherUserId;
  final String? otherDisplayName;
  final Map<String, dynamic>? otherAvatarConfigJson;

  bool isIncomingRequestFor(String myUserId) =>
      status == FriendshipStatus.pending && addresseeId == myUserId;
}

class LeaderboardEntry {
  const LeaderboardEntry({
    required this.userId,
    required this.displayName,
    required this.avatarConfigJson,
    required this.currentMood,
    required this.badgeCount,
    required this.currentStreak,
    required this.isMe,
  });

  final String userId;
  final String? displayName;
  final Map<String, dynamic>? avatarConfigJson;
  final String? currentMood;
  final int badgeCount;
  final int currentStreak;
  final bool isMe;
}

/// Friends/feed/reactions. Mirrors `BadgeRepository`'s shape: a thin,
/// single-file (no `_io`/`_web` split) wrapper over direct Supabase calls
/// and the social `security definer` RPCs from
/// `supabase/migrations/20260626000002_social.sql`.
class SocialRepository {
  SocialRepository._();

  static const _uuid = Uuid();

  static String? get _userId =>
      Env.hasSupabaseConfig ? Supabase.instance.client.auth.currentUser?.id : null;

  /// Looks up a user by email and sends a friend request. Returns a
  /// human-readable error on failure, or null on success.
  static Future<String?> requestFriend(String email) async {
    final userId = _userId;
    if (userId == null) return 'Sign in required.';
    final trimmed = email.trim();
    if (trimmed.isEmpty) return 'Enter an email address.';
    try {
      final rows =
          await Supabase.instance.client.rpc(
                'find_user_by_email',
                params: {'lookup_email': trimmed},
              )
              as List;
      if (rows.isEmpty) return 'No user found with that email.';
      final targetId = (rows.first as Map<String, dynamic>)['id'] as String;
      await Supabase.instance.client.from('friendships').insert({
        'id': _uuid.v4(),
        'requester_id': userId,
        'addressee_id': targetId,
      });
      return null;
    } on PostgrestException catch (e) {
      return e.code == '23505' ? 'Already requested.' : 'Could not send request.';
    } on Object {
      return 'Could not send request.';
    }
  }

  static Future<void> respondToFriendRequest(String friendshipId, bool accept) async {
    try {
      await Supabase.instance.client
          .from('friendships')
          .update({
            'status': accept ? 'accepted' : 'declined',
            'responded_at': DateTime.now().toIso8601String(),
          })
          .eq('id', friendshipId);
    } on Object {
      // Best-effort; the friends screen re-reads listFriendships() after.
    }
  }

  static Future<List<FriendshipView>> listFriendships() async {
    if (_userId == null) return const [];
    try {
      final rows = await Supabase.instance.client.rpc('list_friendships') as List;
      return rows
          .map((r) => _friendshipFromRow(r as Map<String, dynamic>))
          .toList();
    } on Object {
      return const [];
    }
  }

  static FriendshipView _friendshipFromRow(Map<String, dynamic> row) {
    return FriendshipView(
      id: row['id'] as String,
      requesterId: row['requester_id'] as String,
      addresseeId: row['addressee_id'] as String,
      status: _statusFromString(row['status'] as String),
      createdAt: DateTime.parse(row['created_at'] as String),
      otherUserId: row['other_user_id'] as String,
      otherDisplayName: row['other_display_name'] as String?,
      otherAvatarConfigJson: row['other_avatar_config'] as Map<String, dynamic>?,
    );
  }

  static FriendshipStatus _statusFromString(String value) {
    switch (value) {
      case 'accepted':
        return FriendshipStatus.accepted;
      case 'declined':
        return FriendshipStatus.declined;
      case 'blocked':
        return FriendshipStatus.blocked;
      default:
        return FriendshipStatus.pending;
    }
  }

  static Future<List<FeedPost>> getFriendFeed() async {
    if (_userId == null) return const [];
    try {
      final rows = await Supabase.instance.client.rpc('get_friend_feed') as List;
      return rows.map((r) {
        final row = r as Map<String, dynamic>;
        return FeedPost(
          postId: row['post_id'] as String,
          userId: row['user_id'] as String,
          displayName: row['display_name'] as String?,
          avatarConfigJson: row['avatar_config'] as Map<String, dynamic>?,
          currentMood: row['current_mood'] as String?,
          line: row['line'] as String,
          createdAt: DateTime.parse(row['created_at'] as String),
          fireCount: (row['fire_count'] as num).toInt(),
          laughCount: (row['laugh_count'] as num).toInt(),
          eyesCount: (row['eyes_count'] as num).toInt(),
        );
      }).toList();
    } on Object {
      return const [];
    }
  }

  static Future<List<LeaderboardEntry>> getFriendLeaderboard({
    bool fresh = false,
  }) async {
    if (_userId == null) return const [];
    if (Env.hasLeaderboardApiConfig) {
      final fromApi = await _getFriendLeaderboardFromApi(fresh: fresh);
      if (fromApi != null) return fromApi;
    }
    return _getFriendLeaderboardFromRpc();
  }

  static Future<List<LeaderboardEntry>?> _getFriendLeaderboardFromApi({
    required bool fresh,
  }) async {
    try {
      final session = Supabase.instance.client.auth.currentSession;
      final token = session?.accessToken;
      if (token == null) return null;

      final base = Env.leaderboardApiUrl.replaceAll(RegExp(r'/+$'), '');
      final uri = Uri.parse('$base/friends-leaderboard').replace(
        queryParameters: {'fresh': fresh.toString()},
      );
      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final entries = body['entries'] as List<dynamic>?;
      if (entries == null) return null;

      return entries.map((e) {
        final row = e as Map<String, dynamic>;
        return _leaderboardEntryFromRow(row);
      }).toList();
    } on Object {
      return null;
    }
  }

  static Future<List<LeaderboardEntry>> _getFriendLeaderboardFromRpc() async {
    try {
      final rows =
          await Supabase.instance.client.rpc('get_friend_leaderboard') as List;
      return rows
          .map((r) => _leaderboardEntryFromRow(r as Map<String, dynamic>))
          .toList();
    } on Object {
      return const [];
    }
  }

  static LeaderboardEntry _leaderboardEntryFromRow(Map<String, dynamic> row) {
    return LeaderboardEntry(
      userId: row['user_id'] as String,
      displayName: row['display_name'] as String?,
      avatarConfigJson: row['avatar_config'] as Map<String, dynamic>?,
      currentMood: row['current_mood'] as String?,
      badgeCount: (row['badge_count'] as num).toInt(),
      currentStreak: (row['current_streak'] as num).toInt(),
      isMe: row['is_me'] as bool,
    );
  }

  /// Best-effort: a feed post is social flavor, never required for the
  /// underlying receipt save to succeed.
  static Future<void> createFeedPost(TransactionView transaction) async {
    final userId = _userId;
    if (userId == null) return;
    try {
      await Supabase.instance.client.from('feed_posts').insert({
        'id': _uuid.v4(),
        'user_id': userId,
        'transaction_id': transaction.id,
        'line': generateFeedLine(transaction),
      });
    } on Object {
      // Best-effort.
    }
  }

  /// Insert-only; the unique (post_id, user_id, kind) constraint makes a
  /// repeat tap a harmless no-op rather than double-counting.
  static Future<void> reactToPost(String postId, String kind) async {
    final userId = _userId;
    if (userId == null) return;
    try {
      await Supabase.instance.client.from('feed_reactions').insert({
        'id': _uuid.v4(),
        'post_id': postId,
        'user_id': userId,
        'kind': kind,
      });
    } on Object {
      // Best-effort; duplicate-reaction conflicts are expected and benign.
    }
  }
}
