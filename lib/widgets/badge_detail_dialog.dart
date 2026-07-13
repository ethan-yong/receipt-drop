import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../domain/logic/badge_catalog.dart';
import 'badge_hex.dart';

const _kTierColors = [
  Color(0xFFC68A4B),
  Color(0xFF9AA3AD),
  Color(0xFFE0AA3E),
];

class BadgeDetailDialog extends StatelessWidget {
  const BadgeDetailDialog({
    super.key,
    required this.badge,
    required this.earned,
    required this.progress,
    this.tier = 0,
  });

  final BadgeDef badge;
  final bool earned;
  final int progress;
  final int tier;

  static Future<void> show(
    BuildContext context, {
    required BadgeDef badge,
    required bool earned,
    required int progress,
    int tier = 0,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => BadgeDetailDialog(
        badge: badge,
        earned: earned,
        progress: progress,
        tier: tier,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tierGoals = badge.tierGoals;
    final nextGoal = tier < tierGoals.length ? tierGoals[tier] : tierGoals.last;
    final baseGoal = tier > 0 ? tierGoals[tier - 1] : 0;
    final ratio = ((progress - baseGoal) / (nextGoal - baseGoal)).clamp(0.0, 1.0);

    final tierColor = tier > 0 ? _kTierColors[tier - 1] : const Color(0xFFA69F91);
    final tierLabel = tier > 0 ? 'TIER $tier / ${tierGoals.length}' : 'LOCKED';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: AppSpacing.heroBorderRadius),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BadgeHex(
              badge: badge,
              earned: earned && !badge.comingSoon,
              tier: tier,
              size: 96,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(badge.label, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: tierColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                tierLabel,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: tierColor,
                      fontWeight: FontWeight.w800,
                    ),
              ),
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
              _TierRoadmap(
                tierGoals: tierGoals,
                tierUnit: badge.tierUnit,
                currentTier: tier,
                progress: progress,
              ),
              const SizedBox(height: AppSpacing.sm),
              if (tier < tierGoals.length) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 8,
                    color: tierColor,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '$progress / $nextGoal ${badge.tierUnit}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ] else ...[
                Text(
                  'All tiers unlocked!',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
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

class _TierRoadmap extends StatelessWidget {
  const _TierRoadmap({
    required this.tierGoals,
    required this.tierUnit,
    required this.currentTier,
    required this.progress,
  });

  final List<int> tierGoals;
  final String tierUnit;
  final int currentTier;
  final int progress;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(tierGoals.length, (i) {
        final earned = i < currentTier;
        final color = earned ? _kTierColors[i] : AppColors.divider;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Column(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: earned ? color : AppColors.textMuted,
                    width: 1.5,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${i + 1}',
                  style: TextStyle(
                    color: earned ? Colors.white : AppColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${tierGoals[i]}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: earned ? color : AppColors.textMuted,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        );
      }),
    );
  }
}
