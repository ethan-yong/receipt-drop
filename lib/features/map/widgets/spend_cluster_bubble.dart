import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/logic/map_aggregates.dart';
import 'receipt_map_pin.dart';

/// Cluster pin for a geohash bucket of nearby spend places.
///
/// Face is count-driven (not zoom-driven): a single receipt shows that
/// receipt's category emoji + accent border; multiple receipts show the
/// generic receipt emoji with a total-count badge. Tapping fits the camera
/// to the places inside the bucket instead of opening the per-place panel.
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
    final single = bucket.receiptCount == 1;
    return ReceiptMapPin(
      emoji: single
          ? AppColors.categoryEmoji(bucket.dominantCategory)
          : '🧾',
      count: bucket.receiptCount,
      accent: single
          ? AppColors.categoryColor(bucket.dominantCategory)
          : null,
      onTap: onTap,
    );
  }
}
