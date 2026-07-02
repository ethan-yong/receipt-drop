import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/logic/diorama_props.dart';
import '../domain/logic/diorama_theme.dart';

/// A flat, illustrated "scene card" themed by the category of the user's
/// last receipt: a two-band (wall/floor) flat background plus a handful of
/// flat rounded-rect/circle/text props (drawn in simple list order — no
/// camera, no depth sort), with the avatar standing in front and walking
/// between a few named spots over a slow activity cycle.
///
/// This replaces an earlier hand-rolled fake-3D version (perspective
/// camera, painter's-algorithm depth sort, per-face shading) that kept
/// reading as visually broken no matter how many rounds of fixes it got —
/// flat illustration is a far more forgiving medium, and it reuses all the
/// same per-theme prop content (see `diorama_props.dart`), just drawn flat.
class DioramaScene extends StatefulWidget {
  const DioramaScene({
    super.key,
    required this.theme,
    required this.avatar,
    this.props,
    this.size = 280,
    this.borderRadius,
    double? avatarSize,
  }) : avatarSize = avatarSize ?? size * (80 / 300);

  final DioramaTheme theme;

  /// Pre-built avatar widget (e.g. `PixelAvatar(...)`), bottom-anchored to
  /// whichever floor spot the activity cycle currently has it standing at.
  final Widget avatar;

  final DioramaSceneProps? props;
  final double size;
  final BorderRadius? borderRadius;

  /// Rendered box size for [avatar] — forced via an outer `SizedBox` so its
  /// on-screen footprint relative to the scene is predictable regardless of
  /// whatever size the caller's avatar widget happens to declare
  /// internally. Defaults to a proportion scaled to this card's [size].
  final double avatarSize;

  @override
  State<DioramaScene> createState() => _DioramaSceneState();
}

/// The reference card every prop position in `diorama_props.dart` is
/// authored against; [DioramaScene.size] just scales the final drawing.
const double _kReferenceSize = 300;

/// One pass through the "example movements" cycle. Themes with a
/// [DioramaHotspots] layout (currently just Fast Food) get the full 5-beat
/// named cycle (WALKING / LOOKING AT MENU / PICKING UP ORDER / EATING /
/// HAPPY IDLE), with the avatar actually walking to a different spot in
/// the scene for each beat; themes without one keep a simpler in-place
/// shuffle/lean/sparkle/note loop. Layered on top of the avatar's existing
/// mood-driven bob/jitter, not a replacement for it.
const _kActivityCycle = Duration(seconds: 11);

// Hotspot-cycle phase boundaries, as a fraction of `_kActivityCycle`.
const double _kPhaseWalkEnd = 0.18;
const double _kPhaseMenuEnd = 0.38;
const double _kPhasePickupEnd = 0.58;
const double _kPhaseEatEnd = 0.84;

class _DioramaSceneState extends State<DioramaScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ticker;
  final Stopwatch _activityClock = Stopwatch()..start();

  @override
  void initState() {
    super.initState();
    // Pure per-frame clock so the avatar's walk/lean/sparkle cycle keeps
    // advancing — the scene itself is static now, nothing else needs it.
    _ticker = AnimationController(vsync: this, duration: const Duration(days: 1))
      ..addListener(() => setState(() {}))
      ..repeat();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  /// Triangular 0→1→0 envelope for fading a movement-cycle overlay in then
  /// out across its sub-phase window (`local` in `[0,1]`).
  double _envelope(double local) => local < 0.5 ? local * 2 : (1 - local) * 2;

  /// Smoothstep ease, used to glide the avatar between two hotspots rather
  /// than moving at a constant rate.
  double _smooth(double t) {
    final x = t.clamp(0.0, 1.0);
    return x * x * (3 - 2 * x);
  }

  /// Eases from hotspot [a] to [b] as `t` goes 0→1.
  (double, double) _walkTo((double, double) a, (double, double) b, double t) {
    final e = _smooth(t);
    return (a.$1 + (b.$1 - a.$1) * e, a.$2 + (b.$2 - a.$2) * e);
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.size / _kReferenceSize;
    final avatarSize = widget.avatarSize;
    final hotspots = widget.props?.hotspots;

    final cycleMs = _kActivityCycle.inMilliseconds;
    final phase = (_activityClock.elapsedMilliseconds % cycleMs) / cycleMs;
    var avatarX = _kReferenceSize / 2;
    var avatarY = _kReferenceSize * 0.9;
    var walkShuffle = 0.0;
    var bobY = 0.0;
    var sparkleOpacity = 0.0;
    var noteOpacity = 0.0;
    var noteGlyph = '♪';
    var noteColor = const Color(0xFF6FB8E8);

    if (hotspots != null) {
      // Named 5-beat cycle: the avatar actually walks to a different spot
      // in the scene for each beat (WALKING / LOOKING AT MENU / PICKING UP
      // ORDER / EATING / HAPPY IDLE).
      if (phase < _kPhaseWalkEnd) {
        final t = phase / _kPhaseWalkEnd;
        avatarX = hotspots.idle.$1 + math.sin(t * math.pi * 2) * 10;
        avatarY = hotspots.idle.$2 + math.cos(t * math.pi * 2) * 4;
        walkShuffle = math.sin(t * math.pi * 8) * 5;
      } else if (phase < _kPhaseMenuEnd) {
        final t = (phase - _kPhaseWalkEnd) / (_kPhaseMenuEnd - _kPhaseWalkEnd);
        final walkT = (t / 0.4).clamp(0.0, 1.0);
        (avatarX, avatarY) = _walkTo(hotspots.idle, hotspots.counter, walkT);
        if (walkT < 1) {
          walkShuffle = math.sin(walkT * math.pi * 8) * 5;
        } else {
          sparkleOpacity = _envelope(((t - 0.4) / 0.6).clamp(0.0, 1.0));
        }
      } else if (phase < _kPhasePickupEnd) {
        final t = (phase - _kPhaseMenuEnd) / (_kPhasePickupEnd - _kPhaseMenuEnd);
        final walkT = (t / 0.5).clamp(0.0, 1.0);
        (avatarX, avatarY) = _walkTo(hotspots.counter, hotspots.pickup, walkT);
        if (walkT < 1) {
          walkShuffle = math.sin(walkT * math.pi * 8) * 5;
        } else {
          bobY = _envelope(((t - 0.5) / 0.5).clamp(0.0, 1.0)) * 4;
        }
      } else if (phase < _kPhaseEatEnd) {
        final t = (phase - _kPhasePickupEnd) / (_kPhaseEatEnd - _kPhasePickupEnd);
        final walkT = (t / 0.3).clamp(0.0, 1.0);
        (avatarX, avatarY) = _walkTo(hotspots.pickup, hotspots.seat, walkT);
        if (walkT < 1) {
          walkShuffle = math.sin(walkT * math.pi * 8) * 5;
        } else {
          noteOpacity = _envelope(((t - 0.3) / 0.7).clamp(0.0, 1.0));
          noteGlyph = '\u{1F354}'; // burger
          noteColor = Colors.white;
        }
      } else {
        final t = (phase - _kPhaseEatEnd) / (1 - _kPhaseEatEnd);
        final walkT = (t / 0.3).clamp(0.0, 1.0);
        (avatarX, avatarY) = _walkTo(hotspots.seat, hotspots.idle, walkT);
        if (walkT < 1) {
          walkShuffle = math.sin(walkT * math.pi * 8) * 5;
        } else {
          final bounceT = ((t - 0.3) / 0.7).clamp(0.0, 1.0);
          bobY = math.sin(bounceT * math.pi * 6).abs() * -6;
          sparkleOpacity = _envelope(bounceT);
        }
      }
    } else {
      // Generic in-place cycle for themes without a hotspot layout yet.
      if (phase < 0.3) {
        walkShuffle = math.sin(phase / 0.3 * math.pi * 2) * 6;
      } else if (phase < 0.45) {
        bobY = _envelope((phase - 0.3) / 0.15) * 4;
      } else if (phase < 0.7) {
        sparkleOpacity = _envelope((phase - 0.45) / 0.25);
      } else {
        noteOpacity = _envelope((phase - 0.7) / 0.3);
      }
    }

    final floorAnchor = Offset(avatarX * scale, avatarY * scale);

    Widget content = Stack(
      children: [
        RepaintBoundary(
          child: CustomPaint(
            size: Size.square(widget.size),
            painter: _DioramaPainter(
              theme: widget.theme,
              props: widget.props ?? const DioramaSceneProps(),
            ),
          ),
        ),
        Positioned(
          left: floorAnchor.dx - avatarSize / 2,
          top: floorAnchor.dy - avatarSize,
          width: avatarSize,
          height: avatarSize,
          child: IgnorePointer(
            child: Transform.translate(
              offset: Offset(walkShuffle, bobY),
              child: widget.avatar,
            ),
          ),
        ),
        Positioned(
          left: floorAnchor.dx - 8,
          top: floorAnchor.dy - avatarSize - 18,
          child: IgnorePointer(
            child: Opacity(
              opacity: sparkleOpacity,
              child: const Text('✦', style: TextStyle(fontSize: 16, color: Color(0xFFFFC83D))),
            ),
          ),
        ),
        Positioned(
          left: floorAnchor.dx + 6,
          top: floorAnchor.dy - avatarSize - 18,
          child: IgnorePointer(
            child: Opacity(
              opacity: noteOpacity,
              child: Text(noteGlyph, style: TextStyle(fontSize: 16, color: noteColor)),
            ),
          ),
        ),
      ],
    );

    if (widget.borderRadius != null) {
      content = ClipRRect(borderRadius: widget.borderRadius!, child: content);
    }

    return SizedBox(width: widget.size, height: widget.size, child: content);
  }
}

class _DioramaPainter extends CustomPainter {
  _DioramaPainter({required this.theme, required this.props});

  final DioramaTheme theme;
  final DioramaSceneProps props;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / _kReferenceSize;
    _paintBackground(canvas, size, scale);
    for (final box in props.boxes) {
      _paintBox(canvas, box, scale);
    }
    for (final disk in props.disks) {
      _paintDisk(canvas, disk, scale);
    }
    for (final sign in props.signs) {
      _paintSign(canvas, sign, scale);
    }
  }

  void _paintBackground(Canvas canvas, Size size, double scale) {
    final headerRect = Rect.fromLTWH(0, 0, size.width, 10 * scale);
    canvas.drawRect(headerRect, Paint()..color = theme.wallB);

    const wallFraction = 0.62;
    final wallRect = Rect.fromLTWH(
      0,
      headerRect.height,
      size.width,
      size.height * wallFraction - headerRect.height,
    );
    final floorRect = Rect.fromLTWH(
      0,
      size.height * wallFraction,
      size.width,
      size.height * (1 - wallFraction),
    );

    canvas.drawRect(
      wallRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(theme.wallA, Colors.white, 0.18)!, theme.wallA],
        ).createShader(wallRect),
    );
    canvas.drawRect(
      floorRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [theme.floor, Color.lerp(theme.floor, Colors.black, 0.10)!],
        ).createShader(floorRect),
    );

    final seamRect = Rect.fromLTWH(0, wallRect.bottom - 1.5 * scale, size.width, 3 * scale);
    canvas.drawRect(seamRect, Paint()..color = theme.trim.withValues(alpha: 0.7));
  }

  void _paintBox(Canvas canvas, DioramaBoxSpec box, double scale) {
    final rect = Rect.fromLTWH(box.x * scale, box.y * scale, box.w * scale, box.h * scale);
    final radius = math.min(box.radius * scale, math.min(rect.width, rect.height) / 2);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.lerp(box.color, Colors.white, 0.22)!,
          box.color,
          Color.lerp(box.color, Colors.black, 0.16)!,
        ],
        stops: const [0, 0.5, 1],
      ).createShader(rect);
    canvas.drawRRect(rrect, paint);
  }

  void _paintDisk(Canvas canvas, DioramaDiskSpec disk, double scale) {
    final center = Offset(disk.x * scale, disk.y * scale);
    final radius = disk.radius * scale;
    canvas.drawOval(
      Rect.fromCircle(center: center, radius: radius),
      Paint()
        ..shader = RadialGradient(
          colors: [Color.lerp(disk.color, Colors.white, 0.25)!, disk.color],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  void _paintSign(Canvas canvas, DioramaSignSpec sign, double scale) {
    final anchor = Offset(sign.x * scale, sign.y * scale);
    final painter = TextPainter(
      text: TextSpan(
        text: sign.text,
        style: TextStyle(
          color: sign.textColor,
          fontSize: sign.fontSize * scale,
          fontWeight: FontWeight.w700,
          height: 1.15,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 200 * scale);
    final pad = 4 * scale;
    final rect = Rect.fromCenter(
      center: anchor,
      width: painter.width + pad * 2,
      height: painter.height + pad * 2,
    );
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(3 * scale));
    canvas.drawRRect(rrect, Paint()..color = sign.background);
    if (sign.borderColor != null) {
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = sign.borderColor!
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 * scale,
      );
    }
    painter.paint(canvas, rect.center - Offset(painter.width / 2, painter.height / 2));
  }

  @override
  bool shouldRepaint(covariant _DioramaPainter oldDelegate) => true;
}
