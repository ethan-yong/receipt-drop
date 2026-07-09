import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/logic/dashboard_aggregates.dart';

/// Snap-style spend bubble for one place cluster: a rounded pill with the
/// total (RM), tinted by the cluster's dominant category, sitting on a small
/// tail whose tip is the anchor point.
class SpendPlaceMarker extends StatelessWidget {
  const SpendPlaceMarker({
    super.key,
    required this.cluster,
    required this.onTap,
  });

  final MapPlaceCluster cluster;
  final VoidCallback onTap;

  String get _dominantCategory {
    final totals = <String, double>{};
    for (final t in cluster.transactions) {
      totals.update(
        t.effectiveCategory,
        (v) => v + (t.amountMyr ?? 0),
        ifAbsent: () => t.amountMyr ?? 0,
      );
    }
    if (totals.isEmpty) return 'Unclassified';
    return totals.entries
        .reduce((a, b) => a.value >= b.value ? a : b)
        .key;
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.categoryColor(_dominantCategory);

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.cardSurface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: accent, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  'RM ${cluster.totalSpend.toStringAsFixed(0)}',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              if (cluster.visitCount > 1)
                Positioned(
                  top: -6,
                  right: -6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.cardSurface,
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      '${cluster.visitCount}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 9,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          // Tail: its tip is the geographic anchor (marker aligned topCenter).
          CustomPaint(
            size: const Size(12, 7),
            painter: _MarkerTailPainter(color: accent),
          ),
        ],
      ),
    );
  }
}

class _MarkerTailPainter extends CustomPainter {
  const _MarkerTailPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _MarkerTailPainter oldDelegate) =>
      oldDelegate.color != color;
}
