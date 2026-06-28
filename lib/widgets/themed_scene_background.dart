import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/logic/diorama_theme.dart';

/// Flat 2D approximation of Impact Drops' 3D isometric diorama rooms —
/// perspective floor grid and per-theme props for richer scene character.
class ThemedSceneBackground extends StatelessWidget {
  const ThemedSceneBackground({
    super.key,
    required this.theme,
    this.borderRadius,
  });

  final DioramaTheme theme;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: CustomPaint(painter: _ScenePainter(theme: theme)),
    );
  }
}

class _ScenePainter extends CustomPainter {
  _ScenePainter({required this.theme});

  final DioramaTheme theme;

  @override
  void paint(Canvas canvas, Size size) {
    final wallSplit = size.height * 0.55;
    final baseboardSplit = size.height * 0.72;

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, wallSplit),
      Paint()..color = theme.wallA,
    );
    canvas.drawRect(
      Rect.fromLTWH(0, wallSplit, size.width, baseboardSplit - wallSplit),
      Paint()..color = theme.wallB,
    );
    canvas.drawRect(
      Rect.fromLTWH(0, baseboardSplit, size.width, size.height - baseboardSplit),
      Paint()..color = theme.floor,
    );

    _drawPerspectiveFloor(canvas, size, baseboardSplit);
    _drawProps(canvas, size, baseboardSplit);
  }

  void _drawPerspectiveFloor(Canvas canvas, Size size, double baseboardSplit) {
    final vp = Offset(size.width * 0.5, baseboardSplit * 0.85);
    final floorTop = baseboardSplit;
    final floorBottom = size.height;
    final linePaint = Paint()
      ..color = theme.trim.withValues(alpha: 0.3)
      ..strokeWidth = 1;

    // Lines fanning from vanishing point to bottom edge.
    const fanCount = 8;
    for (var i = 0; i <= fanCount; i++) {
      final t = i / fanCount;
      final bottomX = size.width * t;
      canvas.drawLine(vp, Offset(bottomX, floorBottom), linePaint);
    }

    // Horizontal cross-lines with decreasing spacing toward vanishing point.
    var y = floorBottom;
    var spacing = 28.0;
    while (y > floorTop + 8) {
      final t = (y - floorTop) / (floorBottom - floorTop);
      final leftX = vp.dx + (0 - vp.dx) * (1 - t);
      final rightX = vp.dx + (size.width - vp.dx) * (1 - t);
      canvas.drawLine(Offset(leftX, y), Offset(rightX, y), linePaint);
      y -= spacing;
      spacing = math.max(10.0, spacing * 0.78);
    }
  }

  void _drawProps(Canvas canvas, Size size, double baseboardSplit) {
    switch (theme.id) {
      case DioramaThemeId.shopping:
        _drawShoppingProps(canvas, size, baseboardSplit);
      case DioramaThemeId.cafe:
        _drawCafeProps(canvas, size, baseboardSplit);
      case DioramaThemeId.grocery:
        _drawGroceryProps(canvas, size, baseboardSplit);
      case DioramaThemeId.petrol:
        _drawPetrolProps(canvas, size, baseboardSplit);
      case DioramaThemeId.electronics:
        _drawElectronicsProps(canvas, size, baseboardSplit);
      case DioramaThemeId.fastFood:
        _drawFastFoodProps(canvas, size, baseboardSplit);
      default:
        _drawGenericProps(canvas, size, baseboardSplit);
    }
  }

  void _drawShoppingProps(Canvas canvas, Size size, double baseboardSplit) {
    final accent = Paint()..color = theme.accent.withValues(alpha: 0.9);
    final trim = Paint()..color = theme.trim.withValues(alpha: 0.8);
    final rackY = baseboardSplit - size.height * 0.18;
    canvas.drawRect(
      Rect.fromLTWH(size.width * 0.12, rackY, size.width * 0.76, 4),
      accent,
    );
    for (var i = 0; i < 4; i++) {
      final x = size.width * (0.18 + i * 0.16);
      final path = Path()
        ..moveTo(x, rackY + 4)
        ..lineTo(x - 8, rackY + 28)
        ..lineTo(x + 8, rackY + 28)
        ..close();
      canvas.drawPath(path, trim);
    }
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.82, baseboardSplit - size.height * 0.22),
        width: size.width * 0.12,
        height: size.height * 0.14,
      ),
      Paint()
        ..color = theme.wallA
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  void _drawCafeProps(Canvas canvas, Size size, double baseboardSplit) {
    final counter = Paint()..color = theme.accent.withValues(alpha: 0.85);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * 0.1,
          baseboardSplit - size.height * 0.14,
          size.width * 0.55,
          size.height * 0.08,
        ),
        const Radius.circular(4),
      ),
      counter,
    );
    final cup = Paint()..color = theme.trim;
    for (var i = 0; i < 2; i++) {
      canvas.drawCircle(
        Offset(size.width * (0.72 + i * 0.1), baseboardSplit - size.height * 0.1),
        size.width * 0.04,
        cup,
      );
    }
  }

  void _drawGroceryProps(Canvas canvas, Size size, double baseboardSplit) {
    final shelf = Paint()..color = theme.accent.withValues(alpha: 0.85);
    final item = Paint()..color = theme.trim.withValues(alpha: 0.7);
    for (var row = 0; row < 2; row++) {
      final y = baseboardSplit - size.height * (0.22 - row * 0.1);
      canvas.drawRect(
        Rect.fromLTWH(size.width * 0.1, y, size.width * 0.35, 5),
        shelf,
      );
      for (var i = 0; i < 3; i++) {
        canvas.drawCircle(
          Offset(size.width * (0.16 + i * 0.08), y - 10),
          5,
          item,
        );
      }
    }
  }

  void _drawPetrolProps(Canvas canvas, Size size, double baseboardSplit) {
    final pump = Paint()..color = theme.accent.withValues(alpha: 0.9);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * 0.68,
          baseboardSplit - size.height * 0.28,
          size.width * 0.18,
          size.height * 0.22,
        ),
        const Radius.circular(6),
      ),
      pump,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        size.width * 0.62,
        baseboardSplit - size.height * 0.2,
        size.width * 0.08,
        size.height * 0.04,
      ),
      Paint()..color = theme.trim,
    );
  }

  void _drawElectronicsProps(Canvas canvas, Size size, double baseboardSplit) {
    final screen = Paint()..color = theme.accent.withValues(alpha: 0.85);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * 0.12,
          baseboardSplit - size.height * 0.26,
          size.width * 0.28,
          size.height * 0.18,
        ),
        const Radius.circular(4),
      ),
      screen,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * 0.68,
          baseboardSplit - size.height * 0.12,
          size.width * 0.2,
          size.height * 0.06,
        ),
        const Radius.circular(8),
      ),
      Paint()
        ..color = theme.trim
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  void _drawFastFoodProps(Canvas canvas, Size size, double baseboardSplit) {
    final counter = Paint()..color = theme.accent.withValues(alpha: 0.85);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * 0.08,
          baseboardSplit - size.height * 0.16,
          size.width * 0.5,
          size.height * 0.1,
        ),
        const Radius.circular(4),
      ),
      counter,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * 0.7,
          baseboardSplit - size.height * 0.1,
          size.width * 0.18,
          size.height * 0.05,
        ),
        const Radius.circular(3),
      ),
      Paint()..color = theme.trim.withValues(alpha: 0.8),
    );
  }

  void _drawGenericProps(Canvas canvas, Size size, double baseboardSplit) {
    final accent = Paint()..color = theme.accent.withValues(alpha: 0.85);
    final blockWidth = size.width * 0.16;
    final blockHeight = size.height * 0.1;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * 0.08,
          baseboardSplit - blockHeight * 0.6,
          blockWidth,
          blockHeight,
        ),
        const Radius.circular(4),
      ),
      accent,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * 0.76,
          baseboardSplit - blockHeight * 0.6,
          blockWidth,
          blockHeight,
        ),
        const Radius.circular(4),
      ),
      accent,
    );
  }

  @override
  bool shouldRepaint(covariant _ScenePainter oldDelegate) =>
      oldDelegate.theme.id != theme.id;
}
