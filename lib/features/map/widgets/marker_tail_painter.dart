import 'package:flutter/material.dart';

/// Small downward-pointing tail whose tip is a marker's geographic anchor,
/// shared by [SpendPlaceMarker] and [SpendClusterBubble] so both pill-shaped
/// map markers render with the same tail.
class MarkerTailPainter extends CustomPainter {
  const MarkerTailPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant MarkerTailPainter oldDelegate) =>
      oldDelegate.color != color;
}
