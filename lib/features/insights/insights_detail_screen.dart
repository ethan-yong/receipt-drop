import 'package:flutter/material.dart';

import '../../core/bootstrap/app_services.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/insights_worker.dart';
import '../../domain/models/insight_candidate.dart';
import '../../widgets/spending_insights_card.dart';

/// Detail view listing up to 3 curated insights with per-item dismiss.
class InsightsDetailScreen extends StatelessWidget {
  const InsightsDetailScreen({super.key});

  Future<void> _dismiss(BuildContext context, CuratedInsight insight) async {
    await AppServices.insights.dismissLocally(insight.id);
    // Fire-and-forget cloud sync of dismiss state on next InsightsWorker run.
    // Also attempt an immediate best-effort note so volume guard still works.
    await InsightsWorker.noteSyncedTransaction();
  }

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
              return Dismissible(
                key: ValueKey(insight.id),
                direction: DismissDirection.endToStart,
                onDismissed: (_) => _dismiss(context, insight),
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: Colors.red.shade100,
                    borderRadius: AppSpacing.cardBorderRadius,
                  ),
                  child: const Icon(Icons.close_rounded),
                ),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.cardSurface,
                    borderRadius: AppSpacing.cardBorderRadius,
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        insightTypeIcon(insight.type),
                        color: AppColors.primaryGreen,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          insight.body,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Dismiss',
                        onPressed: () => _dismiss(context, insight),
                        icon: const Icon(Icons.close_rounded, size: 20),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
