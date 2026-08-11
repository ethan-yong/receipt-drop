import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../domain/logic/badge_catalog.dart';
import 'badge_icon.dart';

const _kTierColors = [
  Color(0xFFC68A4B), // Bronze
  Color(0xFF9AA3AD), // Silver
  Color(0xFFE0AA3E), // Gold
];
const _kLockedRing = Color(0xFFC9C0AC);
const _kInnerUnlocked = Color(0xFFF3ECDE);
const _kInnerLocked = Color(0xFFDEDACF);
const _kTierLabels = ['BRONZE', 'SILVER', 'GOLD'];

/// Shows all three tier hexes for one achievement inline — Bronze / Silver / Gold.
/// The "current" (next to earn) tier shows a progress bar; earned tiers are
/// coloured; locked tiers are greyed with a lock icon.
class AchievementProgressCard extends StatelessWidget {
  const AchievementProgressCard({
    super.key,
    required this.badge,
    required this.progress,
    required this.tier,
    this.onTap,
  });

  final BadgeDef badge;
  final int progress; // raw count from user_badges.progress
  final int tier; // unlocked_tier 0–3
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final effectiveTier = badge.comingSoon ? 0 : tier;
    final isMaxed = effectiveTier >= 3;

    final nextGoal = effectiveTier < badge.tierGoals.length ? badge.tierGoals[effectiveTier] : null;
    final prevGoal = effectiveTier > 0 ? badge.tierGoals[effectiveTier - 1] : 0;
    final ratio = (nextGoal != null && nextGoal > prevGoal)
        ? ((progress - prevGoal) / (nextGoal - prevGoal)).clamp(0.0, 1.0)
        : 1.0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: AppSpacing.cardBorderRadius,
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              badge.label.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: const Color(0xFF8A8375),
                  ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(3, (i) {
                final isUnlocked = !badge.comingSoon && i < tier;
                final isCurrent = !badge.comingSoon && i == tier && tier < 3;
                final isLocked = badge.comingSoon || i > tier;

                return _TierColumn(
                  badge: badge,
                  tierIndex: i,
                  isUnlocked: isUnlocked,
                  isCurrent: isCurrent,
                  isLocked: isLocked,
                  // Only the current hex shows the progress bar
                  showProgress: isCurrent && nextGoal != null,
                  progress: progress,
                  nextGoal: nextGoal ?? 0,
                  ratio: ratio,
                );
              }),
            ),
            if (isMaxed) ...[
              const SizedBox(height: 10),
              Center(
                child: Text(
                  'All tiers complete 🎉',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFFB0873E),
                      ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TierColumn extends StatelessWidget {
  const _TierColumn({
    required this.badge,
    required this.tierIndex,
    required this.isUnlocked,
    required this.isCurrent,
    required this.isLocked,
    required this.showProgress,
    required this.progress,
    required this.nextGoal,
    required this.ratio,
  });

  final BadgeDef badge;
  final int tierIndex;
  final bool isUnlocked;
  final bool isCurrent;
  final bool isLocked;
  final bool showProgress;
  final int progress;
  final int nextGoal;
  final double ratio;

  @override
  Widget build(BuildContext context) {
    final tierColor = _kTierColors[tierIndex];
    final labelColor = isLocked ? const Color(0xFFB4AC9C) : tierColor;

    return SizedBox(
      width: 64,
      child: Column(
        children: [
          _TierHex(
            badge: badge,
            tierIndex: tierIndex,
            isLocked: isLocked,
            tierColor: tierColor,
          ),
          const SizedBox(height: 6),
          Text(
            _kTierLabels[tierIndex],
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: labelColor,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                  fontSize: 10,
                ),
            textAlign: TextAlign.center,
          ),
          if (showProgress) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 6,
                backgroundColor: const Color(0xFFE9E1D0),
                valueColor: AlwaysStoppedAnimation<Color>(tierColor),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$progress / $nextGoal',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: const Color(0xFF8A8375),
                    fontSize: 10,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

class _TierHex extends StatelessWidget {
  const _TierHex({
    required this.badge,
    required this.tierIndex,
    required this.isLocked,
    required this.tierColor,
  });

  final BadgeDef badge;
  final int tierIndex;
  final bool isLocked;
  final Color tierColor;

  @override
  Widget build(BuildContext context) {
    const size = 56.0;
    const inset = 2.0;
    final ringColor = isLocked ? _kLockedRing : tierColor;
    final innerBg = isLocked ? _kInnerLocked : _kInnerUnlocked;
    final badgeColor = isLocked ? const Color(0xFF9A9384) : tierColor;
    const iconSize = size * 0.52;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipPath(
            clipper: _FlatHexClipper(),
            child: Container(color: ringColor),
          ),
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
                child: isLocked
                    ? ColorFiltered(
                        colorFilter: const ColorFilter.matrix(<double>[
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0,      0,      0,      0.6, 0,
                        ]),
                        child: badgeIconAsset(
                          badge.svgAsset,
                          width: iconSize,
                          height: iconSize,
                        ),
                      )
                    : badgeIconAsset(
                        badge.svgAsset,
                        width: iconSize,
                        height: iconSize,
                      ),
              ),
            ),
          ),
          // Tier number badge (top-left, always visible)
          Positioned(
            top: 2,
            left: 2,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: badgeColor,
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
                '${tierIndex + 1}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          // Lock icon (bottom-centre, locked only)
          if (isLocked)
            Positioned(
              bottom: 3,
              left: 0,
              right: 0,
              child: Center(
                child: SizedBox(
                  width: 12,
                  height: 10,
                  child: CustomPaint(painter: _LockPainter()),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

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
