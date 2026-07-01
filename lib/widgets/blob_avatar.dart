import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../domain/logic/avatar_mood.dart';
import '../domain/models/avatar_config.dart';

/// 2D illustrated avatar: a CustomPainter port of Impact Drops' BlobAvatar,
/// extended to render the customizable color/eyes/hat (the source component
/// itself only ever rendered `mood` — color/eyes/hat were wired to the 3D
/// PixelAvatar instead, which isn't being ported, see plan Phase 2 notes).
///
/// Body shape and mouth follow [mood] (a behavioral signal); fill color,
/// eyes, and hat follow [config] (the user's chosen identity) so that
/// customization isn't overridden by mood on every render.
class BlobAvatar extends StatefulWidget {
  const BlobAvatar({
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
  State<BlobAvatar> createState() => _BlobAvatarState();
}

class _BlobAvatarState extends State<BlobAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    if (widget.animate) _controller.repeat();
  }

  @override
  void didUpdateWidget(BlobAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.animate && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The painted avatar is passed as AnimatedBuilder's `child` (built once,
    // reused every frame) so the wobble transform doesn't force the
    // CustomPainter — with its blur mask filters — to repaint 60x/sec.
    final avatar = SizedBox(
      width: widget.size,
      height: widget.size,
      child: CustomPaint(
        painter: _BlobAvatarPainter(mood: widget.mood, config: widget.config),
      ),
    );
    return AnimatedBuilder(
      animation: _controller,
      child: avatar,
      builder: (context, child) {
        // Port of the `wobble` keyframe (4s, single envelope across one
        // cycle): rest pose is translateY(0) rotate(-1deg) scale(1), peaking
        // at translateY(-6px) rotate(1deg) scale(1.02) at the midpoint.
        final envelope = widget.animate
            ? math.sin(math.pi * _controller.value)
            : 0.0;
        final dy = -6.0 * envelope;
        final angleDeg = -1.0 + 2.0 * envelope;
        final scale = 1.0 + 0.02 * envelope;
        return Transform.translate(
          offset: Offset(0, dy),
          child: Transform.rotate(
            angle: angleDeg * math.pi / 180,
            child: Transform.scale(scale: scale, child: child),
          ),
        );
      },
    );
  }
}

class _BlobAvatarPainter extends CustomPainter {
  _BlobAvatarPainter({required this.mood, required this.config});

  final AvatarMood mood;
  final AvatarConfig config;

  Color get _ink => const Color(0xFF1A1A1A);

  Color get _moodColor {
    switch (mood) {
      case AvatarMood.calm:
        return AppColors.moodCalm;
      case AvatarMood.active:
        return AppColors.moodActive;
      case AvatarMood.spiky:
        return AppColors.moodSpiky;
      case AvatarMood.balanced:
        return AppColors.moodBalanced;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 100;
    Offset p(double x, double y) => Offset(x * scale, y * scale);
    double s(double v) => v * scale;

    final center = p(50, 50);

    // Ambient mood glow behind the body — keeps the mood signal present
    // even though body fill color now follows the user's customization.
    final glowPaint = Paint()
      ..color = _moodColor.withValues(alpha: 0.35)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, s(10));
    canvas.drawCircle(center, s(46), glowPaint);

    final spiky = mood == AvatarMood.spiky;
    final bodyPaint = Paint()
      ..color = config.color.swatch
      ..style = PaintingStyle.fill;
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.18)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, s(2));

    final body = spiky ? _spikyPath(p) : _blobPath(p);
    canvas.drawPath(body, shadowPaint..style = PaintingStyle.stroke);
    canvas.drawPath(body, bodyPaint);

    _paintEyes(canvas, p, s, config.eyes);
    _paintMouth(canvas, p, s, mood);
    _paintHat(canvas, p, s, config.hat);
  }

  Path _blobPath(Offset Function(double, double) p) {
    final path = Path()..moveTo(p(50, 10).dx, p(50, 10).dy);
    path.cubicTo(
      p(72, 10).dx, p(72, 10).dy,
      p(90, 28).dx, p(90, 28).dy,
      p(90, 50).dx, p(90, 50).dy,
    );
    path.cubicTo(
      p(90, 70).dx, p(90, 70).dy,
      p(74, 90).dx, p(74, 90).dy,
      p(50, 90).dx, p(50, 90).dy,
    );
    path.cubicTo(
      p(26, 90).dx, p(26, 90).dy,
      p(10, 70).dx, p(10, 70).dy,
      p(10, 50).dx, p(10, 50).dy,
    );
    path.cubicTo(
      p(10, 28).dx, p(10, 28).dy,
      p(28, 10).dx, p(28, 10).dy,
      p(50, 10).dx, p(50, 10).dy,
    );
    path.close();
    return path;
  }

  Path _spikyPath(Offset Function(double, double) p) {
    const pts = [
      [50.0, 8.0], [62.0, 22.0], [82.0, 18.0], [74.0, 38.0],
      [92.0, 50.0], [74.0, 62.0], [82.0, 82.0], [62.0, 78.0],
      [50.0, 92.0], [38.0, 78.0], [18.0, 82.0], [26.0, 62.0],
      [8.0, 50.0], [26.0, 38.0], [18.0, 18.0], [38.0, 22.0],
    ];
    final path = Path()..moveTo(p(pts[0][0], pts[0][1]).dx, p(pts[0][0], pts[0][1]).dy);
    for (final pt in pts.skip(1)) {
      final o = p(pt[0], pt[1]);
      path.lineTo(o.dx, o.dy);
    }
    path.close();
    return path;
  }

  void _paintEyes(
    Canvas canvas,
    Offset Function(double, double) p,
    double Function(double) s,
    AvatarEyesOption eyes,
  ) {
    final fill = Paint()..color = _ink;
    final stroke = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = s(1.4)
      ..strokeCap = StrokeCap.round;

    void ovalEye(double cx, double cy, double rx, double ry) {
      canvas.drawOval(
        Rect.fromCenter(center: p(cx, cy), width: s(rx * 2), height: s(ry * 2)),
        fill,
      );
    }

    void closedEye(double cx, double cy) {
      final path = Path()
        ..moveTo(p(cx - 3, cy).dx, p(cx - 3, cy).dy)
        ..quadraticBezierTo(
          p(cx, cy - 2.5).dx, p(cx, cy - 2.5).dy,
          p(cx + 3, cy).dx, p(cx + 3, cy).dy,
        );
      canvas.drawPath(path, stroke);
    }

    void starEye(double cx, double cy) {
      final path = Path();
      const points = 4;
      const outer = 3.6;
      const inner = 1.3;
      for (var i = 0; i < points * 2; i++) {
        final r = i.isEven ? outer : inner;
        final angle = (math.pi / points) * i - math.pi / 2;
        final o = p(cx + r * math.cos(angle), cy + r * math.sin(angle));
        if (i == 0) {
          path.moveTo(o.dx, o.dy);
        } else {
          path.lineTo(o.dx, o.dy);
        }
      }
      path.close();
      canvas.drawPath(path, fill);
    }

    void heartEye(double cx, double cy) {
      final path = Path()
        ..moveTo(p(cx, cy + 2.6).dx, p(cx, cy + 2.6).dy)
        ..cubicTo(
          p(cx - 4.2, cy - 1.6).dx, p(cx - 4.2, cy - 1.6).dy,
          p(cx - 1.6, cy - 4.4).dx, p(cx - 1.6, cy - 4.4).dy,
          p(cx, cy - 1.6).dx, p(cx, cy - 1.6).dy,
        )
        ..cubicTo(
          p(cx + 1.6, cy - 4.4).dx, p(cx + 1.6, cy - 4.4).dy,
          p(cx + 4.2, cy - 1.6).dx, p(cx + 4.2, cy - 1.6).dy,
          p(cx, cy + 2.6).dx, p(cx, cy + 2.6).dy,
        )
        ..close();
      canvas.drawPath(path, fill);
    }

    void glassesEye(double cx, double cy) {
      canvas.drawCircle(p(cx, cy), s(4), stroke);
      canvas.drawCircle(p(cx, cy), s(1.5), fill);
    }

    const leftX = 38.0, rightX = 62.0, eyeY = 46.0;

    switch (eyes) {
      case AvatarEyesOption.neutral:
        ovalEye(leftX, eyeY, 3, 4);
        ovalEye(rightX, eyeY, 3, 4);
      case AvatarEyesOption.dot:
        canvas.drawCircle(p(leftX, eyeY), s(1.8), fill);
        canvas.drawCircle(p(rightX, eyeY), s(1.8), fill);
      case AvatarEyesOption.happy:
        ovalEye(leftX, eyeY, 3, 1.5);
        ovalEye(rightX, eyeY, 3, 1.5);
      case AvatarEyesOption.wink:
        closedEye(leftX, eyeY);
        ovalEye(rightX, eyeY, 3, 4);
      case AvatarEyesOption.squint:
        ovalEye(leftX, eyeY, 4, 1);
        ovalEye(rightX, eyeY, 4, 1);
      case AvatarEyesOption.sleepy:
        closedEye(leftX, eyeY - 1);
        closedEye(rightX, eyeY - 1);
      case AvatarEyesOption.blink:
        canvas.drawLine(p(leftX - 3, eyeY), p(leftX + 3, eyeY), stroke);
        canvas.drawLine(p(rightX - 3, eyeY), p(rightX + 3, eyeY), stroke);
      case AvatarEyesOption.star:
        starEye(leftX, eyeY);
        starEye(rightX, eyeY);
      case AvatarEyesOption.heart:
        heartEye(leftX, eyeY);
        heartEye(rightX, eyeY);
      case AvatarEyesOption.glasses:
        glassesEye(leftX, eyeY);
        glassesEye(rightX, eyeY);
        canvas.drawLine(p(leftX + 4, eyeY), p(rightX - 4, eyeY), stroke);
    }
  }

  void _paintMouth(
    Canvas canvas,
    Offset Function(double, double) p,
    double Function(double) s,
    AvatarMood mood,
  ) {
    final fill = Paint()..color = _ink;
    final stroke = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = s(2)
      ..strokeCap = StrokeCap.round;

    switch (mood) {
      case AvatarMood.calm:
        final path = Path()
          ..moveTo(p(42, 60).dx, p(42, 60).dy)
          ..quadraticBezierTo(p(50, 66).dx, p(50, 66).dy, p(58, 60).dx, p(58, 60).dy);
        canvas.drawPath(path, stroke);
      case AvatarMood.balanced:
        canvas.drawLine(p(44, 62), p(56, 62), stroke);
      case AvatarMood.active:
        canvas.drawOval(
          Rect.fromCenter(center: p(50, 62), width: s(8), height: s(6)),
          fill,
        );
      case AvatarMood.spiky:
        canvas.drawOval(
          Rect.fromCenter(center: p(50, 63), width: s(10), height: s(10)),
          fill,
        );
    }
  }

  void _paintHat(
    Canvas canvas,
    Offset Function(double, double) p,
    double Function(double) s,
    AvatarHatOption hat,
  ) {
    final fill = Paint()..color = AppColors.textPrimary;
    final accent = Paint()..color = AppColors.primaryGreen;

    Path triangle(double x1, double y1, double x2, double y2, double x3, double y3) {
      return Path()
        ..moveTo(p(x1, y1).dx, p(x1, y1).dy)
        ..lineTo(p(x2, y2).dx, p(x2, y2).dy)
        ..lineTo(p(x3, y3).dx, p(x3, y3).dy)
        ..close();
    }

    switch (hat) {
      case AvatarHatOption.none:
        break;
      case AvatarHatOption.cap:
        canvas.drawArc(
          Rect.fromCenter(center: p(50, 16), width: s(40), height: s(24)),
          math.pi,
          math.pi,
          true,
          fill,
        );
        canvas.drawRect(
          Rect.fromLTWH(p(62, 14).dx, p(62, 14).dy, s(16), s(4)),
          fill,
        );
      case AvatarHatOption.beanie:
        canvas.drawArc(
          Rect.fromCenter(center: p(50, 12), width: s(44), height: s(28)),
          math.pi,
          math.pi,
          true,
          fill,
        );
        canvas.drawCircle(p(50, 2), s(4), accent);
      case AvatarHatOption.crown:
        for (final cx in [36.0, 50.0, 64.0]) {
          canvas.drawPath(triangle(cx - 6, 16, cx, 4, cx + 6, 16), accent);
          canvas.drawCircle(p(cx, 4), s(2), fill);
        }
      case AvatarHatOption.party:
        canvas.drawPath(triangle(38, 16, 50, 2, 62, 16), accent);
        canvas.drawCircle(p(50, 2), s(3), fill);
      case AvatarHatOption.headband:
        canvas.drawRect(
          Rect.fromLTWH(p(28, 16).dx, p(28, 16).dy, s(44), s(6)),
          accent,
        );
        canvas.drawPath(triangle(46, 19, 50, 14, 54, 19), fill);
      case AvatarHatOption.catEars:
        canvas.drawPath(triangle(30, 16, 35, 3, 40, 16), fill);
        canvas.drawPath(triangle(60, 16, 65, 3, 70, 16), fill);
      case AvatarHatOption.plant:
        canvas.drawRect(
          Rect.fromLTWH(p(44, 8).dx, p(44, 8).dy, s(12), s(8)),
          fill,
        );
        canvas.drawOval(
          Rect.fromCenter(center: p(46, 2), width: s(8), height: s(10)),
          accent,
        );
        canvas.drawOval(
          Rect.fromCenter(center: p(54, 2), width: s(8), height: s(10)),
          accent,
        );
      case AvatarHatOption.propeller:
        canvas.drawArc(
          Rect.fromCenter(center: p(50, 14), width: s(36), height: s(22)),
          math.pi,
          math.pi,
          true,
          fill,
        );
        canvas.drawLine(p(36, 3), p(64, 3), accent);
        canvas.drawCircle(p(50, 3), s(2), fill);
      case AvatarHatOption.tophat:
        canvas.drawRect(
          Rect.fromLTWH(p(40, 0).dx, p(40, 0).dy, s(20), s(14)),
          fill,
        );
        canvas.drawRect(
          Rect.fromLTWH(p(32, 12).dx, p(32, 12).dy, s(36), s(5)),
          fill,
        );
    }
  }

  @override
  bool shouldRepaint(covariant _BlobAvatarPainter oldDelegate) {
    return oldDelegate.mood != mood || oldDelegate.config != config;
  }
}
