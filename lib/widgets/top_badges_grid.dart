import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../data/repositories/avatar_repository.dart';
import '../domain/logic/badge_progress.dart';
import 'badge_detail_dialog.dart';
import 'badge_hex.dart';

/// Home screen's drag-reorderable top-6 badges grid. Hand-rolled with
/// LongPressDraggable/DragTarget rather than a package, per the plan's
/// "avoid new dependencies" call — scope is fixed at 6 items/3 columns.
class TopBadgesGrid extends StatefulWidget {
  const TopBadgesGrid({super.key, required this.entries});

  final List<BadgeEntry> entries;

  @override
  State<TopBadgesGrid> createState() => _TopBadgesGridState();
}

class _TopBadgesGridState extends State<TopBadgesGrid> {
  List<String>? _order;

  @override
  void initState() {
    super.initState();
    AvatarRepository.getTopBadgeOrder().then((order) {
      if (mounted) setState(() => _order = order);
    });
  }

  List<BadgeEntry> _topSix() {
    final byId = {for (final e in widget.entries) e.badge.id: e};
    final picked = <BadgeEntry>[];
    final used = <String>{};

    for (final id in _order ?? const <String>[]) {
      final e = byId[id];
      if (e == null || !used.add(id)) continue;
      picked.add(e);
      if (picked.length == 6) break;
    }

    if (picked.length < 6) {
      final rest = widget.entries.where((e) => !used.contains(e.badge.id)).toList()
        ..sort((a, b) {
          if (a.earned != b.earned) return a.earned ? -1 : 1;
          return b.progress.compareTo(a.progress);
        });
      for (final e in rest) {
        if (picked.length == 6) break;
        picked.add(e);
        used.add(e.badge.id);
      }
    }

    return picked;
  }

  void _reorder(List<BadgeEntry> current, int fromIndex, int toIndex) {
    final ids = current.map((e) => e.badge.id).toList()..insert(toIndex, current[fromIndex].badge.id);
    ids.removeAt(fromIndex > toIndex ? fromIndex + 1 : fromIndex);
    setState(() => _order = ids);
    AvatarRepository.saveTopBadgeOrder(ids);
  }

  @override
  Widget build(BuildContext context) {
    final current = _topSix();
    if (current.isEmpty) return const SizedBox.shrink();

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: AppSpacing.md,
        crossAxisSpacing: AppSpacing.sm,
      ),
      itemCount: current.length,
      itemBuilder: (context, index) {
        final e = current[index];
        return DragTarget<int>(
          onWillAcceptWithDetails: (details) => details.data != index,
          onAcceptWithDetails: (details) => _reorder(current, details.data, index),
          builder: (context, candidateData, rejectedData) {
            final tile = BadgeHex(
              badge: e.badge,
              earned: e.earned,
              showLabel: true,
              onTap: () => BadgeDetailDialog.show(
                context,
                badge: e.badge,
                earned: e.earned,
                progress: e.progress,
              ),
            );
            return AnimatedScale(
              scale: candidateData.isNotEmpty ? 1.1 : 1.0,
              duration: const Duration(milliseconds: 150),
              child: LongPressDraggable<int>(
                data: index,
                feedback: Opacity(opacity: 0.85, child: tile),
                childWhenDragging: Opacity(opacity: 0.3, child: tile),
                child: tile,
              ),
            );
          },
        );
      },
    );
  }
}
