import 'package:flutter/material.dart';

import 'receipt_map_pin.dart';

/// Collapsed overlap indicator for two or more place pins whose screen
/// positions land on top of each other. Shows the generic receipt emoji with
/// a badge for the total receipt count across the overlapping places. Tapping
/// expands the group into a spiderfy fan-out (handled by the map screen).
class OverlapStackMarker extends StatelessWidget {
  const OverlapStackMarker({
    super.key,
    required this.receiptCount,
    required this.onTap,
  });

  /// Sum of visit/receipt counts across the overlapping place clusters.
  final int receiptCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ReceiptMapPin(
      emoji: '🧾',
      count: receiptCount,
      onTap: onTap,
    );
  }
}
