import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/receipt_sheet_theme.dart';

/// Base fill color for shimmer placeholders, keyed to whichever screen
/// palette they sit on.
enum SkeletonPalette {
  app(base: AppColors.divider),
  receiptSheet(base: ReceiptSheetColors.tile);

  const SkeletonPalette({required this.base});

  final Color base;
}

class _SkeletonScope extends InheritedWidget {
  const _SkeletonScope({required this.base, required super.child});

  final Color base;

  static _SkeletonScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SkeletonScope>();

  @override
  bool updateShouldNotify(_SkeletonScope oldWidget) => oldWidget.base != base;
}

/// Wraps a subtree of [SkeletonBox]/[SkeletonCircle] placeholders and drives
/// one shared shimmer sweep across all of them.
class Skeleton extends StatefulWidget {
  const Skeleton({
    super.key,
    required this.child,
    this.palette = SkeletonPalette.app,
  });

  final Widget child;
  final SkeletonPalette palette;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmerController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.palette.base;
    return _SkeletonScope(
      base: base,
      child: AnimatedBuilder(
        animation: _shimmerController,
        builder: (context, child) {
          return ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (bounds) {
              final dx = -1.5 + 3.0 * _shimmerController.value;
              return LinearGradient(
                colors: [base, Colors.white, base],
                stops: const [0.4, 0.5, 0.6],
                begin: Alignment(dx - 0.3, 0),
                end: Alignment(dx + 0.3, 0),
              ).createShader(bounds);
            },
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}

/// Rounded-rect placeholder bar. [color] overrides the ambient [Skeleton]
/// palette — normally left unset so it inherits from the enclosing scope.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 14,
    this.radius = 6,
    this.color,
  });

  final double? width;
  final double height;
  final double radius;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color ?? _SkeletonScope.of(context)?.base ?? AppColors.divider,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Circular placeholder, for avatar/blob-avatar/thumbnail circles.
class SkeletonCircle extends StatelessWidget {
  const SkeletonCircle({super.key, required this.size, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color ?? _SkeletonScope.of(context)?.base ?? AppColors.divider,
        shape: BoxShape.circle,
      ),
    );
  }
}
