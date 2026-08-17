import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import 'marker_tail_painter.dart';

/// Shared map-pin shell for spend markers: a white circle with a centered
/// emoji, a downward tail whose tip is the geographic anchor, and an optional
/// notification-style count badge at the top-right when [count] > 1.
///
/// Pass [accent] for category pins (colored border + matching tail). Leave it
/// null for multi-receipt cluster pins (neutral outline).
class ReceiptMapPin extends StatelessWidget {
  const ReceiptMapPin({
    super.key,
    required this.emoji,
    required this.count,
    required this.onTap,
    this.accent,
  });

  /// Primary visual — receipt icon for clusters, category emoji for places.
  final String emoji;

  /// Receipts represented by this pin. Badge is hidden when ≤ 1.
  final int count;

  /// Category accent for border + tail; null keeps the neutral cluster look.
  final Color? accent;

  final VoidCallback onTap;

  /// Outer diameter of the emoji circle (excluding badge overflow + tail).
  static const double circleSize = 52;

  /// Half-width used by [spend_map_screen] Positioned offsets so the circle
  /// is centered on the geographic anchor horizontally.
  static const double halfWidth = circleSize / 2;

  static const double _tailHeight = 8;

  /// Distance from the top of the widget to the tail tip (circle + tail).
  static const double tipOffsetY = circleSize + _tailHeight;

  @override
  Widget build(BuildContext context) {
    final showBadge = count > 1;
    final badgeLabel = count > 99 ? '99+' : '$count';
    final borderColor = accent ?? AppColors.divider;
    final borderWidth = accent != null ? 2.0 : 1.5;
    final tailColor = accent ?? AppColors.textMuted;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: circleSize,
            height: circleSize,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: circleSize,
                  height: circleSize,
                  decoration: BoxDecoration(
                    color: AppColors.cardSurface,
                    shape: BoxShape.circle,
                    border: Border.all(color: borderColor, width: borderWidth),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    emoji,
                    style: const TextStyle(fontSize: 26, height: 1),
                  ),
                ),
                if (showBadge)
                  Positioned(
                    top: -5,
                    right: -5,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 20),
                      height: 20,
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      decoration: BoxDecoration(
                        color: AppColors.accentOrange,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: AppColors.cardSurface,
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 3,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        badgeLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          CustomPaint(
            size: const Size(14, _tailHeight),
            painter: MarkerTailPainter(color: tailColor),
          ),
        ],
      ),
    );
  }
}
