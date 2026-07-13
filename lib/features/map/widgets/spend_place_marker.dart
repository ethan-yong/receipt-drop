import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/logic/dashboard_aggregates.dart';
import 'marker_tail_painter.dart';

/// Snap-style spend bubble for one place cluster: a rounded pill leading with
/// the visit/receipt count, tinted by the cluster's dominant category
/// (precomputed once in [mapClusters], not recomputed per build), sitting on
/// a small tail whose tip is the anchor point. Total spend is deliberately
/// not shown here — it lives in the tap-to-open detail panel only.
class SpendPlaceMarker extends StatelessWidget {
  const SpendPlaceMarker({
    super.key,
    required this.cluster,
    required this.onTap,
  });

  final MapPlaceCluster cluster;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.categoryColor(cluster.dominantCategory);
    final label = cluster.visitCount == 1
        ? '1 receipt'
        : '${cluster.visitCount} receipts';

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
              label,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          // Tail: its tip is the geographic anchor (marker aligned topCenter).
          CustomPaint(
            size: const Size(12, 7),
            painter: MarkerTailPainter(color: accent),
          ),
        ],
      ),
    );
  }
}
