import 'dart:math';
import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Scene background — sky, ground, clouds, house, mailbox pole + body + slot.
// This painter is static: shouldRepaint returns false.
// ---------------------------------------------------------------------------

class ScenePainter extends CustomPainter {
  const ScenePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 390; // scale relative to 390px reference width

    // Sky gradient
    final skyRect = Rect.fromLTWH(0, 0, size.width, size.height * 0.55);
    canvas.drawRect(
      skyRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFB7D9EA), Color(0xFFE7F0E9)],
        ).createShader(skyRect),
    );

    // Ground / grass
    final grassRect = Rect.fromLTWH(0, size.height * 0.50, size.width, size.height * 0.50);
    canvas.drawRect(
      grassRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFA9D890), Color(0xFF8FC479)],
        ).createShader(grassRect),
    );

    // A few static clouds
    _drawCloud(canvas, Offset(50 * s, 60 * s), 36 * s, 18 * s);
    _drawCloud(canvas, Offset(160 * s, 44 * s), 42 * s, 20 * s);
    _drawCloud(canvas, Offset(300 * s, 80 * s), 30 * s, 16 * s);

    // House (right background)
    _drawHouse(canvas, size, s);

    // Mailbox pole
    final poleRect = Rect.fromLTWH(
      size.width * 0.5 - 4 * s,
      size.height * 0.52,
      8 * s,
      size.height * 0.20,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(poleRect, const Radius.circular(2)),
      Paint()..color = const Color(0xFF5C3E24),
    );
  }

  void _drawCloud(Canvas canvas, Offset center, double rx, double ry) {
    final p = Paint()..color = const Color(0xFFFDFBF5).withValues(alpha: 0.85);
    canvas.drawOval(Rect.fromCenter(center: center, width: rx * 2, height: ry * 2), p);
    canvas.drawOval(
      Rect.fromCenter(center: center.translate(-rx * 0.45, -ry * 0.4), width: rx * 1.2, height: ry * 1.4),
      p,
    );
    canvas.drawOval(
      Rect.fromCenter(center: center.translate(rx * 0.4, -ry * 0.3), width: rx * 1.0, height: ry * 1.2),
      p,
    );
  }

  void _drawHouse(Canvas canvas, Size size, double s) {
    final wallL = size.width * 0.60;
    final wallT = size.height * 0.30;
    const wallW = 64.0;
    const wallH = 52.0;

    // Roof
    final roofPath = Path()
      ..moveTo(wallL - 10 * s, wallT)
      ..lineTo(wallL + wallW * s / 2, wallT - 28 * s)
      ..lineTo(wallL + (wallW + 10) * s, wallT)
      ..close();
    canvas.drawPath(roofPath, Paint()..color = const Color(0xFFB4483B).withValues(alpha: 0.88));

    // Wall
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(wallL, wallT, wallW * s, wallH * s),
        const Radius.circular(2),
      ),
      Paint()..color = const Color(0xFFEFDCC0).withValues(alpha: 0.9),
    );

    // Door
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(wallL + 22 * s, wallT + wallH * s - 28 * s, 18 * s, 28 * s),
        const Radius.circular(2),
      ),
      Paint()..color = const Color(0xFF7A5638).withValues(alpha: 0.9),
    );

    // Windows
    for (final dx in [8.0, 42.0]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(wallL + dx * s, wallT + 12 * s, 12 * s, 12 * s),
          const Radius.circular(2),
        ),
        Paint()..color = const Color(0xFFFAF3E7).withValues(alpha: 0.85),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// Mailbox body painter — drawn separately so it can be squashed independently.
// Includes rounded body, slot stripe, and a flag arm.
// ---------------------------------------------------------------------------

class MailboxPainter extends CustomPainter {
  const MailboxPainter({this.flagAngle = pi / 2});

  /// Flag angle in radians: π/2 = folded down, 0 = raised.
  final double flagAngle;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Body
    final bodyRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, w * 0.80, h * 0.70),
      const Radius.circular(14),
    );
    canvas.drawRRect(
      bodyRect,
      Paint()
        ..color = const Color(0xFFF5C242)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    canvas.drawRRect(bodyRect, Paint()..color = const Color(0xFFF5C242));

    // Slot stripe
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.14, h * 0.30, w * 0.55, h * 0.10),
        const Radius.circular(3),
      ),
      Paint()..color = const Color(0xFFB8841A),
    );

    // Flag arm (rotates around its base at the right side of the box)
    final flagBaseX = w * 0.80;
    final flagBaseY = h * 0.22;
    canvas.save();
    canvas.translate(flagBaseX, flagBaseY);
    canvas.rotate(flagAngle - pi / 2); // 0 = pointing up
    // Pole
    canvas.drawRect(
      Rect.fromLTWH(-3, -h * 0.40, 4, h * 0.42),
      Paint()..color = const Color(0xFF5C3E24),
    );
    // Flag panel
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(1, -h * 0.40, w * 0.25, h * 0.20),
        const Radius.circular(3),
      ),
      Paint()..color = const Color(0xFFE2885C),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant MailboxPainter old) => old.flagAngle != flagAngle;
}

// ---------------------------------------------------------------------------
// Pigeon painter — body, head, beak, tail, animated wing.
// wingAngle: -22° (folded) to 28° (spread), in degrees for readability.
// ---------------------------------------------------------------------------

class PigeonPainter extends CustomPainter {
  const PigeonPainter({required this.wingAngleDeg});

  final double wingAngleDeg;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 80; // reference 80px wide

    // Tail fan
    final tailPaint = Paint()..color = const Color(0xFFACA79C);
    final tailPath = Path()
      ..moveTo(64 * s, 28 * s)
      ..lineTo(80 * s, 20 * s)
      ..lineTo(80 * s, 38 * s)
      ..close();
    canvas.drawPath(tailPath, tailPaint);

    // Body
    canvas.drawOval(
      Rect.fromCenter(center: Offset(36 * s, 28 * s), width: 52 * s, height: 36 * s),
      Paint()..color = const Color(0xFFACA79C),
    );

    // Wing (rotates around root at body left-center)
    canvas.save();
    canvas.translate(20 * s, 20 * s);
    canvas.rotate(wingAngleDeg * pi / 180);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(18 * s, 0), width: 44 * s, height: 16 * s),
      Paint()..color = const Color(0xFF8F8A7C),
    );
    canvas.restore();

    // Head
    canvas.drawCircle(
      Offset(16 * s, 18 * s),
      14 * s,
      Paint()..color = const Color(0xFFB8B3A6),
    );

    // Eye
    canvas.drawCircle(
      Offset(10 * s, 16 * s),
      3 * s,
      Paint()..color = const Color(0xFF23201A),
    );

    // Beak
    final beakPath = Path()
      ..moveTo(0, 20 * s)
      ..lineTo(-14 * s, 24 * s)
      ..lineTo(0, 28 * s)
      ..close();
    canvas.drawPath(beakPath, Paint()..color = const Color(0xFFF0AA2A));
  }

  @override
  bool shouldRepaint(covariant PigeonPainter old) => old.wingAngleDeg != wingAngleDeg;
}

// ---------------------------------------------------------------------------
// Receipt slip painter — a small folded receipt card with ruled lines.
// ---------------------------------------------------------------------------

class ReceiptSlipPainter extends CustomPainter {
  const ReceiptSlipPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Card body
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h), const Radius.circular(3)),
      Paint()
        ..color = const Color(0xFFFFFDF8)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h), const Radius.circular(3)),
      Paint()..color = const Color(0xFFFFFDF8),
    );

    // Ruled lines
    final linePaint = Paint()..color = const Color(0xFFE9DDC8);
    for (final dy in [h * 0.28, h * 0.50, h * 0.70]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.15, dy, w * 0.70, 2),
          const Radius.circular(1),
        ),
        linePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
