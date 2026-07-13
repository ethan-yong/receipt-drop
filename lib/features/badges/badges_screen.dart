import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/bootstrap/app_services.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/badge_repository.dart';
import '../../domain/logic/badge_catalog.dart';
import '../../domain/logic/badge_progress.dart';
import '../../domain/models/transaction_view.dart';
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
  final _lastSynced = <String, int>{};

  @override
  void initState() {
    super.initState();
    BadgeCatalog.loadBundled().then((c) {
      if (mounted) setState(() => _catalog = c);
    });
  }

  void _syncChanged(List<BadgeEntry> entries) {
    for (final e in entries) {
      if (_lastSynced[e.badge.id] == e.progress) continue;
      _lastSynced[e.badge.id] = e.progress;
      BadgeRepository.saveBadgeState(
        e.badge.id,
        progress: e.progress.toDouble(),
        earned: e.earned,
      );
    }
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
          : StreamBuilder<List<TransactionView>>(
              stream: AppServices.transactions.watchAll(),
              builder: (context, snapshot) {
                final rows = snapshot.data ?? const [];
                final entries = computeBadgeEntries(catalog, rows);

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _syncChanged(entries);
                });

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
