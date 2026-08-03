import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../domain/logic/badge_catalog.dart';

// Tier ring colors from design: Bronze / Silver / Gold
const _kTierColors = [
  Color(0xFFC68A4B),
  Color(0xFF9AA3AD),
  Color(0xFFE0AA3E),
];
const _kLockedRing = Color(0xFFC9C0AC);
const _kInnerUnlocked = Color(0xFFF3ECDE);
const _kInnerLocked = Color(0xFFDEDACF);

/// Bronze / Silver / Gold ring color for a badge tier (1..3) — shared with
/// the leaderboard podium so rank medals and badge tiers use the same hues.
Color badgeTierColor(int tier) => _kTierColors[tier.clamp(1, 3) - 1];

// Flat-top hex: 25% 0%, 75% 0%, 100% 50%, 75% 100%, 25% 100%, 0% 50%
class _FlatHexClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size s) => Path()
    ..moveTo(s.width * 0.25, 0)
    ..lineTo(s.width * 0.75, 0)
    ..lineTo(s.width, s.height * 0.5)
    ..lineTo(s.width * 0.75, s.height)
    ..lineTo(s.width * 0.25, s.height)
    ..lineTo(0, s.height * 0.5)
    ..close();

  @override
  bool shouldReclip(covariant CustomClipper<Path> old) => false;
}

/// Hexagonal badge tile.
class BadgeHex extends StatelessWidget {
  const BadgeHex({
    super.key,
    required this.badge,
    required this.earned,
    this.tier = 0,
    this.size = 88,
    this.showLabel = false,
    this.showTierBadge = true,
    this.onTap,
  });

  final BadgeDef badge;
  final bool earned;
  /// 0 = locked, 1/2/3 = current tier.
  final int tier;
  final double size;
  final bool showLabel;
  /// Tier number chip — hidden on compact surfaces (e.g. leaderboard row).
  final bool showTierBadge;
  final VoidCallback? onTap;

  bool get _locked => badge.comingSoon || !earned;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHex(),
          if (showLabel) ...[
            const SizedBox(height: 4),
            Text(
              badge.label,
              style: Theme.of(context).textTheme.labelSmall,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHex() {
    final ringColor = _locked ? _kLockedRing : _kTierColors[tier.clamp(1, 3) - 1];
    final innerBg = _locked ? _kInnerLocked : _kInnerUnlocked;
    final iconSize = size * 0.54;
    const inset = 3.0;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Outer ring hex
          ClipPath(
            clipper: _FlatHexClipper(),
            child: Container(color: ringColor),
          ),
          // Inner fill hex
          Positioned(
            top: inset,
            left: inset,
            right: inset,
            bottom: inset,
            child: ClipPath(
              clipper: _FlatHexClipper(),
              child: Container(
                color: innerBg,
                alignment: Alignment.center,
                child: _locked
                    ? ColorFiltered(
                        colorFilter: const ColorFilter.matrix(<double>[
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0,      0,      0,      0.6, 0,
                        ]),
                        child: SvgPicture.asset(
                          badge.svgAsset,
                          width: iconSize,
                          height: iconSize,
                        ),
                      )
                    : SvgPicture.asset(
                        badge.svgAsset,
                        width: iconSize,
                        height: iconSize,
                      ),
              ),
            ),
          ),
          if (showTierBadge && tier > 0) _tierBadge(ringColor),
          // Lock icon (bottom-centre)
          if (_locked)
            Positioned(
              bottom: 5,
              left: 0,
              right: 0,
              child: Center(
                child: SizedBox(
                  width: 14,
                  height: 12,
                  child: CustomPaint(painter: _LockPainter()),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tierBadge(Color ringColor) {
    final tierBadgeSize = (size * 0.26).clamp(12.0, 22.0);
    final tierFontSize = (tierBadgeSize * 0.5).clamp(8.0, 11.0);
    return Positioned(
      top: 2,
      left: 2,
      child: Container(
        width: tierBadgeSize,
        height: tierBadgeSize,
        decoration: BoxDecoration(
          color: ringColor,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          '$tier',
          style: TextStyle(
            color: Colors.white,
            fontSize: tierFontSize,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _LockPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const bodyColor = Color(0xFFB9AC8E);
    final body = Paint()..color = bodyColor;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, size.height * 0.41, size.width, size.height * 0.59),
        const Radius.circular(3),
      ),
      body,
    );
    canvas.drawArc(
      Rect.fromLTWH(size.width * 0.15, 0, size.width * 0.7, size.height * 0.82),
      3.14,
      3.14,
      false,
      Paint()
        ..color = bodyColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
