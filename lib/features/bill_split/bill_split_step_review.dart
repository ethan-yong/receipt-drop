import 'package:flutter/material.dart';

import '../../core/theme/bill_split_theme.dart';
import '../../data/repositories/social_repository.dart';
import '../../domain/models/bill_split.dart';
import '../../domain/models/transaction_view.dart';
import '../../widgets/receipt_sheet_widgets.dart';
import 'person_avatar.dart';

/// Step 2: total paid, a collection progress bar, each participant's owed
/// amount with a tappable paid/pending status pill, and a reminder action.
///
/// Two reminder UIs, chosen by whether this split has any external
/// (non-Receipt-Drop) contacts:
/// - Friends-only split: the original single aggregate "Remind N friends"
///   CTA (see `BillSplitRepository.sendReminder` — there is no push-
///   notification delivery; this only stamps a timestamp and flips the
///   button label optimistically before navigating to Insights). Unchanged
///   from before this feature existed.
/// - Mixed split (≥1 external contact): per-participant reminder pills —
///   "Remind" (friend, in-app stamp) or "WhatsApp" (contact, deep link) —
///   plus a "Remind all" CTA that bulk-stamps friends and opens WhatsApp
///   for one contact at a time (never several at once). No auto-exit: the
///   user stays on Review and taps "Done for now" when finished, so
///   reminder progress (persisted via `last_reminded_at`) is resumable
///   simply by reopening the split.
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
    required this.onRemindFriend,
    required this.onRemindContact,
    required this.onRemindAllMixed,
    required this.onDone,
  });

  final TransactionView transaction;
  final BillSplitView split;
  final List<FriendshipView> friends;
  final String? ownerId;
  final bool remindersJustSent;
  final Future<void> Function(String participantId, bool paid) onSetParticipantPaid;
  final VoidCallback onSendReminders;
  final Future<void> Function(String participantId) onRemindFriend;
  final Future<void> Function(BillSplitParticipant participant) onRemindContact;
  final Future<void> Function() onRemindAllMixed;
  final VoidCallback onDone;

  bool get _hasExternalContacts => split.participants.any((p) => p.isExternalContact);

  FriendshipView? _friendFor(String userId) =>
      friends.where((f) => f.otherUserId == userId).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final merchant = transaction.merchantRaw?.trim();
    final owed = split.owedTotalMyr;
    final collected = split.collectedMyr;
    final progressPct = owed > 0 ? (collected / owed).clamp(0.0, 1.0) : 0.0;
    final mixed = _hasExternalContacts;

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
                  friendship: p.isExternalContact ? null : _friendFor(p.friendUserId!),
                  participant: p,
                  onToggle: () => onSetParticipantPaid(p.id, !p.paid),
                  reminderAction: (mixed && !p.paid) ? _reminderPillFor(p) : null,
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
          child: mixed ? _buildMixedFooter(context) : _buildLegacyFooter(),
        ),
      ],
    );
  }

  Widget _reminderPillFor(BillSplitParticipant p) {
    final alreadyReminded = p.lastRemindedAt != null;
    if (p.isExternalContact) {
      return _ReminderPill(
        label: alreadyReminded ? '✓ Opened WhatsApp' : 'WhatsApp',
        done: alreadyReminded,
        onTap: alreadyReminded ? null : () => onRemindContact(p),
      );
    }
    return _ReminderPill(
      label: alreadyReminded ? '✓ Reminder sent' : 'Remind',
      done: alreadyReminded,
      onTap: alreadyReminded ? null : () => onRemindFriend(p.id),
    );
  }

  Widget _buildLegacyFooter() {
    return Column(
      children: [
        ReceiptSheetCta(
          label: remindersJustSent
              ? '✓ Reminders sent'
              : split.allSettled
                  ? 'All settled 🎉'
                  : 'Remind ${split.pendingCount} ${split.pendingCount == 1 ? 'friend' : 'friends'}',
          onPressed: (!split.allSettled && !remindersJustSent) ? onSendReminders : null,
        ),
        ReceiptSheetLink(
          label: 'Done for now',
          color: BillSplitColors.subLight,
          onTap: remindersJustSent ? null : onDone,
        ),
      ],
    );
  }

  Widget _buildMixedFooter(BuildContext context) {
    final unreminded = split.participants.where((p) => !p.paid && p.lastRemindedAt == null);
    final unremindedFriends = unreminded.where((p) => !p.isExternalContact).toList();
    final unremindedContacts = unreminded.where((p) => p.isExternalContact).toList();
    final remainingCount = unremindedFriends.length + unremindedContacts.length;

    String label;
    VoidCallback? onPressed;
    if (split.allSettled) {
      label = 'All settled 🎉';
      onPressed = null;
    } else if (remainingCount == 0) {
      label = 'All reminded';
      onPressed = null;
    } else if (unremindedFriends.isNotEmpty) {
      label = 'Remind all ($remainingCount)';
      onPressed = () => onRemindAllMixed();
    } else {
      label = 'Remind next: ${unremindedContacts.first.contactName ?? 'contact'}';
      onPressed = () => onRemindAllMixed();
    }

    return Column(
      children: [
        ReceiptSheetCta(label: label, onPressed: onPressed),
        ReceiptSheetLink(
          label: 'Done for now',
          color: BillSplitColors.subLight,
          onTap: onDone,
        ),
      ],
    );
  }
}

class _ReminderPill extends StatelessWidget {
  const _ReminderPill({required this.label, required this.done, required this.onTap});

  final String label;
  final bool done;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: done ? BillSplitColors.paidBg : BillSplitColors.gold.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: balooText(
            12,
            FontWeight.w800,
            color: done ? BillSplitColors.paidText : BillSplitColors.ink,
          ),
        ),
      ),
    );
  }
}

class _ParticipantRow extends StatelessWidget {
  const _ParticipantRow({
    required this.friendship,
    required this.participant,
    required this.onToggle,
    this.reminderAction,
  });

  final FriendshipView? friendship;
  final BillSplitParticipant participant;
  final VoidCallback onToggle;
  final Widget? reminderAction;

  @override
  Widget build(BuildContext context) {
    final paid = participant.paid;
    // resolvedDisplayName/resolvedAvatarUrl (BillSplitRepository, batched
    // via get_profile_snippets()) cover any friend-shaped participant,
    // friend or not; the local friendship lookup is a secondary fallback
    // for a stale/failed resolution, not the primary source anymore.
    final displayName = participant.isExternalContact
        ? (participant.contactName ?? 'Contact')
        : (participant.resolvedDisplayName ?? friendship?.otherDisplayName ?? 'Friend');
    final avatarUrl = participant.isExternalContact
        ? null
        : (participant.resolvedAvatarUrl ?? friendship?.otherAvatarUrl);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PersonAvatar(
                avatarUrl: avatarUrl,
                displayName: displayName,
                userId: friendship?.otherUserId ?? participant.id,
                size: 38,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
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
          if (reminderAction != null)
            Padding(
              padding: const EdgeInsets.only(left: 50, top: 6),
              child: reminderAction!,
            ),
        ],
      ),
    );
  }
}
