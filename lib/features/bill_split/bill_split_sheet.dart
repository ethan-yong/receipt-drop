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
import '../../domain/logic/bill_split_reminder_message.dart';
import '../../domain/logic/contact_resolution_merge.dart';
import '../../domain/models/bill_split.dart';
import '../../domain/models/friend_group.dart';
import '../../domain/models/transaction_view.dart';
import 'bill_split_step_how.dart';
import 'bill_split_step_review.dart';
import 'bill_split_step_who.dart';
import 'create_group_sheet.dart';
import 'whatsapp_launcher.dart';

/// Where Remind / Done land after the split sheet commits.
enum BillSplitAfterCommit {
  /// Post-scan reward path — close the sheet and go to Insights.
  insights,

  /// Editing an existing receipt — just dismiss the sheet.
  stay,
}

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
  const BillSplitSheet({
    super.key,
    required this.transactionId,
    this.afterCommit = BillSplitAfterCommit.stay,
  });

  final String transactionId;
  final BillSplitAfterCommit afterCommit;

  static Future<void> show(
    BuildContext context, {
    required String transactionId,
    BillSplitAfterCommit afterCommit = BillSplitAfterCommit.stay,
  }) {
    return AdaptiveSheet.showForm<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: BillSplitColors.surface,
      topRadius: kReceiptSheetRadius,
      showDragHandle: false,
      child: BillSplitSheet(
        transactionId: transactionId,
        afterCommit: afterCommit,
      ),
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
  final Map<String, ExternalContactDraft> _selectedContacts = {};
  BillSplitMode _mode = BillSplitMode.equal;
  final Map<String, Set<String>> _itemAssignments = {};
  bool _remindersJustSent = false;
  bool _exiting = false;
  Timer? _reminderTimer;

  late final PageController _pageController = PageController();

  /// Success CTA dwell before auto-exiting after Remind (within 500–800ms).
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
          ..addAll(
            existingSplit.participants
                .where((p) => !p.isExternalContact)
                .map((p) => p.friendUserId!),
          );
        _selectedContacts
          ..clear()
          ..addEntries(
            existingSplit.participants.where((p) => p.isExternalContact).map(
                  (p) => MapEntry(
                    p.id,
                    ExternalContactDraft(
                      id: p.id,
                      name: p.contactName!,
                      phoneDigits: p.contactPhone!,
                    ),
                  ),
                ),
          );
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
    return [?_ownerId, ..._selectedFriendIds, ..._selectedContacts.keys];
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

  /// Adds resolved selections from [ContactPickerSheet]: a
  /// [MatchedContactResolution] (the number matched an existing Receipt
  /// Drop account, friend or not) merges into the same friend-id set used
  /// by manually-picked friends — which is exactly why "picked as a friend
  /// row and separately phone-matched" collapses to one entry for free
  /// (`Set.add` on an already-present id is a no-op). An
  /// [UnmatchedContactResolution] merges into the external-contacts map
  /// exactly as Phase 1's `_addContacts` did, deduped by phone.
  void _addResolvedContacts(List<ContactResolution> results) {
    if (_compositionLocked) return;
    setState(() {
      final merged = mergeContactResolutions(
        friendIds: _selectedFriendIds,
        contacts: _selectedContacts,
        results: results,
      );
      _selectedFriendIds
        ..clear()
        ..addAll(merged.friendIds);
      _selectedContacts
        ..clear()
        ..addAll(merged.contacts);
      _pruneItemAssignments();
    });
  }

  void _removeContact(String id) {
    if (_compositionLocked) return;
    setState(() {
      _selectedContacts.remove(id);
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

  /// Whether at least one friend or external contact is selected — the
  /// minimum needed to proceed past "Who's splitting?" or to persist a split.
  bool get _hasAnyParticipants =>
      _selectedFriendIds.isNotEmpty || _selectedContacts.isNotEmpty;

  ({Map<String, double> participantShareMyr, List<ItemAssignmentInput> assignments})
      _computeShares() {
    final tx = _tx!;
    final ownerId = _ownerId!;
    final participantShareMyr = <String, double>{};
    var assignmentInputs = const <ItemAssignmentInput>[];
    final participantKeys = {..._selectedFriendIds, ..._selectedContacts.keys};

    if (_mode == BillSplitMode.equal) {
      final shares =
          splitEqual(totalMyr: tx.amountMyr!, personIds: _includedPersonIds());
      for (final key in participantKeys) {
        participantShareMyr[key] = shares[key] ?? 0;
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
      for (final key in participantKeys) {
        participantShareMyr[key] = shares[key] ?? 0;
      }
    }
    return (participantShareMyr: participantShareMyr, assignments: assignmentInputs);
  }

  BillSplitView? _buildDraftSplit() {
    final tx = _tx;
    final ownerId = _ownerId;
    if (tx == null || ownerId == null || tx.amountMyr == null || !_hasAnyParticipants) {
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
        for (final e in computed.participantShareMyr.entries)
          _selectedContacts.containsKey(e.key)
              ? BillSplitParticipant(
                  // Unlike a friend's synthetic 'draft-<id>' placeholder
                  // below, a contact's id IS its final persisted row id
                  // (pre-minted at pick time — see ExternalContactDraft),
                  // so _setParticipantPaid's draft->real lookup needs no
                  // special-casing for contacts.
                  id: e.key,
                  friendUserId: null,
                  contactName: _selectedContacts[e.key]!.name,
                  contactPhone: _selectedContacts[e.key]!.phoneDigits,
                  shareMyr: e.value,
                  paid: false,
                  paidAt: null,
                  lastRemindedAt: null,
                )
              : BillSplitParticipant(
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
              assignedKey: personId,
            ),
      ],
    );
  }

  void _goToPage(int page) {
    if (_compositionLocked && page != 2) return;
    if (page < 0 || page > 2) return;
    if (page == 2 && !_hasAnyParticipants) return;
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

    if (page == 2 && !_hasAnyParticipants) {
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
    if (tx == null || ownerId == null || tx.amountMyr == null || !_hasAnyParticipants) {
      return false;
    }

    setState(() => _persisting = true);
    final computed = _computeShares();
    final created = await BillSplitRepository.createSplit(
      transactionId: widget.transactionId,
      totalMyr: tx.amountMyr!,
      mode: _mode,
      participantShareMyr: computed.participantShareMyr,
      externalContacts: _selectedContacts,
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

  void _exitAfterCommit() {
    if (_exiting || !mounted) return;
    _exiting = true;
    _reminderTimer?.cancel();
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    if (widget.afterCommit == BillSplitAfterCommit.insights) {
      router.goNamed('insights');
    }
  }

  Future<void> _onDone() async {
    if (_exiting) return;
    final ok = await _ensurePersisted();
    if (!ok || !mounted) return;
    _exitAfterCommit();
  }

  /// Legacy friends-only path (no external contacts on this split): bulk
  /// stamp every pending participant, dwell on "✓ Reminders sent", then
  /// auto-exit — exactly today's behavior, unchanged, so friends-only
  /// splits see zero difference.
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
    _reminderTimer = Timer(_remindersSentDwell, _exitAfterCommit);
    await Future.wait(pending.map((p) => BillSplitRepository.sendReminder(p.id)));
  }

  /// Mixed-split path (≥1 external contact): stamps a single friend's
  /// `last_reminded_at` and updates local state — no dwell/auto-exit, the
  /// user stays on Review to keep working through the list (see spec's
  /// per-participant reminder mockups).
  Future<void> _remindFriend(String participantId) async {
    final ok = await _ensurePersisted();
    if (!ok || !mounted) return;
    await BillSplitRepository.sendReminder(participantId);
    _markReminded(participantId);
  }

  /// This participant's assigned line items with their *share* of each
  /// item's price (not the full item price) — empty for equal-split mode,
  /// where the WhatsApp message just states the flat total instead.
  List<ReminderLineItem> _assignedItemsFor(BillSplitParticipant participant, BillSplitView split) {
    if (split.mode == BillSplitMode.equal) return const [];
    final lineItemsById = {
      for (final li in _tx?.lineItems ?? const []) if (li.id != null) li.id!: li,
    };
    final byLine = <String, List<String>>{};
    for (final a in split.itemAssignments) {
      (byLine[a.lineItemId] ??= []).add(a.assignedKey);
    }
    final items = <ReminderLineItem>[];
    for (final entry in byLine.entries) {
      final item = lineItemsById[entry.key];
      if (item == null || !entry.value.contains(participant.personKey)) continue;
      final shareCents =
          splitCentsEvenly((item.priceMyr * 100).round(), entry.value)[participant.personKey] ?? 0;
      items.add((label: item.displayLabel, priceMyr: shareCents / 100));
    }
    return items;
  }

  /// Opens WhatsApp with a deterministic, receipt-specific reminder for one
  /// external contact, then stamps the same `last_reminded_at` a friend
  /// reminder would — the UI alone decides the label ("Opened WhatsApp" vs
  /// "Reminder sent") based on [BillSplitParticipant.isExternalContact].
  Future<void> _remindContactViaWhatsApp(BillSplitParticipant participant) async {
    final tx = _tx;
    final phone = participant.contactPhone;
    if (tx == null || phone == null) return;
    final ok = await _ensurePersisted();
    if (!ok || !mounted) return;
    final split = _split;
    if (split == null) return;
    final message = buildWhatsAppReminderMessage(
      recipientName: participant.contactName ?? 'there',
      merchantOrPlace: tx.displayPlace,
      receiptDate: tx.occurredAt,
      assignedItems: _assignedItemsFor(participant, split),
      totalOwedMyr: participant.shareMyr,
    );
    await openWhatsAppReminder(phoneDigits: phone, message: message);
    if (!mounted) return;
    await BillSplitRepository.sendReminder(participant.id);
    _markReminded(participant.id);
  }

  void _markReminded(String participantId) {
    final split = _split;
    if (!mounted || split == null) return;
    setState(() {
      _split = split.copyWith(
        participants: [
          for (final p in split.participants)
            p.id == participantId
                ? p.copyWith(paid: p.paid, paidAt: p.paidAt, lastRemindedAt: DateTime.now())
                : p,
        ],
      );
    });
  }

  /// "Remind all (N)": stamps every pending, not-yet-reminded friend in one
  /// batch (same bulk semantics as [_sendReminders]) and opens WhatsApp for
  /// just the first pending, not-yet-reminded contact — the spec forbids
  /// firing multiple WhatsApp intents back to back, so the rest wait for
  /// individual taps (surfaced as "Remind next: `<name>`" in the review step).
  Future<void> _remindAllMixed() async {
    final ok = await _ensurePersisted();
    if (!ok || !mounted) return;
    final split = _split;
    if (split == null) return;
    final pendingFriends = split.participants
        .where((p) => !p.paid && !p.isExternalContact && p.lastRemindedAt == null)
        .toList();
    if (pendingFriends.isNotEmpty) {
      await Future.wait(pendingFriends.map((p) => BillSplitRepository.sendReminder(p.id)));
      if (!mounted) return;
      final remindedIds = pendingFriends.map((p) => p.id).toSet();
      setState(() {
        _split = split.copyWith(
          participants: [
            for (final p in split.participants)
              remindedIds.contains(p.id)
                  ? p.copyWith(paid: p.paid, paidAt: p.paidAt, lastRemindedAt: DateTime.now())
                  : p,
          ],
        );
      });
    }
    final nextContact = (_split ?? split)
        .participants
        .where((p) => !p.paid && p.isExternalContact && p.lastRemindedAt == null)
        .firstOrNull;
    if (nextContact != null) {
      await _remindContactViaWhatsApp(nextContact);
    }
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
          selectedContacts: _selectedContacts,
          onToggleFriend: _toggleFriend,
          onSelectGroup: _selectGroup,
          onAddResolvedContacts: _addResolvedContacts,
          onRemoveContact: _removeContact,
          onCreateGroup: _createGroupAndRefresh,
          onContinue: _hasAnyParticipants ? _goToStep1 : null,
          ownerAvatarUrl: _ownerAvatarUrl,
          ownerDisplayName: _ownerDisplayName,
          ownerUserId: _ownerId,
        ),
        BillSplitStepHow(
          transaction: tx,
          friends: _friends,
          contacts: _selectedContacts,
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
                onRemindFriend: _remindFriend,
                onRemindContact: _remindContactViaWhatsApp,
                onRemindAllMixed: _remindAllMixed,
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
