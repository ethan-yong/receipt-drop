import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/logic/dashboard_aggregates.dart';
import 'marker_tail_painter.dart';

/// Zoomed-out cluster bubble for a geohash bucket of nearby spend places:
/// shows total receipt count and distinct place count rather than any single
/// place's detail. Sibling to [SpendPlaceMarker] using the same pill+tail
/// visual. Tapping fits the camera to the places inside the bucket (with
/// edge padding) instead of opening the per-place detail panel.
class SpendClusterBubble extends StatelessWidget {
  const SpendClusterBubble({
    super.key,
    required this.bucket,
    required this.onTap,
  });

  final GeoBucket bucket;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.categoryColor(bucket.dominantCategory);
    final receiptsLabel = bucket.receiptCount == 1
        ? '1 receipt'
        : '${bucket.receiptCount} receipts';
    final placesLabel =
        bucket.placeCount == 1 ? '1 place' : '${bucket.placeCount} places';

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.cardSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: accent, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  receiptsLabel,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                Text(
                  placesLabel,
                  style: TextStyle(
                    color: AppColors.textPrimary.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w500,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          // Tail: its tip is the bucket's geohash centroid (anchor point).
          CustomPaint(
            size: const Size(14, 8),
            painter: MarkerTailPainter(color: accent),
          ),
        ],
      ),
    );
  }
}
