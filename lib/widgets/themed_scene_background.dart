import 'package:flutter/material.dart';

import '../domain/logic/diorama_theme.dart';

/// Flat 2D approximation of Impact Drops' 3D isometric diorama rooms —
/// deliberately geometric/flat (no perspective transforms), per the plan's
/// decision to skip porting the CSS-3D/Three.js scene system.
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

    // Floor "tile" texture — thin trim-colored lines instead of a 3D grid.
    final tileLine = Paint()
      ..color = theme.trim.withValues(alpha: 0.25)
      ..strokeWidth = 1;
    const tileStep = 18.0;
    for (var y = baseboardSplit + tileStep; y < size.height; y += tileStep) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), tileLine);
    }

    // Two simple accent blocks ("shelf"/"counter") for scene character.
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
