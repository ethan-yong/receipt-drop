import 'package:flutter/material.dart';

import '../../core/theme/bill_split_theme.dart';
import '../../data/repositories/social_repository.dart';
import '../../domain/logic/bill_split_math.dart';
import '../../domain/models/bill_split.dart';
import '../../domain/models/receipt_line_item.dart';
import '../../domain/models/transaction_view.dart';
import '../../widgets/receipt_sheet_widgets.dart';
import 'person_avatar.dart';

/// Step 1: Equal-split vs. By-item, with a live preview of each person's
/// share either way.
class BillSplitStepHow extends StatelessWidget {
  const BillSplitStepHow({
    super.key,
    required this.transaction,
    required this.friends,
    required this.ownerId,
    this.ownerAvatarUrl,
    required this.includedPersonIds,
    required this.mode,
    required this.canUseByItem,
    required this.itemAssignments,
    required this.onModeChanged,
    required this.onToggleItemPerson,
    required this.creating,
    required this.onReview,
  });

  final TransactionView transaction;
  final List<FriendshipView> friends;
  final String? ownerId;
  final String? ownerAvatarUrl;
  final List<String> includedPersonIds;
  final BillSplitMode mode;
  final bool canUseByItem;
  final Map<String, Set<String>> itemAssignments;
  final ValueChanged<BillSplitMode> onModeChanged;
  final void Function(String lineItemId, String personId) onToggleItemPerson;
  final bool creating;
  final VoidCallback? onReview;

  String _nameFor(String personId) {
    if (personId == ownerId) return 'You';
    final f = friends.where((f) => f.otherUserId == personId).firstOrNull;
    return f?.otherDisplayName ?? 'Friend';
  }

  String? _avatarFor(String personId) {
    if (personId == ownerId) return ownerAvatarUrl;
    final f = friends.where((f) => f.otherUserId == personId).firstOrNull;
    return f?.otherAvatarUrl;
  }

  @override
  Widget build(BuildContext context) {
    final lineItems = transaction.lineItems ?? const [];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: _ModeToggle(
            mode: mode,
            canUseByItem: canUseByItem,
            onChanged: onModeChanged,
          ),
        ),
        if (!canUseByItem && mode == BillSplitMode.equal)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Text(
              'By-item split unlocks once this receipt finishes syncing.',
              style: balooText(12, FontWeight.w600, color: BillSplitColors.sub),
            ),
          ),
        Expanded(
          child: mode == BillSplitMode.equal
              ? _EqualSplitList(
                  totalMyr: transaction.amountMyr ?? 0,
                  personIds: includedPersonIds,
                  nameFor: _nameFor,
                  avatarFor: _avatarFor,
                )
              : _ByItemList(
                  lineItems: lineItems,
                  personIds: includedPersonIds,
                  itemAssignments: itemAssignments,
                  nameFor: _nameFor,
                  avatarFor: _avatarFor,
                  onToggle: onToggleItemPerson,
                ),
        ),
        if (mode == BillSplitMode.byItem)
          _LiveTotalsStrip(
            lineItems: lineItems,
            itemAssignments: itemAssignments,
            personIds: includedPersonIds,
            nameFor: _nameFor,
            avatarFor: _avatarFor,
          ),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: BillSplitColors.tile, width: 1.5)),
          ),
          child: creating
              ? const Center(
                  child: SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                )
              : ReceiptSheetCta(label: 'Review split', onPressed: onReview),
        ),
      ],
    );
  }
}

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({
    required this.mode,
    required this.canUseByItem,
    required this.onChanged,
  });

  final BillSplitMode mode;
  final bool canUseByItem;
  final ValueChanged<BillSplitMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: BillSplitColors.tile,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutBack,
            alignment: mode == BillSplitMode.equal
                ? Alignment.centerLeft
                : Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              child: Container(
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x1E3C3214),
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: _ModeTab(
                  label: 'Equal split',
                  selected: mode == BillSplitMode.equal,
                  onTap: () => onChanged(BillSplitMode.equal),
                ),
              ),
              Expanded(
                child: _ModeTab(
                  label: 'By item',
                  selected: mode == BillSplitMode.byItem,
                  enabled: canUseByItem,
                  onTap: canUseByItem ? () => onChanged(BillSplitMode.byItem) : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ModeTab extends StatelessWidget {
  const _ModeTab({
    required this.label,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = !enabled
        ? BillSplitColors.checkboxBorder
        : selected
            ? BillSplitColors.ink
            : const Color(0xFF9A9284);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: balooText(13.5, FontWeight.w800, color: color),
        ),
      ),
    );
  }
}

class _EqualSplitList extends StatelessWidget {
  const _EqualSplitList({
    required this.totalMyr,
    required this.personIds,
    required this.nameFor,
    required this.avatarFor,
  });

  final double totalMyr;
  final List<String> personIds;
  final String Function(String) nameFor;
  final String? Function(String) avatarFor;

  @override
  Widget build(BuildContext context) {
    final shares = splitEqual(totalMyr: totalMyr, personIds: personIds);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      children: [
        Center(
          child: Column(
            children: [
              Text(
                'Splitting evenly between ${personIds.length} people',
                style: balooText(13, FontWeight.w700, color: BillSplitColors.sub),
              ),
              const SizedBox(height: 4),
              Text(
                'RM ${totalMyr.toStringAsFixed(2)}',
                style: balooText(34, FontWeight.w800, color: BillSplitColors.ink),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        for (final id in personIds)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: Row(
              children: [
                PersonAvatar(
                  avatarUrl: avatarFor(id),
                  displayName: nameFor(id),
                  userId: id,
                  size: 36,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    nameFor(id),
                    style: balooText(15, FontWeight.w700, color: BillSplitColors.body),
                  ),
                ),
                Text(
                  'RM ${(shares[id] ?? 0).toStringAsFixed(2)}',
                  style: balooText(16, FontWeight.w800, color: BillSplitColors.ink),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ByItemList extends StatelessWidget {
  const _ByItemList({
    required this.lineItems,
    required this.personIds,
    required this.itemAssignments,
    required this.nameFor,
    required this.avatarFor,
    required this.onToggle,
  });

  final List<ReceiptLineItem> lineItems;
  final List<String> personIds;
  final Map<String, Set<String>> itemAssignments;
  final String Function(String) nameFor;
  final String? Function(String) avatarFor;
  final void Function(String lineItemId, String personId) onToggle;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      children: [
        Text(
          'Tap who had each item',
          style: balooText(12.5, FontWeight.w700, color: BillSplitColors.sub),
        ),
        const SizedBox(height: 14),
        for (final item in lineItems)
          if (item.id != null) ...[
            _ItemRow(
              item: item,
              personIds: personIds,
              assigned: itemAssignments[item.id] ?? const {},
              nameFor: nameFor,
              avatarFor: avatarFor,
              onToggle: (personId) => onToggle(item.id!, personId),
            ),
            const SizedBox(height: 16),
          ],
      ],
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.personIds,
    required this.assigned,
    required this.nameFor,
    required this.avatarFor,
    required this.onToggle,
  });

  final ReceiptLineItem item;
  final List<String> personIds;
  final Set<String> assigned;
  final String Function(String) nameFor;
  final String? Function(String) avatarFor;
  final void Function(String personId) onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                item.displayLabel,
                style: balooText(14.5, FontWeight.w700, color: BillSplitColors.body),
              ),
            ),
            Text(
              item.priceDisplay,
              style: balooText(14.5, FontWeight.w700, color: BillSplitColors.body),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final personId in personIds) ...[
              _ItemAvatarToggle(
                personId: personId,
                displayName: nameFor(personId),
                avatarUrl: avatarFor(personId),
                on: assigned.contains(personId),
                onTap: () => onToggle(personId),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ],
    );
  }
}

class _ItemAvatarToggle extends StatelessWidget {
  const _ItemAvatarToggle({
    required this.personId,
    required this.displayName,
    required this.avatarUrl,
    required this.on,
    required this.onTap,
  });

  final String personId;
  final String? displayName;
  final String? avatarUrl;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: on ? 1 : 0.5,
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: on ? BillSplitColors.gold : BillSplitColors.checkboxBorder,
              width: 2,
            ),
          ),
          child: PersonAvatar(
            avatarUrl: avatarUrl,
            displayName: displayName,
            userId: personId,
            size: 26,
          ),
        ),
      ),
    );
  }
}

class _LiveTotalsStrip extends StatelessWidget {
  const _LiveTotalsStrip({
    required this.lineItems,
    required this.itemAssignments,
    required this.personIds,
    required this.nameFor,
    required this.avatarFor,
  });

  final List<ReceiptLineItem> lineItems;
  final Map<String, Set<String>> itemAssignments;
  final List<String> personIds;
  final String Function(String) nameFor;
  final String? Function(String) avatarFor;

  @override
  Widget build(BuildContext context) {
    final inputs = [
      for (final item in lineItems)
        if (item.id != null)
          ItemAssignmentInput(
            lineItemId: item.id!,
            priceMyr: item.priceMyr,
            assignedPersonIds: (itemAssignments[item.id] ?? const {}).toList(),
          ),
    ];
    if (inputs.isEmpty) return const SizedBox.shrink();
    final totals = splitByItems(inputs);

    return SizedBox(
      height: 40,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        children: [
          for (final id in personIds)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Container(
                padding: const EdgeInsets.fromLTRB(6, 6, 10, 6),
                decoration: BoxDecoration(
                  color: BillSplitColors.tile,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PersonAvatar(
                      avatarUrl: avatarFor(id),
                      displayName: nameFor(id),
                      userId: id,
                      size: 20,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'RM ${(totals[id] ?? 0).toStringAsFixed(2)}',
                      style: balooText(12, FontWeight.w700, color: BillSplitColors.ink),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
