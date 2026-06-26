import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// Small pill button for a feed post's fire/laugh/eyes reactions — port of
/// Impact Drops' inline ReactionChip.
class ReactionChip extends StatelessWidget {
  const ReactionChip({
    super.key,
    required this.emoji,
    required this.count,
    this.onTap,
  });

  final String emoji;
  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 6),
            Text(
              '$count',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
