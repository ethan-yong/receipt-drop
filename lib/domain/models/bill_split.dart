enum BillSplitMode { equal, byItem }

BillSplitMode billSplitModeFromString(String value) =>
    value == 'by_item' ? BillSplitMode.byItem : BillSplitMode.equal;

String billSplitModeToString(BillSplitMode mode) =>
    mode == BillSplitMode.byItem ? 'by_item' : 'equal';

/// One person's share of a split (`bill_split_participants`) — either a
/// Receipt Drop friend ([friendUserId] set) or an external phone contact
/// with no account ([contactName]/[contactPhone] set instead). Exactly one
/// of those two identity shapes is ever populated, mirrored by the
/// `bsp_identity_pair_check` constraint in
/// `20260824000000_bill_split_external_contacts.sql`.
///
/// Friend display name/avatar are deliberately not stored here — the
/// payer-side UI resolves them against the already-loaded friend roster
/// (`SocialRepository.listFriendships()`), same as group members are
/// resolved in the "who's splitting" step. External-contact display info
/// (name/phone) *is* stored here, since there's no roster to resolve it
/// against.
class BillSplitParticipant {
  const BillSplitParticipant({
    required this.id,
    required this.friendUserId,
    this.contactName,
    this.contactPhone,
    required this.shareMyr,
    required this.paid,
    required this.paidAt,
    required this.lastRemindedAt,
  });

  final String id;
  final String? friendUserId;
  final String? contactName;
  final String? contactPhone;
  final double shareMyr;
  final bool paid;
  final DateTime? paidAt;
  final DateTime? lastRemindedAt;

  bool get isExternalContact => friendUserId == null;

  /// Unifying identity key for split math / item-assignment lookups: a
  /// friend's real `profiles.id`, or (for an external contact) this row's
  /// own id — pre-minted client-side at pick time so it's stable from draft
  /// through persisted, and item assignments can reference it directly via
  /// `bill_split_item_assignments.assigned_participant_id`.
  String get personKey => friendUserId ?? id;

  /// Both [paid] and [paidAt] are required (not defaulted from `this`) so a
  /// transition back to unpaid can clear [paidAt] to null explicitly.
  /// [lastRemindedAt] is optional and defaults from `this` — reminder state
  /// is updated independently of paid state.
  BillSplitParticipant copyWith({
    required bool paid,
    required DateTime? paidAt,
    DateTime? lastRemindedAt,
  }) =>
      BillSplitParticipant(
        id: id,
        friendUserId: friendUserId,
        contactName: contactName,
        contactPhone: contactPhone,
        shareMyr: shareMyr,
        paid: paid,
        paidAt: paidAt,
        lastRemindedAt: lastRemindedAt ?? this.lastRemindedAt,
      );
}

/// One `receipt_line_items` row's assignment to a person, for `by_item`
/// splits (`bill_split_item_assignments`). [assignedKey] is a
/// [BillSplitParticipant.personKey] (or the owner's `profiles.id`) — the
/// same key space used everywhere else in this feature.
class BillSplitItemAssignment {
  const BillSplitItemAssignment({
    required this.lineItemId,
    required this.assignedKey,
  });

  final String lineItemId;
  final String assignedKey;
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
  final List<BillSplitParticipant> participants; // friends + contacts, never "you"
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

  /// Person keys to show as assignee avatars on a line-item row.
  /// Equal splits: owner + every participant (all share every item).
  /// By-item: keys assigned to this line item (empty when [itemId] is missing).
  List<String> assigneeIdsForLineItem(String? itemId) {
    if (mode == BillSplitMode.equal) {
      return [ownerId, ...participants.map((p) => p.personKey)];
    }
    if (itemId == null || itemId.isEmpty) return const [];
    return [
      for (final a in itemAssignments)
        if (a.lineItemId == itemId) a.assignedKey,
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
/// Never surfaced for external contacts — they have no account to view it
/// from, which `get_my_split_requests()` already excludes by construction.
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

/// A phone contact picked to split a bill with, who does not need (and may
/// not have) a Receipt Drop account. [id] is pre-minted client-side (before
/// the split is persisted) and becomes the row id of the
/// `bill_split_participants` row it turns into — see
/// `BillSplitRepository.createSplit`. Scoped to one split; picking the same
/// person again for a different receipt means re-picking them from device
/// contacts (external contacts are not imported as a permanent roster).
class ExternalContactDraft {
  const ExternalContactDraft({
    required this.id,
    required this.name,
    required this.phoneDigits,
  });

  final String id;
  final String name;

  /// Normalized via `lib/domain/logic/phone_number.dart` — bare digits,
  /// wa.me-ready, no leading '+'.
  final String phoneDigits;
}
