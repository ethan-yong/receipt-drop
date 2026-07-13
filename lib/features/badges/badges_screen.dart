import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../data/repositories/badge_repository.dart';
import '../../domain/logic/badge_catalog.dart';
import '../../widgets/badge_detail_dialog.dart';
import '../../widgets/badge_hex.dart';

enum _Filter { all, earned, locked }

class BadgesScreen extends StatefulWidget {
  const BadgesScreen({super.key});

  @override
  State<BadgesScreen> createState() => _BadgesScreenState();
}

class _BadgesScreenState extends State<BadgesScreen> {
  BadgeCatalog? _catalog;
  _Filter _filter = _Filter.all;

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
                final entries = catalog.badges.map((badge) {
                  final row = rows
                      .where((r) => r['badge_id'] == badge.id)
                      .firstOrNull;
                  return (
                    badge: badge,
                    progress: (row?['progress'] as num?)?.toInt() ?? 0,
                    earned: row?['earned'] as bool? ?? false,
                    tier: (row?['unlocked_tier'] as int?) ?? 0,
                  );
                }).toList();

                final filtered = entries.where((e) {
                  switch (_filter) {
                    case _Filter.all:
                      return true;
                    case _Filter.earned:
                      return e.earned;
                    case _Filter.locked:
                      return !e.earned;
                  }
                }).toList();

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        AppSpacing.md,
                        AppSpacing.md,
                        0,
                      ),
                      child: SegmentedButton<_Filter>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: _Filter.all, label: Text('ALL')),
                          ButtonSegment(value: _Filter.earned, label: Text('EARNED')),
                          ButtonSegment(value: _Filter.locked, label: Text('LOCKED')),
                        ],
                        selected: {_filter},
                        onSelectionChanged: (s) => setState(() => _filter = s.first),
                      ),
                    ),
                    Expanded(
                      child: GridView.builder(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: AppSpacing.md,
                          crossAxisSpacing: AppSpacing.sm,
                        ),
                        itemCount: filtered.length,
                        itemBuilder: (context, i) {
                          final e = filtered[i];
                          return BadgeHex(
                            badge: e.badge,
                            earned: e.earned,
                            tier: e.tier,
                            showLabel: true,
                            onTap: () => BadgeDetailDialog.show(
                              context,
                              badge: e.badge,
                              earned: e.earned,
                              progress: e.progress,
                              tier: e.tier,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}
