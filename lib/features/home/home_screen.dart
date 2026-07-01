import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/bootstrap/app_prefs.dart';
import '../../core/bootstrap/app_services.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/avatar_repository.dart';
import '../../domain/logic/avatar_mood.dart';
import '../../domain/logic/badge_catalog.dart';
import '../../domain/logic/badge_progress.dart';
import '../../domain/logic/diorama_theme.dart';
import '../../domain/models/avatar_config.dart';
import '../../domain/models/transaction_view.dart';
import '../../features/share/receipt_capture_flow.dart';
import '../../widgets/adaptive_sync_banner.dart';
import '../../widgets/pixel_avatar.dart';
import '../../widgets/share_coach_mark.dart';
import '../../widgets/themed_scene_background.dart';
import '../../widgets/top_badges_grid.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  var _showCoachMark =
      AppPrefs.shareCoachMarkPending && !AppPrefs.shareCoachMarkSeen;
  AvatarConfig? _avatarConfig;
  BadgeCatalog? _badgeCatalog;

  @override
  void initState() {
    super.initState();
    AvatarRepository.getAvatarConfig().then((config) {
      if (mounted) setState(() => _avatarConfig = config);
    });
    BadgeCatalog.loadBundled().then((catalog) {
      if (mounted) setState(() => _badgeCatalog = catalog);
    });
  }

  Future<void> _retrySync() async {
    await AppServices.transactions.retryStuckSync();
  }

  TransactionView? _mostRecent(List<TransactionView> rows) {
    if (rows.isEmpty) return null;
    return rows.reduce(
      (a, b) => a.occurredAt.isAfter(b.occurredAt) ? a : b,
    );
  }

  @override
  Widget build(BuildContext context) {
    final avatarConfig = _avatarConfig;
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      body: SafeArea(
        child: StreamBuilder<List<TransactionView>>(
          stream: AppServices.transactions.watchAll(),
          builder: (context, snapshot) {
            final rows = snapshot.data ?? const [];
            final stuck = rows.where((t) => t.isStuckSync).length;
            final today = todaysTransactions(rows, DateTime.now());
            final mood = deriveAvatarMood(today);
            final theme = getThemeForCategory(_mostRecent(rows)?.effectiveCategory);
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
            });
            final isIdle = theme.id == DioramaThemeId.idle;

            return Column(
              children: [
                if (_showCoachMark)
                  ShareCoachMark(
                    onDismiss: () => setState(() => _showCoachMark = false),
                  ),
                AdaptiveSyncBanner(stuckCount: stuck, onRetry: _retrySync),
                Expanded(
                  child: SingleChildScrollView(
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
                        const SizedBox(height: AppSpacing.sm),
                        Center(
                          child: SizedBox(
                            width: 280,
                            height: 280,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                ThemedSceneBackground(
                                  theme: theme,
                                  borderRadius: AppSpacing.heroBorderRadius,
                                ),
                                if (avatarConfig != null)
                                  PixelAvatar(
                                    mood: mood,
                                    config: avatarConfig,
                                    size: 180,
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Center(
                          child: Column(
                            children: [
                              Text(
                                isIdle ? 'No scene yet' : theme.label,
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                      letterSpacing: 1.2,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                                child: Text(
                                  theme.caption,
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              OutlinedButton.icon(
                                onPressed: () => context.pushNamed('avatar'),
                                icon: const Icon(Icons.auto_fix_high, size: 16),
                                label: const Text('Customize avatar'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.md,
                                    vertical: AppSpacing.sm,
                                  ),
                                  shape: const StadiumBorder(),
                                ),
                              ),
                            ],
                          ),
                        ),
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
