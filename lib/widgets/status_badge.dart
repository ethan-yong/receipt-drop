import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

enum TransactionBadgeKind { pendingSync, needsAmount }

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.kind});

  final TransactionBadgeKind kind;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, label) = switch (kind) {
      TransactionBadgeKind.pendingSync => (
          AppColors.badgePendingBg,
          AppColors.badgePendingText,
          'pending sync',
        ),
      TransactionBadgeKind.needsAmount => (
          AppColors.badgeNeedsAmountBg,
          AppColors.badgeNeedsAmountText,
          'needs amount',
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
              fontSize: 10,
            ),
      ),
    );
  }
}
