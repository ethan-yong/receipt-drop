import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/bootstrap/app_prefs.dart';
import '../../core/bootstrap/app_services.dart';
import '../../core/config/env.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/avatar_repository.dart';
import '../../data/repositories/social_repository.dart';
import '../../domain/logic/avatar_mood.dart';
import '../../domain/logic/badge_catalog.dart';
import '../../domain/logic/badge_progress.dart';
import '../../domain/models/transaction_view.dart';
import '../../features/share/receipt_capture_flow.dart';
import '../../widgets/adaptive_sync_banner.dart';
import '../../widgets/receipt_card_carousel.dart';
import '../../widgets/share_coach_mark.dart';
import '../../widgets/top_badges_grid.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  var _showCoachMark =
      AppPrefs.shareCoachMarkPending && !AppPrefs.shareCoachMarkSeen;
  BadgeCatalog? _badgeCatalog;

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      AppServices.transactions.seedReceiptShowcaseIfEmpty();
    }
    BadgeCatalog.loadBundled().then((catalog) {
      if (mounted) setState(() => _badgeCatalog = catalog);
    });
  }

  Future<void> _retrySync() async {
    await AppServices.transactions.retryStuckSync();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      body: SafeArea(
        child: StreamBuilder<List<TransactionView>>(
          stream: AppServices.transactions.watchAll(),
          builder: (context, snapshot) {
            final rows = snapshot.data ?? const [];
            final stuck = rows.where((t) => t.isStuckSync).length;
            final needsReview = rows.where((t) => t.needsReview).length;
            final today = todaysTransactions(rows, DateTime.now());
            final mood = deriveAvatarMood(today);
            final badgeCatalog = _badgeCatalog;
            final badgeEntries = badgeCatalog == null
                ? null
                : computeBadgeEntries(badgeCatalog, rows);

            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              AvatarRepository.syncCurrentMood(mood.name);
              AvatarRepository.syncCurrentStreak(currentDailyStreak(rows));
              if (badgeEntries != null) {
                AvatarRepository.syncBadgeCount(
                  badgeEntries.where((e) => e.earned).length,
                );
              }
              if (Env.hasLeaderboardApiConfig) {
                SocialRepository.syncLeaderboardScore();
              }
            });

            return Column(
              children: [
                if (_showCoachMark)
                  ShareCoachMark(
                    onDismiss: () => setState(() => _showCoachMark = false),
                  ),
                AdaptiveSyncBanner(stuckCount: stuck, onRetry: _retrySync),
                if (needsReview > 0)
                  _NeedsReviewBanner(
                    count: needsReview,
                    onTap: () => context.pushNamed('review'),
                  ),
                Expanded(
                  child: SingleChildScrollView(
                    clipBehavior: Clip.none,
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.xs,
                      AppSpacing.md,
                      AppSpacing.xl,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Align(
                          alignment: Alignment.centerRight,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _DropCountPill(count: today.length),
                              const SizedBox(width: AppSpacing.sm),
                              _RoundIconButton(
                                icon: Icons.settings_outlined,
                                onTap: () => context.pushNamed('settings'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          "TODAY'S RECEIPTS",
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                letterSpacing: 1.2,
                              ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        ReceiptCardCarousel(transactions: today),
                        const SizedBox(height: AppSpacing.lg),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: () => ReceiptCaptureFlow.start(context),
                            style: FilledButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: AppSpacing.heroBorderRadius,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                            ),
                            child: Text(
                              'Drop Receipt',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'BADGES',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelMedium
                                      ?.copyWith(letterSpacing: 1.2),
                                ),
                                Text(
                                  'Top 6 — drag to reorder',
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ],
                            ),
                            TextButton(
                              onPressed: () => context.pushNamed('badges'),
                              child: const Row(
                                children: [
                                  Text('View All'),
                                  Icon(Icons.chevron_right, size: 16),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        if (badgeEntries != null)
                          TopBadgesGrid(entries: badgeEntries),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _NeedsReviewBanner extends StatelessWidget {
  const _NeedsReviewBanner({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        0,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppSpacing.chipBorderRadius,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: AppColors.badgePendingBg,
            borderRadius: AppSpacing.chipBorderRadius,
          ),
          child: Row(
            children: [
              const Icon(
                Icons.rate_review_outlined,
                size: 18,
                color: AppColors.badgePendingText,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  count == 1
                      ? '1 receipt needs review'
                      : '$count receipts need review',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.badgePendingText,
                      ),
                ),
              ),
              const Icon(
                Icons.chevron_right,
                size: 18,
                color: AppColors.badgePendingText,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DropCountPill extends StatelessWidget {
  const _DropCountPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: AppSpacing.chipBorderRadius,
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.auto_awesome, size: 14),
          const SizedBox(width: 4),
          Text('$count drops', style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.divider),
        ),
        child: Icon(icon, size: 18, color: AppColors.textPrimary),
      ),
    );
  }
}
