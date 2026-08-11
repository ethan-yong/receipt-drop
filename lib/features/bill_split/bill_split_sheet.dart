import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/bootstrap/app_services.dart';
import '../../core/platform/adaptive_sheet.dart';
import '../../core/theme/bill_split_theme.dart';
import '../../data/repositories/bill_split_repository.dart';
import '../../data/repositories/profile_repository.dart';
import '../../data/repositories/social_repository.dart';
import '../../domain/logic/bill_split_math.dart';
import '../../domain/models/bill_split.dart';
import '../../domain/models/friend_group.dart';
import '../../domain/models/transaction_view.dart';
import 'bill_split_step_how.dart';
import 'bill_split_step_review.dart';
import 'bill_split_step_who.dart';
import 'create_group_sheet.dart';

/// A receipt's payer picks who to split with (friends or a saved group),
/// chooses equal or by-item split, then reviews amounts owed and can mark
/// friends paid / send a reminder. From the Claude Design handoff "Bill
/// Split Flow.dc.html", presented as a bottom sheet the same way
/// `ReceiptConfirmSheet` is — the closest existing precedent for "a modal
/// flow launched from a saved receipt."
class BillSplitSheet extends StatefulWidget {
  const BillSplitSheet({super.key, required this.transactionId});

  final String transactionId;

  static Future<void> show(BuildContext context, {required String transactionId}) {
    return AdaptiveSheet.showForm<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: BillSplitColors.surface,
      topRadius: kReceiptSheetRadius,
      showDragHandle: false,
      child: BillSplitSheet(transactionId: transactionId),
    );
  }

  @override
  State<BillSplitSheet> createState() => _BillSplitSheetState();
}

class _BillSplitSheetState extends State<BillSplitSheet> {
  bool _loading = true;
  TransactionView? _tx;
  List<FriendshipView> _friends = const [];
  List<FriendGroupView> _groups = const [];
  BillSplitView? _existingSplit;
  String? _ownerAvatarUrl;
  String? _ownerDisplayName;

  int _step = 0;
  final Set<String> _selectedFriendIds = {};
  BillSplitMode _mode = BillSplitMode.equal;
  final Map<String, Set<String>> _itemAssignments = {};
  bool _creatingSplit = false;
  bool _remindersJustSent = false;
  Timer? _reminderTimer;

  String? get _ownerId => Supabase.instance.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reminderTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final ownerId = _ownerId;
    final results = await Future.wait([
      AppServices.transactions.getById(widget.transactionId),
      SocialRepository.listFriendships(),
      BillSplitRepository.listFriendGroups(),
      BillSplitRepository.getSplitForTransaction(widget.transactionId),
      if (ownerId != null) ProfileRepository.fetchProfileHeader(ownerId),
    ]);
    if (!mounted) return;
    final tx = results[0] as TransactionView?;
    final friendships = results[1] as List<FriendshipView>;
    final groups = results[2] as List<FriendGroupView>;
    final existingSplit = results[3] as BillSplitView?;
    final ownerHeader = ownerId != null
        ? results[4] as ({String? displayName, String? username, String? avatarUrl})
        : null;
    setState(() {
      _tx = tx;
      _friends =
          friendships.where((f) => f.status == FriendshipStatus.accepted).toList();
      _groups = groups;
      _existingSplit = existingSplit;
      _ownerAvatarUrl = ownerHeader?.avatarUrl;
      _ownerDisplayName = ownerHeader?.displayName;
      _loading = false;
      if (existingSplit != null) {
        // A split already exists for this receipt — open straight at
        // Review, never re-enter pick/method (protects already-recorded
        // paid state; bill_splits.transaction_id is unique so there's no
        // way to create a second one anyway).
        _selectedFriendIds
          ..clear()
          ..addAll(existingSplit.participants.map((p) => p.friendUserId));
        _mode = existingSplit.mode;
        _step = 2;
      }
    });
  }

  List<String> _includedPersonIds() {
    return [?_ownerId, ..._selectedFriendIds];
  }

  void _toggleFriend(String friendId) {
    setState(() {
      if (!_selectedFriendIds.remove(friendId)) {
        _selectedFriendIds.add(friendId);
      }
      _pruneItemAssignments();
    });
  }

  void _selectGroup(FriendGroupView group) {
    setState(() {
      _selectedFriendIds
        ..clear()
        ..addAll(group.members.map((m) => m.userId));
      _pruneItemAssignments();
    });
  }

  void _pruneItemAssignments() {
    final included = _includedPersonIds().toSet();
    final owner = _ownerId;
    for (final set in _itemAssignments.values) {
      set.removeWhere((id) => !included.contains(id));
      if (set.isEmpty && owner != null) set.add(owner);
    }
  }

  void _ensureItemDefaults() {
    final included = _includedPersonIds().toSet();
    for (final item in _tx?.lineItems ?? const []) {
      final id = item.id;
      if (id == null) continue;
      _itemAssignments.putIfAbsent(id, () => {...included});
    }
  }

  void _toggleItemPerson(String lineItemId, String personId) {
    setState(() {
      final set =
          _itemAssignments.putIfAbsent(lineItemId, () => {..._includedPersonIds()});
      if (set.contains(personId)) {
        if (set.length == 1) return; // must keep at least one person
        set.remove(personId);
      } else {
        set.add(personId);
      }
    });
  }

  void _goToStep1() {
    setState(() {
      _ensureItemDefaults();
      _step = 1;
    });
  }

  void _goBackToStep0() => setState(() => _step = 0);

  /// True once the receipt has synced (item assignments FK to
  /// `receipt_line_items.id`, which must exist server-side first) and every
  /// line item has a real id.
  bool get _canUseByItem {
    final tx = _tx;
    if (tx == null || tx.syncStatus != 'synced') return false;
    final items = tx.lineItems;
    if (items == null || items.isEmpty) return false;
    return items.every((i) => i.id != null);
  }

  Future<void> _goToReview() async {
    final tx = _tx;
    final ownerId = _ownerId;
    if (tx == null || ownerId == null || tx.amountMyr == null) return;

    setState(() => _creatingSplit = true);

    final friendShares = <String, double>{};
    var assignmentInputs = const <ItemAssignmentInput>[];

    if (_mode == BillSplitMode.equal) {
      final shares =
          splitEqual(totalMyr: tx.amountMyr!, personIds: _includedPersonIds());
      for (final friendId in _selectedFriendIds) {
        friendShares[friendId] = shares[friendId] ?? 0;
      }
    } else {
      _ensureItemDefaults();
      assignmentInputs = [
        for (final item in tx.lineItems ?? const [])
          if (item.id != null)
            ItemAssignmentInput(
              lineItemId: item.id!,
              priceMyr: item.priceMyr,
              assignedPersonIds:
                  (_itemAssignments[item.id!] ?? {ownerId}).toList(),
            ),
      ];
      final shares = splitByItems(assignmentInputs);
      for (final friendId in _selectedFriendIds) {
        friendShares[friendId] = shares[friendId] ?? 0;
      }
    }

    final created = await BillSplitRepository.createSplit(
      transactionId: widget.transactionId,
      totalMyr: tx.amountMyr!,
      mode: _mode,
      friendShareMyr: friendShares,
      itemAssignments: assignmentInputs,
    );
    if (!mounted) return;
    setState(() {
      _creatingSplit = false;
      if (created != null) {
        _existingSplit = created;
        _step = 2;
      }
    });
  }

  Future<void> _setParticipantPaid(String participantId, bool paid) async {
    final split = _existingSplit;
    if (split == null) return;
    setState(() {
      _existingSplit = split.copyWith(
        participants: [
          for (final p in split.participants)
            p.id == participantId
                ? p.copyWith(paid: paid, paidAt: paid ? DateTime.now() : null)
                : p,
        ],
      );
    });
    await BillSplitRepository.setParticipantPaid(participantId, paid);
  }

  Future<void> _sendReminders() async {
    final split = _existingSplit;
    if (split == null) return;
    final pending = split.participants.where((p) => !p.paid).toList();
    if (pending.isEmpty) return;
    setState(() => _remindersJustSent = true);
    _reminderTimer?.cancel();
    _reminderTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _remindersJustSent = false);
    });
    await Future.wait(pending.map((p) => BillSplitRepository.sendReminder(p.id)));
  }

  Future<void> _createGroupAndRefresh() async {
    final created = await CreateGroupSheetLauncher.launch(context, friends: _friends);
    if (created && mounted) {
      final groups = await BillSplitRepository.listFriendGroups();
      if (mounted) setState(() => _groups = groups);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.86,
        child: Column(
          children: [
            _Header(
              title: switch (_step) {
                0 => "Who's splitting?",
                1 => 'How to split',
                _ => 'Review & send',
              },
              step: _step,
              showBack: _step > 0 && _existingSplit == null,
              onBack: _goBackToStep0,
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _buildStep(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep() {
    final tx = _tx;
    if (tx == null) {
      return const Center(child: Text('Receipt not found.'));
    }
    switch (_step) {
      case 0:
        return BillSplitStepWho(
          transaction: tx,
          friends: _friends,
          groups: _groups,
          selectedFriendIds: _selectedFriendIds,
          onToggleFriend: _toggleFriend,
          onSelectGroup: _selectGroup,
          onCreateGroup: _createGroupAndRefresh,
          onContinue: _selectedFriendIds.isNotEmpty ? _goToStep1 : null,
          ownerAvatarUrl: _ownerAvatarUrl,
          ownerDisplayName: _ownerDisplayName,
          ownerUserId: _ownerId,
        );
      case 1:
        return BillSplitStepHow(
          transaction: tx,
          friends: _friends,
          ownerId: _ownerId,
          ownerAvatarUrl: _ownerAvatarUrl,
          includedPersonIds: _includedPersonIds(),
          mode: _mode,
          canUseByItem: _canUseByItem,
          itemAssignments: _itemAssignments,
          onModeChanged: (m) => setState(() => _mode = m),
          onToggleItemPerson: _toggleItemPerson,
          creating: _creatingSplit,
          onReview: _creatingSplit ? null : _goToReview,
        );
      default:
        final split = _existingSplit;
        if (split == null) {
          return const Center(child: Text('No split yet.'));
        }
        return BillSplitStepReview(
          transaction: tx,
          split: split,
          friends: _friends,
          ownerId: _ownerId,
          remindersJustSent: _remindersJustSent,
          onSetParticipantPaid: _setParticipantPaid,
          onSendReminders: _sendReminders,
          onDone: () => Navigator.of(context).pop(),
        );
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.step,
    required this.showBack,
    required this.onBack,
  });

  final String title;
  final int step;
  final bool showBack;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 34,
                height: 34,
                child: showBack
                    ? Material(
                        color: BillSplitColors.tile,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: onBack,
                          child: const Icon(
                            Icons.arrow_back_ios_new,
                            size: 15,
                            color: BillSplitColors.subLight,
                          ),
                        ),
                      )
                    : null,
              ),
              Expanded(
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: balooText(17, FontWeight.w800, color: BillSplitColors.ink),
                ),
              ),
              const SizedBox(width: 34),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: i == step ? 22 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i <= step ? BillSplitColors.gold : BillSplitColors.tile,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
