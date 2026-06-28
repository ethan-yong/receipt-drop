import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../domain/logic/badge_catalog.dart';
import 'badge_hex.dart';

class BadgeDetailDialog extends StatelessWidget {
  const BadgeDetailDialog({
    super.key,
    required this.badge,
    required this.earned,
    required this.progress,
  });

  final BadgeDef badge;
  final bool earned;
  final int progress;

  static Future<void> show(
    BuildContext context, {
    required BadgeDef badge,
    required bool earned,
    required int progress,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => BadgeDetailDialog(badge: badge, earned: earned, progress: progress),
    );
  }

  String get _rarityLabel {
    switch (badge.rarity) {
      case BadgeRarity.common:
        return 'COMMON';
      case BadgeRarity.rare:
        return 'RARE';
      case BadgeRarity.epic:
        return 'EPIC';
      case BadgeRarity.legendary:
        return 'LEGENDARY';
    }
  }

  @override
  Widget build(BuildContext context) {
    final ratio = (progress / badge.goal).clamp(0.0, 1.0).toDouble();
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: AppSpacing.heroBorderRadius),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BadgeHex(badge: badge, earned: earned && !badge.comingSoon, size: 96),
            const SizedBox(height: AppSpacing.md),
            Text(badge.label, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_rarityLabel, style: Theme.of(context).textTheme.labelSmall),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              badge.description,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            if (badge.comingSoon) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Coming soon',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            ] else ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(value: ratio, minHeight: 8),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                earned
                    ? 'Earned'
                    : '$progress / ${badge.goal}'
                        '${badge.hint != null ? ' — ${badge.hint}' : ''}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}
