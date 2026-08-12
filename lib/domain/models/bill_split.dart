enum BillSplitMode { equal, byItem }

BillSplitMode billSplitModeFromString(String value) =>
    value == 'by_item' ? BillSplitMode.byItem : BillSplitMode.equal;

String billSplitModeToString(BillSplitMode mode) =>
    mode == BillSplitMode.byItem ? 'by_item' : 'equal';

/// One friend's share of a split (`bill_split_participants`). Display
/// name/avatar are deliberately not stored here — the payer-side UI
/// resolves them against the already-loaded friend roster
/// (`SocialRepository.listFriendships()`), same as group members are
/// resolved in the "who's splitting" step.
class BillSplitParticipant {
  const BillSplitParticipant({
    required this.id,
    required this.friendUserId,
    required this.shareMyr,
    required this.paid,
    required this.paidAt,
    required this.lastRemindedAt,
  });

  final String id;
  final String friendUserId;
  final double shareMyr;
  final bool paid;
  final DateTime? paidAt;
  final DateTime? lastRemindedAt;

  /// Both [paid] and [paidAt] are required (not defaulted from `this`) so a
  /// transition back to unpaid can clear [paidAt] to null explicitly.
  BillSplitParticipant copyWith({required bool paid, required DateTime? paidAt}) =>
      BillSplitParticipant(
        id: id,
        friendUserId: friendUserId,
        shareMyr: shareMyr,
        paid: paid,
        paidAt: paidAt,
        lastRemindedAt: lastRemindedAt,
      );
}

/// One `receipt_line_items` row's assignment to a person, for `by_item`
/// splits (`bill_split_item_assignments`).
class BillSplitItemAssignment {
  const BillSplitItemAssignment({
    required this.lineItemId,
    required this.assignedUserId,
  });

  final String lineItemId;
  final String assignedUserId;
}

/// A payer's split for one receipt (`bill_splits`), with its participants
/// and (for `by_item` mode) item assignments.
class BillSplitView {
  const BillSplitView({
    required this.id,
    required this.transactionId,
    required this.ownerId,
    required this.mode,
    required this.totalMyr,
    required this.createdAt,
    required this.participants,
    required this.itemAssignments,
  });

  final String id;
  final String transactionId;
  final String ownerId;
  final BillSplitMode mode;
  final double totalMyr;
  final DateTime createdAt;
  final List<BillSplitParticipant> participants; // friends only, never "you"
  final List<BillSplitItemAssignment> itemAssignments; // empty for equal mode

  double get owedTotalMyr =>
      participants.fold(0.0, (sum, p) => sum + p.shareMyr);

  double get collectedMyr => participants
      .where((p) => p.paid)
      .fold(0.0, (sum, p) => sum + p.shareMyr);

  /// The payer's own share, derived (never stored) — "You paid the bill".
  double get yourShareMyr => totalMyr - owedTotalMyr;

  int get pendingCount => participants.where((p) => !p.paid).length;

  bool get allSettled => pendingCount == 0;

  /// User ids to show as assignee avatars on a line-item row.
  /// Equal splits: owner + every friend participant (all share every item).
  /// By-item: users assigned to this line item (empty when [itemId] is missing).
  List<String> assigneeIdsForLineItem(String? itemId) {
    if (mode == BillSplitMode.equal) {
      return [ownerId, ...participants.map((p) => p.friendUserId)];
    }
    if (itemId == null || itemId.isEmpty) return const [];
    return [
      for (final a in itemAssignments)
        if (a.lineItemId == itemId) a.assignedUserId,
    ];
  }

  BillSplitView copyWith({List<BillSplitParticipant>? participants}) => BillSplitView(
        id: id,
        transactionId: transactionId,
        ownerId: ownerId,
        mode: mode,
        totalMyr: totalMyr,
        createdAt: createdAt,
        participants: participants ?? this.participants,
        itemAssignments: itemAssignments,
      );
}

/// A friend's view of a split they're a participant in
/// (`get_my_split_requests()`), surfaced on the Split Requests screen.
class MySplitRequestView {
  const MySplitRequestView({
    required this.splitId,
    required this.participantId,
    required this.transactionId,
    required this.merchantRaw,
    required this.payerUserId,
    required this.payerDisplayName,
    required this.payerAvatarUrl,
    required this.mode,
    required this.totalMyr,
    required this.shareMyr,
    required this.paid,
    required this.paidAt,
    required this.createdAt,
  });

  final String splitId;
  final String participantId;
  final String transactionId;
  final String? merchantRaw;
  final String payerUserId;
  final String? payerDisplayName;

  /// Real profile photo URL from the payer's `profiles.avatar_url`.
  final String? payerAvatarUrl;
  final BillSplitMode mode;
  final double totalMyr;
  final double shareMyr;
  final bool paid;
  final DateTime? paidAt;
  final DateTime createdAt;
}
