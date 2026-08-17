import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/logic/map_aggregates.dart';
import 'receipt_map_pin.dart';

/// Place pin: dominant category emoji with a category-colored border/tail and
/// a count badge for receipts in that category (hidden when count is 1).
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
    return ReceiptMapPin(
      emoji: AppColors.categoryEmoji(cluster.dominantCategory),
      count: cluster.dominantCategoryCount,
      accent: AppColors.categoryColor(cluster.dominantCategory),
      onTap: onTap,
    );
  }
}
