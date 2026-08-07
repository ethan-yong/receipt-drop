import 'package:flutter/material.dart';

import '../../core/theme/bill_split_theme.dart';
import '../../data/repositories/social_repository.dart';
import '../../domain/models/friend_group.dart';
import '../../domain/models/transaction_view.dart';
import '../../widgets/receipt_sheet_widgets.dart';
import 'person_avatar.dart';

/// Step 0: receipt summary, group quick-select, and the friend
/// checkbox list ("You" is always included and non-toggleable).
class BillSplitStepWho extends StatelessWidget {
  const BillSplitStepWho({
    super.key,
    required this.transaction,
    required this.friends,
    required this.groups,
    required this.selectedFriendIds,
    required this.onToggleFriend,
    required this.onSelectGroup,
    required this.onCreateGroup,
    required this.onContinue,
  });

  final TransactionView transaction;
  final List<FriendshipView> friends;
  final List<FriendGroupView> groups;
  final Set<String> selectedFriendIds;
  final ValueChanged<String> onToggleFriend;
  final ValueChanged<FriendGroupView> onSelectGroup;
  final VoidCallback onCreateGroup;
  final VoidCallback? onContinue;

  bool _isGroupActive(FriendGroupView g) {
    final memberIds = g.members.map((m) => m.userId).toSet();
    return memberIds.length == selectedFriendIds.length &&
        memberIds.every(selectedFriendIds.contains);
  }

  @override
  Widget build(BuildContext context) {
    final merchant = transaction.merchantRaw?.trim();
    final itemCount = transaction.lineItems?.length ?? 0;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: BillSplitColors.tile,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE2885C),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text('🧾', style: TextStyle(fontSize: 18)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            merchant != null && merchant.isNotEmpty ? merchant : 'Receipt',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                balooText(15, FontWeight.w800, color: BillSplitColors.ink),
                          ),
                          Text(
                            '$itemCount items',
                            style:
                                balooText(12.5, FontWeight.w600, color: BillSplitColors.sub),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      'RM ${(transaction.amountMyr ?? 0).toStringAsFixed(2)}',
                      style: balooText(17, FontWeight.w800, color: BillSplitColors.ink),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _SectionLabel(
                friends.isEmpty ? 'Groups' : 'Split with a group',
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final g in groups)
                    _GroupChip(
                      group: g,
                      isActive: _isGroupActive(g),
                      onTap: () => onSelectGroup(g),
                    ),
                  _NewGroupChip(onTap: onCreateGroup),
                ],
              ),
              const SizedBox(height: 20),
              const _SectionLabel('Or pick people'),
              const SizedBox(height: 6),
              const _YouRow(),
              if (friends.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Add friends first to split a bill with them.',
                    style: balooText(13, FontWeight.w600, color: BillSplitColors.sub),
                  ),
                )
              else
                for (final f in friends)
                  _FriendRow(
                    friendship: f,
                    selected: selectedFriendIds.contains(f.otherUserId),
                    onTap: () => onToggleFriend(f.otherUserId),
                  ),
              const SizedBox(height: 8),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: BillSplitColors.tile, width: 1.5)),
          ),
          child: ReceiptSheetCta(
            label: 'Continue with ${selectedFriendIds.length + 1} people',
            onPressed: onContinue,
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: balooText(
        12,
        FontWeight.w800,
        color: BillSplitColors.subLight,
        letterSpacing: .5,
      ),
    );
  }
}

class _YouRow extends StatelessWidget {
  const _YouRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          const PersonAvatar(isYou: true, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('You', style: balooText(15, FontWeight.w800, color: BillSplitColors.ink)),
                Text(
                  'Paid the bill',
                  style: balooText(12, FontWeight.w600, color: BillSplitColors.subLight),
                ),
              ],
            ),
          ),
          Text(
            'Included',
            style: balooText(12, FontWeight.w700, color: BillSplitColors.subLight),
          ),
        ],
      ),
    );
  }
}

class _FriendRow extends StatelessWidget {
  const _FriendRow({
    required this.friendship,
    required this.selected,
    required this.onTap,
  });

  final FriendshipView friendship;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            PersonAvatar(
              isYou: false,
              displayName: friendship.otherDisplayName,
              avatarConfigJson: friendship.otherAvatarConfigJson,
              size: 40,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                friendship.otherDisplayName ?? 'Friend',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: balooText(15, FontWeight.w800, color: BillSplitColors.ink),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: selected ? BillSplitColors.gold : Colors.white,
                border: Border.all(
                  color: selected ? BillSplitColors.gold : BillSplitColors.checkboxBorder,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(7),
              ),
              alignment: Alignment.center,
              child: selected
                  ? const Icon(Icons.check, size: 15, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupChip extends StatelessWidget {
  const _GroupChip({required this.group, required this.isActive, required this.onTap});

  final FriendGroupView group;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 14, 8),
        decoration: BoxDecoration(
          color: isActive ? BillSplitColors.gold : Colors.white,
          border: Border.all(
            color: isActive ? BillSplitColors.gold : const Color(0xFFE9DDCA),
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 24,
              child: Row(
                children: [
                  for (final m in group.members.take(3))
                    Padding(
                      padding: const EdgeInsets.only(left: -8),
                      child: PersonAvatar(
                        isYou: false,
                        displayName: m.displayName,
                        avatarConfigJson: m.avatarConfigJson,
                        size: 24,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              group.name,
              style: balooText(
                13,
                FontWeight.w700,
                color: isActive ? BillSplitColors.ctaText : BillSplitColors.body,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NewGroupChip extends StatelessWidget {
  const _NewGroupChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFE9DDCA), width: 1.5),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add, size: 16, color: BillSplitColors.body),
            const SizedBox(width: 4),
            Text(
              'New group',
              style: balooText(13, FontWeight.w700, color: BillSplitColors.body),
            ),
          ],
        ),
      ),
    );
  }
}
