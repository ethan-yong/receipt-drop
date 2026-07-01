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
    this.showRarityChip = false,
    this.onTap,
  });

  final BadgeDef badge;
  final bool earned;
  final double size;
  final bool showLabel;
  final bool showRarityChip;
  final VoidCallback? onTap;

  bool get _locked => badge.comingSoon || !earned;

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

  Color get _rarityChipBg {
    switch (badge.rarity) {
      case BadgeRarity.common:
        return const Color(0xFFE8E4DC);
      case BadgeRarity.rare:
        return const Color(0xFFD6EBFA);
      case BadgeRarity.epic:
        return const Color(0xFFEDE0F8);
      case BadgeRarity.legendary:
        return const Color(0xFFFFF3C4);
    }
  }

  Color get _rarityChipText {
    switch (badge.rarity) {
      case BadgeRarity.common:
        return const Color(0xFF645D51);
      case BadgeRarity.rare:
        return const Color(0xFF2E6A9E);
      case BadgeRarity.epic:
        return const Color(0xFF7B4FA8);
      case BadgeRarity.legendary:
        return AppColors.primaryGreenDark;
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
                fill: _locked ? AppColors.divider : _rarityColor,
                stroke: _locked ? null : _rarityColor,
                locked: _locked,
              ),
              child: Center(
                child: Opacity(
                  opacity: _locked ? 0.35 : 1,
                  child: Text(
                    badge.emoji,
                    style: TextStyle(fontSize: size * 0.36),
                  ),
                ),
              ),
            ),
          ),
          if (showRarityChip) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _rarityChipBg,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                badge.rarity.name.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontSize: 9,
                      color: _rarityChipText,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
              ),
            ),
          ],
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
  _HexPainter({
    required this.fill,
    required this.locked,
    this.stroke,
  });

  final Color fill;
  final Color? stroke;
  final bool locked;

  Path _hexPath(double w, double h) {
    return Path()
      ..moveTo(w * 0.5, 0)
      ..lineTo(w * 0.95, h * 0.25)
      ..lineTo(w * 0.95, h * 0.75)
      ..lineTo(w * 0.5, h)
      ..lineTo(w * 0.05, h * 0.75)
      ..lineTo(w * 0.05, h * 0.25)
      ..close();
  }

  void _drawLock(Canvas canvas, double w, double h) {
    final bodyPaint = Paint()..color = AppColors.textMuted;
    final cx = w * 0.5;
    final cy = h * 0.82;
    final bodyW = w * 0.14;
    final bodyH = h * 0.08;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(cx, cy + bodyH * 0.15),
          width: bodyW,
          height: bodyH,
        ),
        const Radius.circular(2),
      ),
      bodyPaint,
    );
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(cx, cy - bodyH * 0.1),
        width: bodyW * 0.9,
        height: bodyH * 1.4,
      ),
      3.14,
      3.14,
      false,
      Paint()
        ..color = AppColors.textMuted
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = _hexPath(w, h);

    final gradient = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: locked
            ? [fill.withValues(alpha: 0.6), fill.withValues(alpha: 0.3)]
            : [fill, fill.withValues(alpha: 0.75)],
      ).createShader(Offset.zero & size);
    canvas.drawPath(path, gradient);

    if (stroke != null) {
      canvas.drawPath(
        path,
        Paint()
          ..color = stroke!
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    if (locked) {
      _drawLock(canvas, w, h);
    }
  }

  @override
  bool shouldRepaint(covariant _HexPainter oldDelegate) =>
      oldDelegate.fill != fill ||
      oldDelegate.locked != locked ||
      oldDelegate.stroke != stroke;
}
