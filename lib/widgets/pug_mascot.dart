import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// Pug mascot illustration (asset with vector fallback).
class PugMascot extends StatelessWidget {
  const PugMascot({
    super.key,
    this.assetPath = 'assets/branding/pug-logo.png',
    this.size = 120,
  });

  final String assetPath;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: Image.asset(
        assetPath,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _PugMascotFallback(size: size),
      ),
    );
  }
}

class _PugMascotFallback extends StatelessWidget {
  const _PugMascotFallback({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _PugPainter()),
    );
  }
}

class _PugPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width * 0.42;
    canvas.drawCircle(center, r, Paint()..color = const Color(0xFFE8C9A0));
    canvas.drawCircle(
      Offset(center.dx - r * 0.35, center.dy - r * 0.55),
      r * 0.22,
      Paint()..color = const Color(0xFFD4A574),
    );
    canvas.drawCircle(
      Offset(center.dx + r * 0.35, center.dy - r * 0.55),
      r * 0.22,
      Paint()..color = const Color(0xFFD4A574),
    );
    canvas.drawCircle(
      Offset(center.dx - r * 0.28, center.dy - r * 0.05),
      r * 0.08,
      Paint()..color = AppColors.textPrimary,
    );
    canvas.drawCircle(
      Offset(center.dx + r * 0.28, center.dy - r * 0.05),
      r * 0.08,
      Paint()..color = AppColors.textPrimary,
    );
    final hoodie = Path()
      ..addOval(Rect.fromCircle(center: center.translate(0, r * 0.35), radius: r * 0.75));
    canvas.drawPath(hoodie, Paint()..color = AppColors.primaryGreen);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
