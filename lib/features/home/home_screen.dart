import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/bootstrap/app_prefs.dart';
import '../../core/bootstrap/app_services.dart';
import '../../core/config/env.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/avatar_repository.dart';
import '../../data/repositories/badge_repository.dart';
import '../../data/repositories/social_repository.dart';
import '../../domain/logic/avatar_mood.dart';
import '../../domain/logic/badge_catalog.dart';
import '../../domain/logic/badge_progress.dart';
import '../../domain/models/pending_import_model.dart';
import '../../domain/models/transaction_view.dart';
import '../../features/share/receipt_capture_flow.dart';
import '../../widgets/adaptive_sync_banner.dart';
import '../../widgets/pending_drop_indicator.dart';
import '../../widgets/receipt_card_carousel.dart';
import '../../widgets/share_coach_mark.dart';
import '../../widgets/spending_insights_card.dart';
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
  final _badgeStream = BadgeRepository.streamAll();
  double _topOverlayHeight = 0;

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

  void _onTopOverlayHeightChanged(double height) {
    if (height == _topOverlayHeight) return;
    setState(() => _topOverlayHeight = height);
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

            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              AvatarRepository.syncCurrentMood(mood.name);
              AvatarRepository.syncCurrentStreak(currentDailyStreak(rows));
              // badge_count is now maintained by the Postgres trigger on transactions;
              // no client-side syncBadgeCount needed.
              if (Env.hasLeaderboardApiConfig) {
                SocialRepository.syncLeaderboardScore();
              }
            });

            return Stack(
              children: [
                Positioned.fill(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      _topOverlayHeight + AppSpacing.xs,
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
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "TODAY'S RECEIPTS",
                              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                    letterSpacing: 1.2,
                                  ),
                            ),
                            _ViewHistoryButton(
                              onTap: () => context.pushNamed('history'),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        ReceiptCardCarousel(transactions: today),
                        const SizedBox(height: AppSpacing.md),
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
                        const SpendingInsightsCard(),
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
                        if (_badgeCatalog != null)
                          StreamBuilder<List<Map<String, dynamic>>>(
                            stream: _badgeStream,
                            builder: (context, badgeSnapshot) {
                              final badgeCatalog = _badgeCatalog!;
                              final badgeRows = badgeSnapshot.data ?? const [];
                              final entries = badgeCatalog.badges.map((badge) {
                                final row = badgeRows
                                    .where((r) => r['badge_id'] == badge.id)
                                    .firstOrNull;
                                return (
                                  badge: badge,
                                  progress: (row?['progress'] as num?)?.toInt() ?? 0,
                                  earned: row?['earned'] as bool? ?? false,
                                  tier: (row?['unlocked_tier'] as int?) ?? 0,
                                );
                              }).toList();
                              return TopBadgesGrid(entries: entries);
                            },
                          ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _HomeTopOverlay(
                    showCoachMark: _showCoachMark,
                    onDismissCoachMark: () =>
                        setState(() => _showCoachMark = false),
                    stuckCount: stuck,
                    onRetrySync: _retrySync,
                    needsReview: needsReview,
                    onHeightChanged: _onTopOverlayHeightChanged,
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

/// Pinned home-screen alerts that stay above scrolling content.
class _HomeTopOverlay extends StatefulWidget {
  const _HomeTopOverlay({
    required this.showCoachMark,
    required this.onDismissCoachMark,
    required this.stuckCount,
    required this.onRetrySync,
    required this.needsReview,
    required this.onHeightChanged,
  });

  final bool showCoachMark;
  final VoidCallback onDismissCoachMark;
  final int stuckCount;
  final VoidCallback onRetrySync;
  final int needsReview;
  final ValueChanged<double> onHeightChanged;

  @override
  State<_HomeTopOverlay> createState() => _HomeTopOverlayState();
}

class _HomeTopOverlayState extends State<_HomeTopOverlay> {
  final _key = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reportHeight());
  }

  @override
  void didUpdateWidget(covariant _HomeTopOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reportHeight());
  }

  void _reportHeight() {
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    widget.onHeightChanged(box.size.height);
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (_) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _reportHeight());
        return true;
      },
      child: SizeChangedLayoutNotifier(
        child: DecoratedBox(
          key: _key,
          decoration: const BoxDecoration(color: AppColors.scaffold),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.showCoachMark)
                ShareCoachMark(onDismiss: widget.onDismissCoachMark),
              AdaptiveSyncBanner(
                stuckCount: widget.stuckCount,
                onRetry: widget.onRetrySync,
              ),
              StreamBuilder<List<PendingImportModel>>(
                stream: AppServices.pendingImports.watchAll(),
                builder: (context, pendingSnapshot) {
                  WidgetsBinding.instance
                      .addPostFrameCallback((_) => _reportHeight());
                  final pending = pendingSnapshot.data ?? const [];
                  if (pending.isEmpty) return const SizedBox.shrink();
                  return PendingDropIndicator(
                    pending: pending,
                    onTap: () => context.pushNamed('pending-imports'),
                  );
                },
              ),
              if (widget.needsReview > 0)
                _NeedsReviewBanner(
                  count: widget.needsReview,
                  onTap: () => context.pushNamed('review'),
                ),
            ],
          ),
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

/// Small boxed text link next to "TODAY'S RECEIPTS" that opens the
/// receipts-only history view (`ReceiptHistoryScreen`), distinct from the
/// full Dashboard (which pairs the same receipts with charts).
class _ViewHistoryButton extends StatelessWidget {
  const _ViewHistoryButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppSpacing.chipBorderRadius,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: AppSpacing.chipBorderRadius,
          border: Border.all(color: AppColors.divider),
        ),
        child: Text(
          'VIEW HISTORY',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                letterSpacing: 0.8,
              ),
        ),
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
