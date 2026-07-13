import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../data/repositories/badge_repository.dart';
import '../../domain/logic/badge_catalog.dart';
import '../../widgets/achievement_progress_card.dart';
import '../../widgets/badge_detail_dialog.dart';

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
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<List<Map<String, dynamic>>>(
              stream: BadgeRepository.streamAll(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    snapshot.data == null) {
                  return const Center(child: CircularProgressIndicator());
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
