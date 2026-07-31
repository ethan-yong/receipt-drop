import 'package:flutter/material.dart';

import '../../core/bootstrap/app_services.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/logic/insight_badge.dart';
import '../../domain/models/insight_candidate.dart';
import '../../widgets/insight_visualization.dart';
import '../../widgets/spending_insights_card.dart';
import '../../widgets/typewriter_text.dart';

/// Detail view listing up to 3 curated insights.
class InsightsDetailScreen extends StatelessWidget {
  const InsightsDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(title: const Text('Insights')),
      body: StreamBuilder<List<CuratedInsight>>(
        stream: AppServices.insights.watchActive(),
        builder: (context, snapshot) {
          final insights = snapshot.data ?? const [];
          if (insights.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text(
                  SpendingInsightsCardView.emptyHeadline,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
              ),
            );
          }

          // Prefer rank-0; fall back to newest createdAt.
          final freshest = insights.reduce((a, b) {
            if (a.rank != b.rank) return a.rank < b.rank ? a : b;
            return a.createdAt.isAfter(b.createdAt) ? a : b;
          });
          final freshness = insightFreshnessLabel(freshest.createdAt);

          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: insights.length + 1,
            separatorBuilder: (_, index) {
              if (index == 0) return const SizedBox(height: AppSpacing.md);
              return const SizedBox(height: AppSpacing.sm);
            },
            itemBuilder: (context, index) {
              if (index == 0) {
                return Text(
                  freshness,
                  style: Theme.of(context).textTheme.labelSmall,
                );
              }
              final insight = insights[index - 1];
              return _InsightCard(
                key: ValueKey(insight.id),
                insight: insight,
              );
            },
          );
        },
      ),
    );
  }
}

/// A single curated insight: headline + optional metric badge, its chart
/// (if any), and a typed-out supporting sentence. The forecast type gets a
/// dark card treatment to read as a distinct "ahead" moment.
class _InsightCard extends StatelessWidget {
  const _InsightCard({super.key, required this.insight});

  final CuratedInsight insight;

  @override
  Widget build(BuildContext context) {
    final dark = insight.type == 'forecast';
    final split = splitInsightBody(insight.body);
    final badge = insightBadgeFor(insight.type, insight.visualization);
    final textTheme = Theme.of(context).textTheme;
    final headlineColor = dark ? Colors.white : AppColors.textPrimary;
    final supportingColor =
        dark ? AppColors.onDarkCardSecondary : AppColors.textSecondary;
    final iconColor =
        dark ? AppColors.insightNeutralOnDark : AppColors.primaryGreenDark;

    return Container(
      width: double.infinity,
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(
        color: dark ? AppColors.textPrimary : AppColors.cardSurface,
        borderRadius: AppSpacing.cardBorderRadius,
        border: dark ? null : Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.18 : 0.06),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(insightTypeIcon(insight.type), size: 20, color: iconColor),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  split.headline,
                  style: textTheme.titleSmall?.copyWith(color: headlineColor),
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: AppSpacing.sm),
                _InsightBadgeLabel(badge: badge, dark: dark),
              ],
            ],
          ),
          if (insight.visualization != null) ...[
            const SizedBox(height: AppSpacing.sm),
            InsightVisualization(visualization: insight.visualization),
          ],
          if (split.supporting != null) ...[
            const SizedBox(height: AppSpacing.sm),
            TypewriterText(
              text: split.supporting!,
              style: textTheme.bodySmall?.copyWith(color: supportingColor),
            ),
          ],
        ],
      ),
    );
  }
}

class _InsightBadgeLabel extends StatelessWidget {
  const _InsightBadgeLabel({required this.badge, required this.dark});

  final InsightBadge badge;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final color = switch (badge.direction) {
      InsightBadgeDirection.up => AppColors.insightAlert,
      InsightBadgeDirection.down => AppColors.insightGood,
      InsightBadgeDirection.neutral =>
        dark ? AppColors.insightNeutralOnDark : AppColors.primaryGreenDark,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          badge.label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
        ),
        if (badge.direction != InsightBadgeDirection.neutral) ...[
          const SizedBox(width: 3),
          Icon(
            badge.direction == InsightBadgeDirection.up
                ? Icons.arrow_upward_rounded
                : Icons.arrow_downward_rounded,
            size: 14,
            color: color,
          ),
        ],
      ],
    );
  }
}
