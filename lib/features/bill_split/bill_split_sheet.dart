import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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
///
/// Creation uses a swipeable Who → How → Review wizard; the split is only
/// persisted on Remind / Done / paid. Reopening an existing split locks on
/// Review so paid state cannot be recomposed away.
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
  BillSplitView? _split;
  String? _ownerAvatarUrl;
  String? _ownerDisplayName;

  /// True when this sheet opened on an already-saved split (Review-only).
  bool _wizardLocked = false;

  /// True once [_split] has been written to Supabase this session (or was
  /// loaded as an existing split).
  bool _persisted = false;

  bool _persisting = false;
  int _step = 0;
  final Set<String> _selectedFriendIds = {};
  BillSplitMode _mode = BillSplitMode.equal;
  final Map<String, Set<String>> _itemAssignments = {};
  bool _remindersJustSent = false;
  bool _exiting = false;
  Timer? _reminderTimer;

  late final PageController _pageController = PageController();

  /// Success CTA dwell before auto-navigating to Insights (within 500–800ms).
  static const _remindersSentDwell = Duration(milliseconds: 650);

  String? get _ownerId => Supabase.instance.client.auth.currentUser?.id;

  /// Composition can no longer change via swipe / back.
  bool get _compositionLocked => _wizardLocked || _persisted;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reminderTimer?.cancel();
    _pageController.dispose();
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
        _split = existingSplit;
        _persisted = true;
        _wizardLocked = true;
        _step = 2;
      }
    });
    if (existingSplit != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_pageController.hasClients) return;
        _pageController.jumpToPage(2);
      });
    }
  }

  List<String> _includedPersonIds() {
    return [?_ownerId, ..._selectedFriendIds];
  }

  void _toggleFriend(String friendId) {
    if (_compositionLocked) return;
    setState(() {
      if (!_selectedFriendIds.remove(friendId)) {
        _selectedFriendIds.add(friendId);
      }
      _pruneItemAssignments();
    });
  }

  void _selectGroup(FriendGroupView group) {
    if (_compositionLocked) return;
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
    if (_compositionLocked) return;
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

  ({Map<String, double> friendShares, List<ItemAssignmentInput> assignments})
      _computeShares() {
    final tx = _tx!;
    final ownerId = _ownerId!;
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
    return (friendShares: friendShares, assignments: assignmentInputs);
  }

  BillSplitView? _buildDraftSplit() {
    final tx = _tx;
    final ownerId = _ownerId;
    if (tx == null ||
        ownerId == null ||
        tx.amountMyr == null ||
        _selectedFriendIds.isEmpty) {
      return null;
    }
    final computed = _computeShares();
    return BillSplitView(
      id: 'draft',
      transactionId: widget.transactionId,
      ownerId: ownerId,
      mode: _mode,
      totalMyr: tx.amountMyr!,
      createdAt: DateTime.now(),
      participants: [
        for (final e in computed.friendShares.entries)
          BillSplitParticipant(
            id: 'draft-${e.key}',
            friendUserId: e.key,
            shareMyr: e.value,
            paid: false,
            paidAt: null,
            lastRemindedAt: null,
          ),
      ],
      itemAssignments: [
        for (final a in computed.assignments)
          for (final personId in a.assignedPersonIds)
            BillSplitItemAssignment(
              lineItemId: a.lineItemId,
              assignedUserId: personId,
            ),
      ],
    );
  }

  void _goToPage(int page) {
    if (_compositionLocked && page != 2) return;
    if (page < 0 || page > 2) return;
    if (page == 2 && _selectedFriendIds.isEmpty) return;
    if (page == 1) _ensureItemDefaults();
    if (page == 2 && !_persisted) {
      final draft = _buildDraftSplit();
      if (draft == null) return;
      setState(() => _split = draft);
    }
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _goToStep1() => _goToPage(1);

  void _goToReview() => _goToPage(2);

  void _goBack() {
    if (_compositionLocked || _step <= 0) return;
    _goToPage(_step - 1);
  }

  void _onPageChanged(int page) {
    if (_compositionLocked) {
      if (page != 2 && _pageController.hasClients) {
        _pageController.jumpToPage(2);
      }
      setState(() => _step = 2);
      return;
    }

    if (page == 2 && _selectedFriendIds.isEmpty) {
      _pageController.animateToPage(
        1,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
      return;
    }

    setState(() {
      _step = page;
      if (page == 1) _ensureItemDefaults();
      if (page == 2 && !_persisted) {
        _split = _buildDraftSplit();
      }
    });
  }

  Future<bool> _ensurePersisted() async {
    if (_persisted && _split != null) return true;
    if (_persisting) return false;
    final tx = _tx;
    final ownerId = _ownerId;
    if (tx == null ||
        ownerId == null ||
        tx.amountMyr == null ||
        _selectedFriendIds.isEmpty) {
      return false;
    }

    setState(() => _persisting = true);
    final computed = _computeShares();
    final created = await BillSplitRepository.createSplit(
      transactionId: widget.transactionId,
      totalMyr: tx.amountMyr!,
      mode: _mode,
      friendShareMyr: computed.friendShares,
      itemAssignments: computed.assignments,
    );
    if (!mounted) return false;
    setState(() {
      _persisting = false;
      if (created != null) {
        _split = created;
        _persisted = true;
      }
    });
    return created != null;
  }

  Future<void> _setParticipantPaid(String participantId, bool paid) async {
    final before = _split;
    if (before == null) return;
    final friendUserId = before.participants
        .where((p) => p.id == participantId)
        .firstOrNull
        ?.friendUserId;

    final ok = await _ensurePersisted();
    if (!ok || !mounted) return;

    final split = _split!;
    final realId = friendUserId != null
        ? split.participants
            .where((p) => p.friendUserId == friendUserId)
            .firstOrNull
            ?.id
        : participantId;
    if (realId == null) return;

    setState(() {
      _split = split.copyWith(
        participants: [
          for (final p in split.participants)
            p.id == realId
                ? p.copyWith(paid: paid, paidAt: paid ? DateTime.now() : null)
                : p,
        ],
      );
    });
    await BillSplitRepository.setParticipantPaid(realId, paid);
  }

  void _exitToInsights() {
    if (_exiting || !mounted) return;
    _exiting = true;
    _reminderTimer?.cancel();
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.goNamed('insights');
  }

  Future<void> _onDone() async {
    if (_exiting) return;
    final ok = await _ensurePersisted();
    if (!ok || !mounted) return;
    _exitToInsights();
  }

  Future<void> _sendReminders() async {
    if (_remindersJustSent || _exiting) return;
    final ok = await _ensurePersisted();
    if (!ok || !mounted) return;
    final split = _split;
    if (split == null) return;
    final pending = split.participants.where((p) => !p.paid).toList();
    if (pending.isEmpty) return;
    setState(() => _remindersJustSent = true);
    _reminderTimer?.cancel();
    _reminderTimer = Timer(_remindersSentDwell, _exitToInsights);
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
    // System back: step back through Who/How/Review while the wizard is
    // editable; once locked (or on Who), allow the modal sheet to dismiss.
    return PopScope(
      canPop: _compositionLocked || _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goBack();
      },
      child: SafeArea(
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
                showBack: _step > 0 && !_compositionLocked,
                onBack: _goBack,
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _buildPager(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPager() {
    final tx = _tx;
    if (tx == null) {
      return const Center(child: Text('Receipt not found.'));
    }
    final split = _split;

    return PageView(
      controller: _pageController,
      physics: _compositionLocked
          ? const NeverScrollableScrollPhysics()
          : const PageScrollPhysics(),
      onPageChanged: _onPageChanged,
      children: [
        BillSplitStepWho(
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
        ),
        BillSplitStepHow(
          transaction: tx,
          friends: _friends,
          ownerId: _ownerId,
          ownerAvatarUrl: _ownerAvatarUrl,
          includedPersonIds: _includedPersonIds(),
          mode: _mode,
          canUseByItem: _canUseByItem,
          itemAssignments: _itemAssignments,
          onModeChanged: (m) {
            if (_compositionLocked) return;
            setState(() => _mode = m);
          },
          onToggleItemPerson: _toggleItemPerson,
          creating: _persisting,
          onReview: _persisting ? null : _goToReview,
        ),
        split == null
            ? const Center(child: Text('No split yet.'))
            : BillSplitStepReview(
                transaction: tx,
                split: split,
                friends: _friends,
                ownerId: _ownerId,
                remindersJustSent: _remindersJustSent,
                onSetParticipantPaid: _setParticipantPaid,
                onSendReminders: _sendReminders,
                onDone: _onDone,
              ),
      ],
    );
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
