import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../domain/logic/impact_level.dart';

/// Port of Impact Drops' ReceiptStrip — a small dashed-border "receipt" card
/// whose height communicates impact level instead of showing a number.
class ReceiptStrip extends StatelessWidget {
  const ReceiptStrip({super.key, required this.impact, this.label});

  final ImpactLevel impact;
  final String? label;

  static const _lengths = {
    ImpactLevel.low: 80.0,
    ImpactLevel.med: 140.0,
    ImpactLevel.high: 220.0,
  };

  Color get _stripColor {
    switch (impact) {
      case ImpactLevel.low:
        return AppColors.impactLow;
      case ImpactLevel.med:
        return AppColors.impactMed;
      case ImpactLevel.high:
        return AppColors.impactHigh;
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = _lengths[impact]!;
    return SizedBox(
      width: 88,
      height: height,
      child: CustomPaint(
        painter: _ReceiptStripPainter(stripColor: _stripColor),
        child: label == null
            ? null
            : Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Text(
                    label!.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          letterSpacing: 0.6,
                        ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _ReceiptStripPainter extends CustomPainter {
  _ReceiptStripPainter({required this.stripColor});

  final Color stripColor;
  static const _radius = 6.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(_radius),
    );

    canvas.drawRRect(rrect, Paint()..color = AppColors.cardSurface);
    canvas.save();
    canvas.clipRRect(rrect);

    final texture = Paint()
      ..color = AppColors.textPrimary.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    for (var y = 14.0; y < size.height; y += 15) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), texture);
    }

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, 8),
      Paint()..color = stripColor,
    );

    canvas.restore();

    _drawDashedRRect(canvas, rrect, AppColors.divider);
  }

  void _drawDashedRRect(Canvas canvas, RRect rrect, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()..addRRect(rrect);
    const dashWidth = 4.0, dashGap = 3.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + dashWidth, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance += dashWidth + dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ReceiptStripPainter oldDelegate) =>
      oldDelegate.stripColor != stripColor;
}
