import 'package:flutter/material.dart';

import '../../core/theme/bill_split_theme.dart';
import '../../data/repositories/social_repository.dart';
import '../../domain/models/bill_split.dart';
import '../../domain/models/transaction_view.dart';
import '../../widgets/receipt_sheet_widgets.dart';
import 'person_avatar.dart';

/// Step 2: total paid, a collection progress bar, each friend's owed
/// amount with a tappable paid/pending status pill, and a best-effort
/// "remind" action (see `BillSplitRepository.sendReminder` — there is no
/// push-notification delivery; this only stamps a timestamp and flips the
/// button label optimistically).
class BillSplitStepReview extends StatelessWidget {
  const BillSplitStepReview({
    super.key,
    required this.transaction,
    required this.split,
    required this.friends,
    required this.ownerId,
    required this.remindersJustSent,
    required this.onSetParticipantPaid,
    required this.onSendReminders,
    required this.onDone,
  });

  final TransactionView transaction;
  final BillSplitView split;
  final List<FriendshipView> friends;
  final String? ownerId;
  final bool remindersJustSent;
  final Future<void> Function(String participantId, bool paid) onSetParticipantPaid;
  final VoidCallback onSendReminders;
  final VoidCallback onDone;

  FriendshipView? _friendFor(String userId) =>
      friends.where((f) => f.otherUserId == userId).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final merchant = transaction.merchantRaw?.trim();
    final owed = split.owedTotalMyr;
    final collected = split.collectedMyr;
    final progressPct = owed > 0 ? (collected / owed).clamp(0.0, 1.0) : 0.0;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
            children: [
              Center(
                child: Column(
                  children: [
                    Text(
                      'You paid',
                      style: balooText(13, FontWeight.w700, color: BillSplitColors.sub),
                    ),
                    Text(
                      'RM ${split.totalMyr.toStringAsFixed(2)}',
                      style: balooText(30, FontWeight.w800, color: BillSplitColors.ink),
                    ),
                    if (merchant != null && merchant.isNotEmpty)
                      Text(
                        'at $merchant',
                        style:
                            balooText(13, FontWeight.w700, color: BillSplitColors.sub),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Collected',
                    style: balooText(12.5, FontWeight.w700, color: BillSplitColors.sub),
                  ),
                  Text(
                    'RM ${collected.toStringAsFixed(2)} of RM ${owed.toStringAsFixed(2)}',
                    style: balooText(12.5, FontWeight.w800, color: BillSplitColors.ink),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  height: 8,
                  child: Stack(
                    children: [
                      Container(color: BillSplitColors.tile),
                      AnimatedFractionallySizedBox(
                        duration: const Duration(milliseconds: 550),
                        curve: Curves.easeOutCubic,
                        widthFactor: progressPct,
                        child: Container(color: BillSplitColors.progressFill),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              for (final p in split.participants)
                _ParticipantRow(
                  friendship: _friendFor(p.friendUserId),
                  participant: p,
                  onToggle: () => onSetParticipantPaid(p.id, !p.paid),
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
          child: Column(
            children: [
              ReceiptSheetCta(
                label: remindersJustSent
                    ? 'Reminders sent ✓'
                    : split.allSettled
                        ? 'All settled 🎉'
                        : 'Remind ${split.pendingCount} ${split.pendingCount == 1 ? 'friend' : 'friends'}',
                onPressed:
                    (!split.allSettled && !remindersJustSent) ? onSendReminders : null,
              ),
              ReceiptSheetLink(
                label: 'Done for now',
                color: BillSplitColors.subLight,
                onTap: onDone,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ParticipantRow extends StatelessWidget {
  const _ParticipantRow({
    required this.friendship,
    required this.participant,
    required this.onToggle,
  });

  final FriendshipView? friendship;
  final BillSplitParticipant participant;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final paid = participant.paid;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          PersonAvatar(
            avatarUrl: friendship?.otherAvatarUrl,
            displayName: friendship?.otherDisplayName,
            userId: friendship?.otherUserId ?? participant.friendUserId,
            size: 38,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  friendship?.otherDisplayName ?? 'Friend',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: balooText(15, FontWeight.w800, color: BillSplitColors.ink),
                ),
                Text(
                  'owes you RM ${participant.shareMyr.toStringAsFixed(2)}',
                  style: balooText(12.5, FontWeight.w600, color: BillSplitColors.sub),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onToggle,
            child: TweenAnimationBuilder<double>(
              key: ValueKey(paid),
              tween: Tween(begin: paid ? 1.16 : 1.0, end: 1.0),
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOut,
              builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: paid ? BillSplitColors.paidBg : BillSplitColors.tile,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  paid ? 'Paid ✓' : 'Pending',
                  style: balooText(
                    12.5,
                    FontWeight.w800,
                    color: paid ? BillSplitColors.paidText : BillSplitColors.sub,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
