import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../domain/logic/badge_catalog.dart';

/// Hexagonal badge tile — port of Impact Drops' BadgeHex.
class BadgeHex extends StatelessWidget {
  const BadgeHex({
    super.key,
    required this.badge,
    required this.earned,
    this.size = 88,
    this.showLabel = false,
    this.onTap,
  });

  final BadgeDef badge;
  final bool earned;
  final double size;
  final bool showLabel;
  final VoidCallback? onTap;

  Color get _rarityColor {
    switch (badge.rarity) {
      case BadgeRarity.common:
        return const Color(0xFFB8B0A4);
      case BadgeRarity.rare:
        return const Color(0xFF6FB8E8);
      case BadgeRarity.epic:
        return const Color(0xFFC7A8E8);
      case BadgeRarity.legendary:
        return AppColors.primaryGreen;
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CustomPaint(
              painter: _HexPainter(
                fill: earned ? _rarityColor : AppColors.divider,
                locked: !earned,
              ),
              child: Center(
                child: Opacity(
                  opacity: earned ? 1 : 0.4,
                  child: Text(badge.emoji, style: TextStyle(fontSize: size * 0.36)),
                ),
              ),
            ),
          ),
          if (showLabel) ...[
            const SizedBox(height: 4),
            Text(
              badge.label,
              style: Theme.of(context).textTheme.labelSmall,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

class _HexPainter extends CustomPainter {
  _HexPainter({required this.fill, required this.locked});

  final Color fill;
  final bool locked;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(w * 0.5, 0)
      ..lineTo(w * 0.95, h * 0.25)
      ..lineTo(w * 0.95, h * 0.75)
      ..lineTo(w * 0.5, h)
      ..lineTo(w * 0.05, h * 0.75)
      ..lineTo(w * 0.05, h * 0.25)
      ..close();

    final gradient = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: locked
            ? [fill.withValues(alpha: 0.6), fill.withValues(alpha: 0.3)]
            : [fill, fill.withValues(alpha: 0.75)],
      ).createShader(Offset.zero & size);
    canvas.drawPath(path, gradient);

    if (locked) {
      final lockPaint = Paint()..color = AppColors.textMuted;
      canvas.drawCircle(Offset(w * 0.5, h * 0.82), w * 0.06, lockPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _HexPainter oldDelegate) =>
      oldDelegate.fill != fill || oldDelegate.locked != locked;
}
