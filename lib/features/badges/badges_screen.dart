import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../data/repositories/badge_repository.dart';
import '../../domain/logic/badge_catalog.dart';
import '../../widgets/achievement_progress_card.dart';
import '../../widgets/badge_detail_dialog.dart';
import '../../widgets/skeleton.dart';

class BadgesScreen extends StatefulWidget {
  const BadgesScreen({super.key});

  @override
  State<BadgesScreen> createState() => _BadgesScreenState();
}

class _BadgesScreenState extends State<BadgesScreen> {
  BadgeCatalog? _catalog;

  @override
  void initState() {
    super.initState();
    BadgeCatalog.loadBundled().then((c) {
      if (mounted) setState(() => _catalog = c);
    });
  }

  @override
  Widget build(BuildContext context) {
    final catalog = _catalog;
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text('Badges'),
      ),
      body: catalog == null
          ? const _BadgesSkeleton()
          : StreamBuilder<List<Map<String, dynamic>>>(
              stream: BadgeRepository.streamAll(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    snapshot.data == null) {
                  return const _BadgesSkeleton();
                }

                final rows = snapshot.data ?? const [];

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final twoCol = constraints.maxWidth > 700;
                    return CustomScrollView(
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.md,
                            AppSpacing.md,
                            AppSpacing.md,
                            0,
                          ),
                          sliver: SliverToBoxAdapter(
                            child: Text(
                              'ALL ACHIEVEMENTS',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.6,
                                    color: const Color(0xFF8A8375),
                                  ),
                            ),
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.md,
                            AppSpacing.md,
                            AppSpacing.md,
                            AppSpacing.xl,
                          ),
                          sliver: twoCol
                              ? SliverGrid.builder(
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    crossAxisSpacing: AppSpacing.md,
                                    mainAxisSpacing: AppSpacing.md,
                                    childAspectRatio: 1.55,
                                  ),
                                  itemCount: catalog.badges.length,
                                  itemBuilder: (context, i) =>
                                      _buildCard(context, catalog.badges[i], rows),
                                )
                              : SliverList.separated(
                                  itemCount: catalog.badges.length,
                                  separatorBuilder: (context, _) =>
                                      const SizedBox(height: AppSpacing.md),
                                  itemBuilder: (context, i) =>
                                      _buildCard(context, catalog.badges[i], rows),
                                ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
    );
  }

  Widget _buildCard(
    BuildContext context,
    BadgeDef badge,
    List<Map<String, dynamic>> rows,
  ) {
    final row = rows.where((r) => r['badge_id'] == badge.id).firstOrNull;
    final progress = (row?['progress'] as num?)?.toInt() ?? 0;
    final tier = (row?['unlocked_tier'] as int?) ?? 0;

    return AchievementProgressCard(
      badge: badge,
      progress: progress,
      tier: tier,
      onTap: () => BadgeDetailDialog.show(
        context,
        badge: badge,
        earned: tier > 0,
        progress: progress,
        tier: tier,
      ),
    );
  }
}

/// Loading placeholder for the achievements list. Deliberately renders a
/// fixed single-column list rather than mirroring the real screen's
/// responsive 1-col/2-col [LayoutBuilder] split — not worth the complexity
/// for a transient state.
class _BadgesSkeleton extends StatelessWidget {
  const _BadgesSkeleton();

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          for (var i = 0; i < 4; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.md),
            const _AchievementCardSkeleton(),
          ],
        ],
      ),
    );
  }
}

class _AchievementCardSkeleton extends StatelessWidget {
  const _AchievementCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: AppSpacing.cardBorderRadius,
        border: Border.all(color: AppColors.divider),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(width: 100, height: 11),
          SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _TierHexSkeleton(),
              _TierHexSkeleton(),
              _TierHexSkeleton(),
            ],
          ),
        ],
      ),
    );
  }
}

class _TierHexSkeleton extends StatelessWidget {
  const _TierHexSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        SkeletonBox(width: 80, height: 80, radius: 12),
        SizedBox(height: 6),
        SkeletonBox(width: 44, height: 10),
      ],
    );
  }
}
