import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../domain/logic/avatar_mood.dart';
import '../domain/models/avatar_config.dart';

/// Simplified isometric block avatar — port of Impact Drops' PixelAvatar.
class PixelAvatar extends StatefulWidget {
  const PixelAvatar({
    super.key,
    required this.mood,
    required this.config,
    this.size = 200,
    this.animate = true,
  });

  final AvatarMood mood;
  final AvatarConfig config;
  final double size;
  final bool animate;

  @override
  State<PixelAvatar> createState() => _PixelAvatarState();
}

class _PixelAvatarState extends State<PixelAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    if (widget.animate) _controller.repeat();
  }

  @override
  void didUpdateWidget(PixelAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.mood == AvatarMood.spiky && widget.animate) {
      _controller.duration = const Duration(milliseconds: 200);
    } else {
      _controller.duration = const Duration(milliseconds: 1200);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Offset _motionOffset(double t) {
    switch (widget.mood) {
      case AvatarMood.spiky:
        final jitter = math.sin(t * math.pi * 8) * 3;
        return Offset(jitter, 0);
      case AvatarMood.active:
        final walk = math.sin(t * math.pi * 2) * 10;
        return Offset(walk, -2);
      case AvatarMood.calm:
      case AvatarMood.balanced:
        return Offset(0, math.sin(t * math.pi * 2) * 4);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final offset = widget.animate ? _motionOffset(_controller.value) : Offset.zero;
        return Transform.translate(
          offset: offset,
          child: child,
        );
      },
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: CustomPaint(
          painter: _PixelAvatarPainter(
            mood: widget.mood,
            config: widget.config,
          ),
        ),
      ),
    );
  }
}

class _PixelAvatarPainter extends CustomPainter {
  _PixelAvatarPainter({required this.mood, required this.config});

  final AvatarMood mood;
  final AvatarConfig config;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width * 0.5;
    final cy = size.height * 0.58;
    final bodyW = size.width * 0.42;
    final bodyH = size.height * 0.38;

    final bodyColor = config.color.swatch;
    final shade = Color.lerp(bodyColor, Colors.black, 0.18)!;
    final highlight = Color.lerp(bodyColor, Colors.white, 0.15)!;

    // Isometric body: top face
    final top = Path()
      ..moveTo(cx, cy - bodyH * 0.55)
      ..lineTo(cx + bodyW * 0.5, cy - bodyH * 0.25)
      ..lineTo(cx, cy - bodyH * 0.05)
      ..lineTo(cx - bodyW * 0.5, cy - bodyH * 0.25)
      ..close();
    canvas.drawPath(top, Paint()..color = highlight);

    // Left face
    final left = Path()
      ..moveTo(cx - bodyW * 0.5, cy - bodyH * 0.25)
      ..lineTo(cx, cy - bodyH * 0.05)
      ..lineTo(cx, cy + bodyH * 0.45)
      ..lineTo(cx - bodyW * 0.5, cy + bodyH * 0.15)
      ..close();
    canvas.drawPath(left, Paint()..color = shade);

    // Right face
    final right = Path()
      ..moveTo(cx + bodyW * 0.5, cy - bodyH * 0.25)
      ..lineTo(cx, cy - bodyH * 0.05)
      ..lineTo(cx, cy + bodyH * 0.45)
      ..lineTo(cx + bodyW * 0.5, cy + bodyH * 0.15)
      ..close();
    canvas.drawPath(right, Paint()..color = bodyColor);

    _drawEyes(canvas, cx, cy - bodyH * 0.18, bodyW * 0.35);
    _drawMouth(canvas, cx, cy - bodyH * 0.02, bodyW * 0.2);
    _drawHat(canvas, cx, cy - bodyH * 0.55, bodyW);
  }

  void _drawEyes(Canvas canvas, double cx, double cy, double span) {
    final eyePaint = Paint()..color = AppColors.textPrimary;
    final left = Offset(cx - span * 0.35, cy);
    final right = Offset(cx + span * 0.35, cy);

    switch (config.eyes) {
      case AvatarEyesOption.neutral:
      case AvatarEyesOption.dot:
        canvas.drawCircle(left, span * 0.08, eyePaint);
        canvas.drawCircle(right, span * 0.08, eyePaint);
      case AvatarEyesOption.happy:
        _arcEye(canvas, left, span * 0.12, false);
        _arcEye(canvas, right, span * 0.12, false);
      case AvatarEyesOption.wink:
        canvas.drawCircle(left, span * 0.08, eyePaint);
        _arcEye(canvas, right, span * 0.12, true);
      case AvatarEyesOption.squint:
        _arcEye(canvas, left, span * 0.1, true);
        _arcEye(canvas, right, span * 0.1, true);
      case AvatarEyesOption.sleepy:
        _arcEye(canvas, left, span * 0.14, true);
        _arcEye(canvas, right, span * 0.14, true);
      case AvatarEyesOption.blink:
        canvas.drawRect(
          Rect.fromCenter(center: left, width: span * 0.22, height: 2),
          eyePaint,
        );
        canvas.drawRect(
          Rect.fromCenter(center: right, width: span * 0.22, height: 2),
          eyePaint,
        );
      case AvatarEyesOption.star:
        _starEye(canvas, left, span * 0.12, eyePaint);
        _starEye(canvas, right, span * 0.12, eyePaint);
      case AvatarEyesOption.heart:
        _heartEye(canvas, left, span * 0.1, eyePaint);
        _heartEye(canvas, right, span * 0.1, eyePaint);
      case AvatarEyesOption.glasses:
        final frame = Paint()
          ..color = AppColors.textPrimary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
        canvas.drawCircle(left, span * 0.12, frame);
        canvas.drawCircle(right, span * 0.12, frame);
        canvas.drawLine(
          Offset(left.dx + span * 0.12, left.dy),
          Offset(right.dx - span * 0.12, right.dy),
          frame,
        );
    }
  }

  void _arcEye(Canvas canvas, Offset c, double r, bool flat) {
    final paint = Paint()
      ..color = AppColors.textPrimary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawArc(rect, flat ? math.pi * 0.1 : math.pi * 0.15, math.pi * 0.7, false, paint);
  }

  void _starEye(Canvas canvas, Offset c, double r, Paint paint) {
    final path = Path();
    for (var i = 0; i < 5; i++) {
      final angle = -math.pi / 2 + i * 4 * math.pi / 5;
      final pt = Offset(c.dx + math.cos(angle) * r, c.dy + math.sin(angle) * r);
      if (i == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _heartEye(Canvas canvas, Offset c, double r, Paint paint) {
    final path = Path()
      ..moveTo(c.dx, c.dy + r * 0.4)
      ..cubicTo(
        c.dx - r, c.dy - r * 0.2,
        c.dx - r * 0.2, c.dy - r,
        c.dx, c.dy - r * 0.3,
      )
      ..cubicTo(
        c.dx + r * 0.2, c.dy - r,
        c.dx + r, c.dy - r * 0.2,
        c.dx, c.dy + r * 0.4,
      );
    canvas.drawPath(path, paint);
  }

  void _drawMouth(Canvas canvas, double cx, double cy, double w) {
    final paint = Paint()
      ..color = AppColors.textPrimary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final rect = Rect.fromCenter(
      center: Offset(cx, cy + (mood == AvatarMood.spiky ? 2 : 0)),
      width: w,
      height: mood == AvatarMood.spiky ? w * 0.35 : w * 0.25,
    );
    final start = mood == AvatarMood.spiky ? math.pi * 0.15 : math.pi * 0.2;
    final sweep = mood == AvatarMood.spiky ? math.pi * 0.7 : math.pi * 0.55;
    canvas.drawArc(rect, start, sweep, false, paint);
  }

  void _drawHat(Canvas canvas, double cx, double topY, double bodyW) {
    switch (config.hat) {
      case AvatarHatOption.none:
        return;
      case AvatarHatOption.crown:
        final base = Paint()..color = AppColors.primaryGreen;
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset(cx, topY - bodyW * 0.08),
            width: bodyW * 0.55,
            height: bodyW * 0.1,
          ),
          base,
        );
        for (var i = -1; i <= 1; i++) {
          canvas.drawRect(
            Rect.fromCenter(
              center: Offset(cx + i * bodyW * 0.14, topY - bodyW * 0.18),
              width: bodyW * 0.08,
              height: bodyW * 0.14,
            ),
            base,
          );
        }
      case AvatarHatOption.catEars:
        final ear = Paint()..color = config.color.swatch;
        final earShade = Color.lerp(config.color.swatch, Colors.black, 0.2)!;
        canvas.drawPath(
          Path()
            ..moveTo(cx - bodyW * 0.22, topY)
            ..lineTo(cx - bodyW * 0.34, topY - bodyW * 0.22)
            ..lineTo(cx - bodyW * 0.08, topY - bodyW * 0.04)
            ..close(),
          ear,
        );
        canvas.drawPath(
          Path()
            ..moveTo(cx + bodyW * 0.22, topY)
            ..lineTo(cx + bodyW * 0.34, topY - bodyW * 0.22)
            ..lineTo(cx + bodyW * 0.08, topY - bodyW * 0.04)
            ..close(),
          ear..color = earShade,
        );
      case AvatarHatOption.propeller:
        final hub = Paint()..color = AppColors.textMuted;
        canvas.drawCircle(Offset(cx, topY - bodyW * 0.06), bodyW * 0.05, hub);
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset(cx, topY - bodyW * 0.16),
            width: bodyW * 0.5,
            height: bodyW * 0.05,
          ),
          Paint()..color = AppColors.accentOrange,
        );
      case AvatarHatOption.plant:
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset(cx, topY - bodyW * 0.04),
            width: bodyW * 0.2,
            height: bodyW * 0.12,
          ),
          Paint()..color = const Color(0xFF8B5A2B),
        );
        canvas.drawCircle(
          Offset(cx, topY - bodyW * 0.16),
          bodyW * 0.1,
          Paint()..color = AppColors.chartGroceries,
        );
      case AvatarHatOption.cap:
      case AvatarHatOption.beanie:
      case AvatarHatOption.party:
      case AvatarHatOption.headband:
      case AvatarHatOption.tophat:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(cx, topY - bodyW * 0.06),
              width: bodyW * 0.6,
              height: bodyW * 0.12,
            ),
            const Radius.circular(4),
          ),
          Paint()..color = AppColors.primaryGreenDark,
        );
    }
  }

  @override
  bool shouldRepaint(covariant _PixelAvatarPainter oldDelegate) =>
      oldDelegate.mood != mood || oldDelegate.config != config;
}
