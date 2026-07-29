import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/bootstrap/app_services.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/models/insight_candidate.dart';

IconData insightTypeIcon(String type) {
  switch (type) {
    case 'spending_spike':
      return Icons.trending_up_rounded;
    case 'category_shift':
      return Icons.pie_chart_outline_rounded;
    case 'habit':
      return Icons.place_outlined;
    case 'streak':
      return Icons.local_fire_department_outlined;
    case 'forecast':
      return Icons.timeline_rounded;
    default:
      return Icons.lightbulb_outline_rounded;
  }
}

/// Trailing emoji for an active-state headline (cosmetic; empty state has none).
String insightHeadlineEmoji(String type) {
  switch (type) {
    case 'spending_spike':
      return '📈';
    case 'category_shift':
      return '🔄';
    case 'habit':
      return '☕';
    case 'streak':
      return '🔥';
    case 'forecast':
      return '📊';
    default:
      return '✨';
  }
}

/// Recover curator title/description from a joined `body` (`"$title. $description"`).
({String headline, String? supporting}) splitInsightBody(String body) {
  final trimmed = body.trim();
  final idx = trimmed.indexOf('. ');
  if (idx > 0 && idx <= 60) {
    final head = trimmed.substring(0, idx).trim();
    final rest = trimmed.substring(idx + 2).trim();
    if (head.isNotEmpty && rest.isNotEmpty) {
      return (headline: head, supporting: rest);
    }
  }
  return (headline: trimmed, supporting: null);
}

/// Detail-page freshness line from [createdAt]. Home card stays free of timestamps.
String insightFreshnessLabel(DateTime createdAt, {DateTime? now}) {
  final clock = now ?? DateTime.now();
  final createdDay = DateTime(createdAt.year, createdAt.month, createdAt.day);
  final today = DateTime(clock.year, clock.month, clock.day);
  final days = today.difference(createdDay).inDays;
  if (days <= 0) return 'Updated today';
  if (days == 1) return 'Updated yesterday';
  if (days <= 7) return 'Updated $days days ago';
  return 'Based on your recent receipts';
}

/// Strava/Fitness-style highlight card for Home — always visible.
///
/// Active: tappable → Insights detail. Empty: non-interactive aspirational copy.
class SpendingInsightsCard extends StatelessWidget {
  const SpendingInsightsCard({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CuratedInsight>>(
      stream: AppServices.insights.watchActive(),
      builder: (context, snapshot) {
        final insights = snapshot.data ?? const [];
        final top = insights.isEmpty ? null : insights.first;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: SpendingInsightsCardView(
            key: ValueKey(top?.id ?? 'empty'),
            insight: top,
            onTap: top == null
                ? null
                : () => context.pushNamed('insights'),
          ),
        );
      },
    );
  }
}

/// Presentational body of [SpendingInsightsCard] — testable without AppServices.
class SpendingInsightsCardView extends StatelessWidget {
  const SpendingInsightsCardView({
    super.key,
    this.insight,
    this.onTap,
  });

  /// Top-ranked insight, or null for the empty state.
  final CuratedInsight? insight;

  /// When non-null, the whole card is tappable (active state only).
  final VoidCallback? onTap;

  static const emptyHeadline = 'Your spending story is just getting started';
  static const emptySupporting =
      "Upload more receipts and we'll discover your spending habits.";

  @override
  Widget build(BuildContext context) {
    final active = insight != null;
    final textTheme = Theme.of(context).textTheme;

    final String headline;
    final String? supporting;
    if (active) {
      final split = splitInsightBody(insight!.body);
      final emoji = insightHeadlineEmoji(insight!.type);
      headline = '${split.headline} $emoji';
      supporting = split.supporting;
    } else {
      headline = emptyHeadline;
      supporting = emptySupporting;
    }

    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '✨ What We Noticed',
          style: textTheme.labelLarge?.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          headline,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: textTheme.titleLarge,
        ),
        if (supporting != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            supporting,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
        if (active) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'View insights',
                style: textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryGreenDark,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              const Icon(
                Icons.arrow_forward_rounded,
                size: 16,
                color: AppColors.primaryGreenDark,
              ),
            ],
          ),
        ],
      ],
    );

    // Empty: plain bordered container — no Material/InkWell/ripple.
    if (onTap == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: AppSpacing.cardBorderRadius,
          border: Border.all(color: AppColors.divider),
        ),
        child: column,
      );
    }

    // Active: Material + InkWell so the whole card is tappable with ripple.
    return Material(
      color: AppColors.cardSurface,
      borderRadius: AppSpacing.cardBorderRadius,
      child: InkWell(
        borderRadius: AppSpacing.cardBorderRadius,
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: AppSpacing.cardBorderRadius,
            border: Border.all(color: AppColors.divider),
          ),
          child: column,
        ),
      ),
    );
  }
}
