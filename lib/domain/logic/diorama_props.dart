import 'package:flutter/material.dart';

import 'diorama_theme.dart';

/// One flat rounded-rect prop, in a 300×300 reference card: origin
/// top-left, `+x` right, `+y` down. `x` spans `[x, x+w]`, `y` spans
/// `[y, y+h]`. `groundY = 270` is the shared "floor line" that every
/// floor-resting prop's bottom edge (`y + h`) touches — props mounted
/// higher up (signage, shelving) sit at a smaller `y`.
///
/// These positions were ported from the previous fake-3D layout via
/// `x: oldX + 150`, `y: 270 + oldY * 2`, `h: oldH * 2` (kept as literal
/// arithmetic below so the original authored values stay visible) —
/// reusing all the already-tuned per-theme content without re-deriving it,
/// now drawn flat instead of projected through a camera.
class DioramaBoxSpec {
  const DioramaBoxSpec({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.color,
    this.radius = 4,
  });

  final double x;
  final double y;
  final double w;
  final double h;
  final Color color;
  final double radius;
}

/// A small flat circular prop (fruit, wheel, tire, bulb), centered at
/// `(x, y)` in the same reference space as [DioramaBoxSpec]. Radius is
/// kept unscaled relative to the old layout (only positions were rescaled)
/// so circles stay round and proportionate to box widths.
class DioramaDiskSpec {
  const DioramaDiskSpec({
    required this.x,
    required this.y,
    required this.radius,
    required this.color,
  });

  final double x;
  final double y;
  final double radius;
  final Color color;
}

/// A small text label (storefront signage), anchored at `(x, y)`.
class DioramaSignSpec {
  const DioramaSignSpec({
    required this.x,
    required this.y,
    required this.text,
    required this.background,
    this.textColor = Colors.white,
    this.fontSize = 11,
    this.borderColor,
  });

  final double x;
  final double y;
  final String text;
  final Color background;
  final Color textColor;
  final double fontSize;

  /// Optional thin outline (e.g. a tan card border on a white menu board).
  final Color? borderColor;
}

/// Named flat-card `(x, y)` anchor points within a themed scene that the
/// avatar walks between during its activity cycle (see `DioramaScene`).
/// Only themes with a detailed reference layout define these; the rest
/// fall back to a simple in-place shuffle.
class DioramaHotspots {
  const DioramaHotspots({
    required this.idle,
    required this.counter,
    required this.pickup,
    required this.seat,
  });

  /// Default standing spot used for the "wander" beat and as the walk
  /// cycle's start/end point.
  final (double, double) idle;

  /// Stand here to look up at the menu board.
  final (double, double) counter;

  /// Stand here to collect the order from the pick-up window.
  final (double, double) pickup;

  /// Sit here to eat.
  final (double, double) seat;
}

/// All the prop content for one themed scene. Draw order is `boxes` then
/// `disks` then `signs`, each in list order — flat layering needs no depth
/// sort, so the list order alone determines what's in front of what
/// (later entries painted on top).
class DioramaSceneProps {
  const DioramaSceneProps({
    this.boxes = const [],
    this.disks = const [],
    this.signs = const [],
    this.hotspots,
  });

  final List<DioramaBoxSpec> boxes;
  final List<DioramaDiskSpec> disks;
  final List<DioramaSignSpec> signs;
  final DioramaHotspots? hotspots;
}

const _woodLight = Color(0xFFB98654);
const _grocRed = Color(0xFFD9534F);
const _grocGreen = Color(0xFF5CB85C);
const _grocAmber = Color(0xFFE8B23D);
const _cartGray = Color(0xFFD8DCDE);
const _wheelDark = Color(0xFF333333);
const _glassBlue = Color(0xFFCFE7EF);
const _pastryTan = Color(0xFFD2A679);
const _machineWhite = Color(0xFFEDEDE5);
const _leafGreen = Color(0xFF6FA850);
const _leafGreenLight = Color(0xFF7FB35C);
const _tireBlack = Color(0xFF2B2B2B);
const _skinTone = Color(0xFFE8D6C0);
const _bulbYellow = Color(0xFFFCE8A8);

/// Fast Food's exact "Home Platform Design Sheet" palette: WALLS, ACCENT,
/// FLOOR, COUNTER, METAL, WOOD, PLANT. `wallA`/`floor`/`accent`/`trim` on
/// `dioramaThemes[fastFood]` already carry the first four (and WOOD) — these
/// extra two (COUNTER, METAL, PLANT) aren't part of the 5-slot theme struct,
/// so the room layout below references them directly.
const _ffCounter = Color(0xFFFFE0BA);
const _ffMetal = Color(0xFFD1C7BA);
const _ffPlant = Color(0xFF6FA24A);
const _ffDark = Color(0xFF3A332D);
const _ffScreenDark = Color(0xFF2B2B2B);

/// Reference-matched flat scene layouts — the five named categories get
/// full storefront detail (signage, shelving, counters, furniture); the
/// remaining bonus themes keep their simpler boxes-only layouts since they
/// aren't part of that reference.
DioramaSceneProps dioramaPropsFor(DioramaTheme theme) {
  switch (theme.id) {
    case DioramaThemeId.grocery:
      return DioramaSceneProps(
        signs: [
          DioramaSignSpec(x: -55 + 150, y: 270 + -122 * 2, text: 'FRESH MART', background: theme.accent, fontSize: 12),
        ],
        boxes: [
          DioramaBoxSpec(x: -88 + 150, y: 270 + -92 * 2, w: 4, h: 92 * 2, color: theme.trim),
          for (final oldY in [-26.0, -52.0, -78.0])
            DioramaBoxSpec(x: -85 + 150, y: 270 + oldY * 2, w: 75, h: 3 * 2, color: theme.trim),
          for (var row = 0; row < 3; row++)
            for (var col = 0; col < 6; col++)
              DioramaBoxSpec(
                x: -80 + col * 12 + 150,
                y: 270 + (-42.0 - row * 26) * 2,
                w: 9,
                h: 14 * 2,
                color: [_grocRed, _grocGreen, _grocAmber][col % 3],
              ),
          DioramaBoxSpec(x: 28 + 150, y: 270 + -18 * 2, w: 42, h: 18 * 2, color: _woodLight),
          DioramaBoxSpec(x: 72 + 150, y: 270 + -82 * 2, w: 18, h: 48 * 2, color: const Color(0xFFBFE0EE)),
          DioramaBoxSpec(x: 80 + 150, y: 270 + -82 * 2, w: 2, h: 48 * 2, color: theme.trim),
          DioramaBoxSpec(x: 25 + 150, y: 270 + -20 * 2, w: 26, h: 18 * 2, color: _cartGray),
          DioramaBoxSpec(x: 44 + 150, y: 270 + -34 * 2, w: 3, h: 16 * 2, color: theme.trim),
        ],
        disks: [
          DioramaDiskSpec(x: 34 + 150, y: 270 + -19 * 2, radius: 7, color: _grocRed),
          DioramaDiskSpec(x: 44 + 150, y: 270 + -19 * 2, radius: 6, color: _leafGreen),
          DioramaDiskSpec(x: 54 + 150, y: 270 + -19 * 2, radius: 7, color: const Color(0xFFE0552E)),
          DioramaDiskSpec(x: 64 + 150, y: 270 + -19 * 2, radius: 6, color: _grocRed),
          DioramaDiskSpec(x: 38 + 150, y: 270 + -19 * 2, radius: 6, color: _leafGreenLight),
          DioramaDiskSpec(x: 30 + 150, y: 270 + -2 * 2, radius: 4, color: _wheelDark),
          DioramaDiskSpec(x: 46 + 150, y: 270 + -2 * 2, radius: 4, color: _wheelDark),
        ],
      );

    case DioramaThemeId.cafe:
      return DioramaSceneProps(
        signs: [
          DioramaSignSpec(x: -45 + 150, y: 270 + -124 * 2, text: 'COZY CAFE', background: theme.accent, fontSize: 12),
          DioramaSignSpec(
            x: -20 + 150,
            y: 270 + -120 * 2,
            text: 'COFFEE • LATTE\nESPRESSO • TEA',
            background: theme.trim,
            textColor: theme.wallA,
            fontSize: 8,
          ),
          DioramaSignSpec(
            x: -58 + 150,
            y: 270 + -32 * 2,
            text: 'COFFEE\nMAKES YOU\nHAPPY',
            background: theme.wallA,
            textColor: theme.trim,
            fontSize: 7,
          ),
        ],
        boxes: [
          DioramaBoxSpec(x: -70 + 150, y: 270 + -100 * 2, w: 70, h: 8 * 2, color: theme.accent),
          DioramaBoxSpec(x: -80 + 150, y: 270 + -30 * 2, w: 70, h: 30 * 2, color: theme.accent),
          DioramaBoxSpec(x: -78 + 150, y: 270 + -58 * 2, w: 30, h: 26 * 2, color: _glassBlue),
          DioramaBoxSpec(x: -72 + 150, y: 270 + -50 * 2, w: 8, h: 8 * 2, color: _pastryTan),
          DioramaBoxSpec(x: -62 + 150, y: 270 + -50 * 2, w: 8, h: 8 * 2, color: _pastryTan),
          DioramaBoxSpec(x: -40 + 150, y: 270 + -58 * 2, w: 22, h: 24 * 2, color: _machineWhite),
          DioramaBoxSpec(x: -38 + 150, y: 270 + -38 * 2, w: 6, h: 8 * 2, color: theme.trim),
          DioramaBoxSpec(x: 38 + 150, y: 270 + -28 * 2, w: 24, h: 3 * 2, color: theme.trim),
          DioramaBoxSpec(x: 48 + 150, y: 270 + -26 * 2, w: 4, h: 26 * 2, color: theme.trim),
          DioramaBoxSpec(x: 66 + 150, y: 270 + -16 * 2, w: 14, h: 3 * 2, color: theme.accent),
          DioramaBoxSpec(x: 66 + 150, y: 270 + -30 * 2, w: 14, h: 16 * 2, color: theme.accent),
          DioramaBoxSpec(x: -65 + 150, y: 270 + -26 * 2, w: 14, h: 22 * 2, color: theme.trim),
          DioramaBoxSpec(x: 70 + 150, y: 270 + -14 * 2, w: 14, h: 14 * 2, color: const Color(0xFFB89B7A)),
        ],
        disks: [
          DioramaDiskSpec(x: 77 + 150, y: 270 + -26 * 2, radius: 10, color: _leafGreen),
          DioramaDiskSpec(x: 72 + 150, y: 270 + -30 * 2, radius: 8, color: _leafGreenLight),
        ],
      );

    case DioramaThemeId.petrol:
      return DioramaSceneProps(
        signs: [
          DioramaSignSpec(x: -35 + 150, y: 270 + -126 * 2, text: 'FUEL UP', background: theme.accent, fontSize: 13),
          DioramaSignSpec(
            x: -75 + 150,
            y: 270 + -22 * 2,
            text: 'DRIVE\nSAFE',
            background: Colors.white,
            textColor: theme.accent,
            fontSize: 8,
          ),
        ],
        boxes: [
          DioramaBoxSpec(x: -95 + 150, y: 270 + -100 * 2, w: 190, h: 10 * 2, color: theme.accent),
          for (final baseX in [-25.0, 10.0]) ...[
            DioramaBoxSpec(x: baseX + 150, y: 270 + -50 * 2, w: 20, h: 50 * 2, color: _machineWhite),
            DioramaBoxSpec(x: baseX + 3 + 150, y: 270 + -44 * 2, w: 14, h: 12 * 2, color: theme.trim),
            DioramaBoxSpec(x: baseX + 22 + 150, y: 270 + -40 * 2, w: 4, h: 10 * 2, color: theme.trim),
          ],
          DioramaBoxSpec(x: 70 + 150, y: 270 + -80 * 2, w: 18, h: 80 * 2, color: theme.trim),
          DioramaBoxSpec(x: 18 + 150, y: 270 + -10 * 2, w: 12, h: 10 * 2, color: theme.accent),
          DioramaBoxSpec(x: 21 + 150, y: 270 + -16 * 2, w: 6, h: 8 * 2, color: theme.accent),
        ],
        disks: [
          DioramaDiskSpec(x: -75 + 150, y: 270 + -8 * 2, radius: 12, color: _tireBlack),
          DioramaDiskSpec(x: -75 + 150, y: 270 + -20 * 2, radius: 12, color: _tireBlack),
          DioramaDiskSpec(x: -75 + 150, y: 270 + -32 * 2, radius: 12, color: _tireBlack),
        ],
      );

    case DioramaThemeId.shopping:
      return DioramaSceneProps(
        signs: [
          DioramaSignSpec(x: -50 + 150, y: 270 + -124 * 2, text: 'SALE 50% OFF', background: theme.accent, fontSize: 11),
          DioramaSignSpec(x: 24 + 150, y: 270 + -32 * 2, text: 'NEW', background: Colors.white, textColor: theme.accent, fontSize: 7),
        ],
        boxes: [
          DioramaBoxSpec(x: -85 + 150, y: 270 + -78 * 2, w: 70, h: 3 * 2, color: theme.trim),
          DioramaBoxSpec(x: -85 + 150, y: 270 + -78 * 2, w: 3, h: 78 * 2, color: theme.trim),
          DioramaBoxSpec(x: -18 + 150, y: 270 + -78 * 2, w: 3, h: 78 * 2, color: theme.trim),
          for (var i = 0; i < 5; i++)
            DioramaBoxSpec(
              x: -80 + i * 13 + 150,
              y: 270 + -74 * 2,
              w: 11,
              h: 30 * 2,
              color: [
                const Color(0xFFE0556B),
                const Color(0xFFEFC9CE),
                const Color(0xFFC97B4A),
                const Color(0xFF5B5A99),
                const Color(0xFFEDE2B8),
              ][i],
            ),
          DioramaBoxSpec(x: 42 + 150, y: 270 + -60 * 2, w: 14, h: 50 * 2, color: const Color(0xFFEFC9CE)),
          DioramaBoxSpec(x: 65 + 150, y: 270 + -90 * 2, w: 20, h: 50 * 2, color: const Color(0xFFEFE9E0)),
          DioramaBoxSpec(x: -28 + 150, y: 270 + -20 * 2, w: 14, h: 20 * 2, color: theme.accent),
          DioramaBoxSpec(x: -12 + 150, y: 270 + -16 * 2, w: 12, h: 16 * 2, color: const Color(0xFFEFC9CE)),
          DioramaBoxSpec(x: 20 + 150, y: 270 + -14 * 2, w: 24, h: 14 * 2, color: theme.trim),
          DioramaBoxSpec(x: 24 + 150, y: 270 + -20 * 2, w: 16, h: 3 * 2, color: const Color(0xFFE0556B)),
          DioramaBoxSpec(x: 24 + 150, y: 270 + -24 * 2, w: 16, h: 3 * 2, color: const Color(0xFFC97B4A)),
          DioramaBoxSpec(x: 24 + 150, y: 270 + -28 * 2, w: 16, h: 3 * 2, color: const Color(0xFFEDE2B8)),
        ],
        disks: [
          DioramaDiskSpec(x: 49 + 150, y: 270 + -66 * 2, radius: 6, color: _skinTone),
          DioramaDiskSpec(x: 66 + 150, y: 270 + -92 * 2, radius: 2, color: _bulbYellow),
          DioramaDiskSpec(x: 70 + 150, y: 270 + -92 * 2, radius: 2, color: _bulbYellow),
          DioramaDiskSpec(x: 74 + 150, y: 270 + -92 * 2, radius: 2, color: _bulbYellow),
          DioramaDiskSpec(x: 78 + 150, y: 270 + -92 * 2, radius: 2, color: _bulbYellow),
          DioramaDiskSpec(x: 82 + 150, y: 270 + -92 * 2, radius: 2, color: _bulbYellow),
        ],
      );

    case DioramaThemeId.fastFood:
      return DioramaSceneProps(
        // Hand-placed on the open floor strip below `groundY=270` — the
        // counter/window/table all rest with their bottoms at 270, so the
        // avatar's spots stand just in front of (or, for `seat`, right at)
        // each one.
        hotspots: const DioramaHotspots(
          idle: (150, 286),
          counter: (127, 280),
          pickup: (184, 280),
          seat: (191, 268),
        ),
        signs: [
          DioramaSignSpec(x: 78, y: 62, text: 'HOT & TASTY', background: Colors.white, textColor: theme.accent, fontSize: 8, borderColor: _ffCounter),
          DioramaSignSpec(x: 118, y: 66, text: '🍔', background: Colors.white, fontSize: 16, borderColor: _ffCounter),
          DioramaSignSpec(x: 137, y: 66, text: '🍟', background: Colors.white, fontSize: 16, borderColor: _ffCounter),
          DioramaSignSpec(x: 156, y: 66, text: '🥤', background: Colors.white, fontSize: 16, borderColor: _ffCounter),
          DioramaSignSpec(x: 184, y: 126, text: 'PICK UP\nHERE', background: theme.accent, textColor: Colors.white, fontSize: 8),
          DioramaSignSpec(x: 184, y: 172, text: '🛍️', background: _glassBlue, fontSize: 13),
        ],
        boxes: [
          // Counter: pale ledge on top of a red facade.
          DioramaBoxSpec(x: 84, y: 206, w: 86, h: 10, color: _ffCounter),
          DioramaBoxSpec(x: 84, y: 216, w: 86, h: 54, color: theme.accent),
          // Food tray on the ledge's left side (burger + fries + drink).
          DioramaBoxSpec(x: 88, y: 196, w: 28, h: 10, color: theme.accent, radius: 3),
          DioramaBoxSpec(x: 90, y: 186, w: 10, h: 10, color: const Color(0xFFE0A85C), radius: 5),
          DioramaBoxSpec(x: 102, y: 184, w: 7, h: 12, color: theme.accent, radius: 2),
          DioramaBoxSpec(x: 111, y: 182, w: 7, h: 14, color: Colors.white, radius: 2),
          DioramaBoxSpec(x: 114, y: 176, w: 1.5, h: 8, color: theme.trim, radius: 0),
          // Register, drink dispenser, espresso machine on the ledge's
          // right side, left to right.
          DioramaBoxSpec(x: 122, y: 156, w: 16, h: 50, color: Color.lerp(_ffMetal, Colors.white, 0.2)!),
          DioramaBoxSpec(x: 125, y: 162, w: 10, h: 14, color: _ffScreenDark),
          DioramaBoxSpec(x: 140, y: 146, w: 16, h: 60, color: _ffDark),
          DioramaBoxSpec(x: 142, y: 168, w: 3, h: 5, color: theme.floor),
          DioramaBoxSpec(x: 146, y: 168, w: 3, h: 5, color: theme.floor),
          DioramaBoxSpec(x: 150, y: 168, w: 3, h: 5, color: theme.floor),
          DioramaBoxSpec(x: 158, y: 154, w: 12, h: 52, color: _ffMetal),
          DioramaBoxSpec(x: 161, y: 200, w: 6, h: 6, color: Colors.white, radius: 2),
          // Pick-up window, set into the counter facade.
          DioramaBoxSpec(x: 170, y: 154, w: 26, h: 64, color: theme.trim),
          DioramaBoxSpec(x: 172, y: 158, w: 22, h: 56, color: _glassBlue),
          DioramaBoxSpec(x: 168, y: 212, w: 30, h: 8, color: theme.accent),
          // Dining table (round top + pedestal) + two chairs.
          DioramaBoxSpec(x: 189, y: 234, w: 4, h: 36, color: _ffScreenDark),
          DioramaBoxSpec(x: 162, y: 224, w: 12, h: 32, color: theme.accent, radius: 5),
          DioramaBoxSpec(x: 160, y: 254, w: 16, h: 16, color: theme.accent, radius: 4),
          DioramaBoxSpec(x: 208, y: 224, w: 12, h: 32, color: theme.accent, radius: 5),
          DioramaBoxSpec(x: 206, y: 254, w: 16, h: 16, color: theme.accent, radius: 4),
          // Plant decor in the corner.
          DioramaBoxSpec(x: 238, y: 242, w: 16, h: 28, color: theme.trim),
        ],
        disks: [
          DioramaDiskSpec(x: 104, y: 180, radius: 2, color: theme.floor),
          DioramaDiskSpec(x: 107, y: 178, radius: 2, color: theme.floor),
          DioramaDiskSpec(x: 191, y: 228, radius: 15, color: Colors.white),
          DioramaDiskSpec(x: 248, y: 220, radius: 9, color: _ffPlant),
          DioramaDiskSpec(x: 240, y: 214, radius: 7, color: _ffPlant),
          DioramaDiskSpec(x: 256, y: 216, radius: 7, color: _ffPlant),
          DioramaDiskSpec(x: 244, y: 204, radius: 6, color: _ffPlant),
          DioramaDiskSpec(x: 252, y: 206, radius: 6, color: _ffPlant),
        ],
      );

    case DioramaThemeId.gym:
      return DioramaSceneProps(boxes: [
        DioramaBoxSpec(x: -81 + 150, y: 270 + -6 * 2, w: 30, h: 6 * 2, color: theme.trim),
        DioramaBoxSpec(x: -81 + 150, y: 270 + -26 * 2, w: 30, h: 20 * 2, color: const Color(0xFF3A3F4D)),
        DioramaBoxSpec(x: -20 + 150, y: 270 + -24 * 2, w: 70, h: 4 * 2, color: theme.trim),
        for (var i = 0; i < 4; i++)
          DioramaBoxSpec(x: -16 + i * 16 + 150, y: 270 + -30 * 2, w: 6, h: 6 * 2, color: theme.accent),
        DioramaBoxSpec(x: 16 + 150, y: 270 + -2 * 2, w: 36, h: 2 * 2, color: const Color(0xFFC9714A)),
      ]);

    case DioramaThemeId.electronics:
      return DioramaSceneProps(boxes: [
        DioramaBoxSpec(x: -42 + 150, y: 270 + -116 * 2, w: 26, h: 20 * 2, color: const Color(0xFF3E7FD1)),
        DioramaBoxSpec(x: -12 + 150, y: 270 + -116 * 2, w: 26, h: 20 * 2, color: const Color(0xFFC149B8)),
        DioramaBoxSpec(x: 18 + 150, y: 270 + -116 * 2, w: 26, h: 20 * 2, color: const Color(0xFF3FA869)),
        DioramaBoxSpec(x: -45 + 150, y: 270 + -24 * 2, w: 90, h: 24 * 2, color: theme.trim),
        DioramaBoxSpec(x: -28 + 150, y: 270 + -30 * 2, w: 18, h: 6 * 2, color: const Color(0xFF2E2A45)),
        DioramaBoxSpec(x: 2 + 150, y: 270 + -30 * 2, w: 18, h: 6 * 2, color: const Color(0xFF2E2A45)),
        DioramaBoxSpec(x: -45 + 150, y: 270 + -80 * 2, w: 90, h: 2 * 2, color: theme.accent),
      ]);

    case DioramaThemeId.beauty:
      return DioramaSceneProps(
        boxes: [
          DioramaBoxSpec(x: -40 + 150, y: 270 + -26 * 2, w: 80, h: 26 * 2, color: theme.accent),
          DioramaBoxSpec(x: -24 + 150, y: 270 + -100 * 2, w: 48, h: 56 * 2, color: const Color(0xFFF5F2F0)),
          DioramaBoxSpec(x: -30 + 150, y: 270 + -40 * 2, w: 6, h: 14 * 2, color: const Color(0xFFF0AFC0)),
          DioramaBoxSpec(x: -20 + 150, y: 270 + -40 * 2, w: 6, h: 14 * 2, color: const Color(0xFFEAB58C)),
          DioramaBoxSpec(x: -10 + 150, y: 270 + -40 * 2, w: 6, h: 14 * 2, color: const Color(0xFFB7A8D9)),
          DioramaBoxSpec(x: 0 + 150, y: 270 + -40 * 2, w: 6, h: 14 * 2, color: const Color(0xFFEDE2B8)),
          DioramaBoxSpec(x: 30 + 150, y: 270 + -18 * 2, w: 16, h: 3 * 2, color: theme.trim),
          DioramaBoxSpec(x: 36 + 150, y: 270 + -18 * 2, w: 3, h: 18 * 2, color: theme.trim),
        ],
        disks: [
          DioramaDiskSpec(x: -20 + 150, y: 270 + -106 * 2, radius: 2, color: const Color(0xFFF2DE9E)),
          DioramaDiskSpec(x: -10 + 150, y: 270 + -106 * 2, radius: 2, color: const Color(0xFFF2DE9E)),
          DioramaDiskSpec(x: 0 + 150, y: 270 + -106 * 2, radius: 2, color: const Color(0xFFF2DE9E)),
          DioramaDiskSpec(x: 10 + 150, y: 270 + -106 * 2, radius: 2, color: const Color(0xFFF2DE9E)),
          DioramaDiskSpec(x: 20 + 150, y: 270 + -106 * 2, radius: 2, color: const Color(0xFFF2DE9E)),
        ],
      );

    case DioramaThemeId.transport:
      return DioramaSceneProps(boxes: [
        DioramaBoxSpec(x: -75 + 150, y: 270 + -2 * 2, w: 150, h: 2 * 2, color: theme.accent),
        DioramaBoxSpec(x: -77 + 150, y: 270 + -14 * 2, w: 50, h: 4 * 2, color: theme.trim),
        DioramaBoxSpec(x: -77 + 150, y: 270 + -28 * 2, w: 50, h: 14 * 2, color: theme.trim),
        DioramaBoxSpec(x: -50 + 150, y: 270 + -120 * 2, w: 8, h: 120 * 2, color: theme.trim),
        DioramaBoxSpec(x: 50 + 150, y: 270 + -120 * 2, w: 8, h: 120 * 2, color: theme.trim),
        DioramaBoxSpec(x: -22 + 150, y: 270 + -110 * 2, w: 44, h: 14 * 2, color: theme.accent),
        DioramaBoxSpec(x: -30 + 150, y: 270 + -80 * 2, w: 60, h: 4 * 2, color: const Color(0xFF2E323F)),
      ]);

    case DioramaThemeId.home:
      return DioramaSceneProps(boxes: [
        DioramaBoxSpec(x: -40 + 150, y: 270 + -18 * 2, w: 80, h: 18 * 2, color: theme.accent),
        DioramaBoxSpec(x: -40 + 150, y: 270 + -44 * 2, w: 80, h: 26 * 2, color: theme.accent),
        DioramaBoxSpec(x: 50 + 150, y: 270 + -60 * 2, w: 3, h: 60 * 2, color: theme.trim),
        DioramaBoxSpec(x: 45 + 150, y: 270 + -70 * 2, w: 14, h: 10 * 2, color: const Color(0xFFEDE3CC)),
        DioramaBoxSpec(x: -30 + 150, y: 270 + -100 * 2, w: 20, h: 14 * 2, color: theme.trim),
      ]);

    case DioramaThemeId.idle:
      return const DioramaSceneProps();
  }
}
