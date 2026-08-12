import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/config/env.dart';
import '../../domain/logic/bill_split_math.dart';
import '../../domain/models/bill_split.dart';
import '../../domain/models/friend_group.dart';

/// Friend groups + Bill Split. Mirrors `SocialRepository`'s shape: a thin,
/// single-file (no `_io`/`_web` split) wrapper over direct Supabase calls
/// and the `security definer` RPCs from `20260807000000_friend_groups.sql`
/// / `20260807010000_bill_splits.sql`.
class BillSplitRepository {
  BillSplitRepository._();

  static const _uuid = Uuid();

  static String? get _userId =>
      Env.hasSupabaseConfig ? Supabase.instance.client.auth.currentUser?.id : null;

  // --- friend groups ---------------------------------------------------

  static Future<List<FriendGroupView>> listFriendGroups() async {
    if (_userId == null) return const [];
    try {
      final rows = await Supabase.instance.client.rpc('list_friend_groups') as List;
      final byGroup = <String, List<Map<String, dynamic>>>{};
      final order = <String>[];
      for (final r in rows) {
        final row = r as Map<String, dynamic>;
        final groupId = row['group_id'] as String;
        if (!byGroup.containsKey(groupId)) order.add(groupId);
        (byGroup[groupId] ??= []).add(row);
      }
      return order.map((groupId) {
        final groupRows = byGroup[groupId]!;
        final first = groupRows.first;
        return FriendGroupView(
          id: groupId,
          name: first['name'] as String,
          createdAt: DateTime.parse(first['created_at'] as String),
          members: groupRows
              .map(
                (row) => FriendGroupMember(
                  userId: row['member_user_id'] as String,
                  displayName: row['member_display_name'] as String?,
                  avatarUrl: row['member_avatar_url'] as String?,
                ),
              )
              .toList(),
        );
      }).toList();
    } on Object {
      return const [];
    }
  }

  /// Returns a human-readable error, or null on success.
  static Future<String?> createFriendGroup({
    required String name,
    required List<String> memberFriendUserIds,
  }) async {
    final userId = _userId;
    if (userId == null) return 'Sign in required.';
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'Enter a group name.';
    if (memberFriendUserIds.isEmpty) return 'Pick at least one friend.';
    try {
      final groupId = _uuid.v4();
      await Supabase.instance.client.from('friend_groups').insert({
        'id': groupId,
        'owner_id': userId,
        'name': trimmed,
      });
      await Supabase.instance.client.from('friend_group_members').insert(
            memberFriendUserIds
                .map((friendId) => {'group_id': groupId, 'friend_user_id': friendId})
                .toList(),
          );
      return null;
    } on Object {
      return 'Could not create group.';
    }
  }

  static Future<void> deleteFriendGroup(String groupId) async {
    try {
      await Supabase.instance.client.from('friend_groups').delete().eq('id', groupId);
    } on Object {
      // Best-effort; the caller re-reads listFriendGroups() after.
    }
  }

  // --- bill split (payer side) -----------------------------------------

  /// Null if this transaction has no split yet (or the caller isn't its
  /// owner — RLS returns no row either way).
  static Future<BillSplitView?> getSplitForTransaction(String transactionId) async {
    if (_userId == null) return null;
    try {
      final splitRow = await Supabase.instance.client
          .from('bill_splits')
          .select()
          .eq('transaction_id', transactionId)
          .maybeSingle();
      if (splitRow == null) return null;
      return _assembleSplit(splitRow);
    } on Object {
      return null;
    }
  }

  static Future<BillSplitView?> _assembleSplit(Map<String, dynamic> splitRow) async {
    final splitId = splitRow['id'] as String;
    final mode = billSplitModeFromString(splitRow['mode'] as String);

    final participantRows = await Supabase.instance.client
        .from('bill_split_participants')
        .select()
        .eq('split_id', splitId) as List;
    final participants = participantRows
        .map((r) => _participantFromRow(r as Map<String, dynamic>))
        .toList();

    var itemAssignments = const <BillSplitItemAssignment>[];
    if (mode == BillSplitMode.byItem) {
      final assignmentRows = await Supabase.instance.client
          .from('bill_split_item_assignments')
          .select()
          .eq('split_id', splitId) as List;
      itemAssignments = assignmentRows
          .map((r) {
            final row = r as Map<String, dynamic>;
            return BillSplitItemAssignment(
              lineItemId: row['line_item_id'] as String,
              assignedUserId: row['assigned_user_id'] as String,
            );
          })
          .toList();
    }

    return BillSplitView(
      id: splitId,
      transactionId: splitRow['transaction_id'] as String,
      ownerId: splitRow['owner_id'] as String,
      mode: mode,
      totalMyr: (splitRow['total_myr'] as num).toDouble(),
      createdAt: DateTime.parse(splitRow['created_at'] as String),
      participants: participants,
      itemAssignments: itemAssignments,
    );
  }

  static BillSplitParticipant _participantFromRow(Map<String, dynamic> row) {
    return BillSplitParticipant(
      id: row['id'] as String,
      friendUserId: row['friend_user_id'] as String,
      shareMyr: (row['share_myr'] as num).toDouble(),
      paid: row['paid'] as bool,
      paidAt: row['paid_at'] != null ? DateTime.parse(row['paid_at'] as String) : null,
      lastRemindedAt: row['last_reminded_at'] != null
          ? DateTime.parse(row['last_reminded_at'] as String)
          : null,
    );
  }

  /// Creates a split header + participants + (for `by_item`) item
  /// assignments, then re-reads it via [getSplitForTransaction] so the
  /// read/write paths always share one assembly point.
  static Future<BillSplitView?> createSplit({
    required String transactionId,
    required double totalMyr,
    required BillSplitMode mode,
    required Map<String, double> friendShareMyr,
    List<ItemAssignmentInput> itemAssignments = const [],
  }) async {
    final userId = _userId;
    if (userId == null || friendShareMyr.isEmpty) return null;
    try {
      final splitId = _uuid.v4();
      await Supabase.instance.client.from('bill_splits').insert({
        'id': splitId,
        'transaction_id': transactionId,
        'owner_id': userId,
        'mode': billSplitModeToString(mode),
        'total_myr': totalMyr,
      });

      await Supabase.instance.client.from('bill_split_participants').insert(
            friendShareMyr.entries
                .map(
                  (e) => {
                    'id': _uuid.v4(),
                    'split_id': splitId,
                    'friend_user_id': e.key,
                    'share_myr': e.value,
                  },
                )
                .toList(),
          );

      if (mode == BillSplitMode.byItem && itemAssignments.isNotEmpty) {
        final rows = <Map<String, dynamic>>[];
        for (final item in itemAssignments) {
          for (final personId in item.assignedPersonIds) {
            rows.add({
              'id': _uuid.v4(),
              'split_id': splitId,
              'line_item_id': item.lineItemId,
              'assigned_user_id': personId,
            });
          }
        }
        await Supabase.instance.client.from('bill_split_item_assignments').insert(rows);
      }

      return getSplitForTransaction(transactionId);
    } on Object {
      return null;
    }
  }

  /// Used by both the payer's review step and a friend's self-report; RLS
  /// (not app logic) determines who's allowed to call this for a given row.
  static Future<void> setParticipantPaid(String participantId, bool paid) async {
    try {
      await Supabase.instance.client.from('bill_split_participants').update({
        'paid': paid,
        'paid_at': paid ? DateTime.now().toIso8601String() : null,
      }).eq('id', participantId);
    } on Object {
      // Best-effort; the caller's optimistic UI state is the source of
      // truth for the current session either way.
    }
  }

  /// Best-effort: stamps `last_reminded_at` only. There is no push-
  /// notification or messaging system in this app to actually deliver a
  /// reminder — discovery is the friend's own Split Requests screen/Home
  /// banner (see `getMySplitRequests`). This just records that the payer
  /// tapped "remind" and drives the "✓ Reminders sent" optimistic label.
  static Future<void> sendReminder(String participantId) async {
    try {
      await Supabase.instance.client.from('bill_split_participants').update({
        'last_reminded_at': DateTime.now().toIso8601String(),
      }).eq('id', participantId);
    } on Object {
      // Best-effort.
    }
  }

  // --- bill split (friend side) -----------------------------------------

  /// Realtime raw `bill_split_participants` rows the caller is a
  /// participant in — used only to drive the Home screen's pending-count
  /// banner (mirrors `BadgeRepository.streamAll()`'s pattern). Callers that
  /// need the joined merchant/payer view should use [getMySplitRequests].
  static Stream<List<Map<String, dynamic>>> streamMyPendingSplitParticipants() {
    final userId = _userId;
    if (userId == null) return Stream.value(const []);
    return Supabase.instance.client
        .from('bill_split_participants')
        .stream(primaryKey: ['id'])
        .eq('friend_user_id', userId);
  }

  static Future<List<MySplitRequestView>> getMySplitRequests() async {
    if (_userId == null) return const [];
    try {
      final rows = await Supabase.instance.client.rpc('get_my_split_requests') as List;
      return rows.map((r) {
        final row = r as Map<String, dynamic>;
        return MySplitRequestView(
          splitId: row['split_id'] as String,
          participantId: row['participant_id'] as String,
          transactionId: row['transaction_id'] as String,
          merchantRaw: row['merchant_raw'] as String?,
          payerUserId: row['payer_user_id'] as String,
          payerDisplayName: row['payer_display_name'] as String?,
          payerAvatarUrl: row['payer_avatar_url'] as String?,
          mode: billSplitModeFromString(row['mode'] as String),
          totalMyr: (row['total_myr'] as num).toDouble(),
          shareMyr: (row['share_myr'] as num).toDouble(),
          paid: row['paid'] as bool,
          paidAt: row['paid_at'] != null ? DateTime.parse(row['paid_at'] as String) : null,
          createdAt: DateTime.parse(row['created_at'] as String),
        );
      }).toList();
    } on Object {
      return const [];
    }
  }
}
