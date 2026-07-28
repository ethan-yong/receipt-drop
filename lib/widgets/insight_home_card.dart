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

/// Compact single-insight card for Home — invisible when there are no active
/// insights (no empty-state nagging).
class InsightHomeCard extends StatelessWidget {
  const InsightHomeCard({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CuratedInsight>>(
      stream: AppServices.insights.watchActive(),
      builder: (context, snapshot) {
        final insights = snapshot.data ?? const [];
        if (insights.isEmpty) return const SizedBox.shrink();
        final top = insights.first;
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Material(
            color: AppColors.cardSurface,
            borderRadius: AppSpacing.cardBorderRadius,
            child: InkWell(
              borderRadius: AppSpacing.cardBorderRadius,
              onTap: () => context.pushNamed('insights'),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  borderRadius: AppSpacing.cardBorderRadius,
                  border: Border.all(color: AppColors.divider),
                ),
                child: Row(
                  children: [
                    Icon(
                      insightTypeIcon(top.type),
                      color: AppColors.primaryGreen,
                      size: 22,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        top.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.divider,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
