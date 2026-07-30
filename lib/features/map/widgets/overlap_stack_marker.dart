import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import 'marker_tail_painter.dart';

/// Collapsed overlap indicator for two or more place pins whose screen
/// positions land on top of each other. Sibling to [SpendPlaceMarker] /
/// [SpendClusterBubble] using the same pill+tail language, with a faint
/// stacked-card affect behind the front pill. Tapping expands the group
/// into a spiderfy fan-out (handled by the map screen).
class OverlapStackMarker extends StatelessWidget {
  const OverlapStackMarker({
    super.key,
    required this.count,
    required this.dominantCategory,
    required this.onTap,
  });

  final int count;
  final String dominantCategory;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.categoryColor(dominantCategory);
    final label = '$count nearby';

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            // Extra room for the two offset back-cards behind the front pill.
            width: 110,
            height: 44,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Transform.translate(
                  offset: const Offset(5, 4),
                  child: _stackCard(
                    accent.withValues(alpha: 0.35),
                    filled: false,
                  ),
                ),
                Transform.translate(
                  offset: const Offset(2.5, 2),
                  child: _stackCard(
                    accent.withValues(alpha: 0.55),
                    filled: false,
                  ),
                ),
                _stackCard(accent, filled: true, label: label),
              ],
            ),
          ),
          CustomPaint(
            size: const Size(12, 7),
            painter: MarkerTailPainter(color: accent),
          ),
        ],
      ),
    );
  }

  Widget _stackCard(Color border, {required bool filled, String? label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: filled ? AppColors.cardSurface : AppColors.cardSurface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border, width: 2),
        boxShadow: filled
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: label == null
          ? const SizedBox(width: 64, height: 16)
          : Text(
              label,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
    );
  }
}
