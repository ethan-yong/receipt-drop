import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// Always-on scrolling banner teaching the OS Share-menu import path
/// ("share a receipt from your bank/TNG app into Receipt Drop").
///
/// Non-dismissible by design — replaces the old one-time dismissible
/// coach-mark card. Home keeps this collapsed at the scroll top, then
/// fades it in with a slide-up from below after a short scroll.
class ShareTicker extends StatefulWidget {
  const ShareTicker({super.key, this.active = true});

  /// When false, pauses marquee/glow animations (hidden off-screen).
  final bool active;

  @override
  State<ShareTicker> createState() => _ShareTickerState();
}

class _ShareTickerState extends State<ShareTicker>
    with TickerProviderStateMixin {
  static const _tickerText =
      'RECEIPT IN YOUR BANK OR TNG APP? · TAP SHARE · CHOOSE RECEIPT DROP · DONE ·';
  static const _accent = Color(0xFFF6964B);
  static const _textColor = Color(0xFF23201A);
  static const _copyGap = 26.0;

  late final AnimationController _scrollController;
  late final AnimationController _glowController;
  TextStyle? _style;
  double? _itemWidth;

  @override
  void initState() {
    super.initState();
    _scrollController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    );
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    _syncAnimationPlayback();
  }

  @override
  void didUpdateWidget(covariant ShareTicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      _syncAnimationPlayback();
    }
  }

  void _syncAnimationPlayback() {
    if (widget.active) {
      if (!_scrollController.isAnimating) _scrollController.repeat();
      if (!_glowController.isAnimating) _glowController.repeat(reverse: true);
    } else {
      _scrollController.stop();
      _glowController.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final base = Theme.of(context).textTheme.labelSmall ?? const TextStyle();
    final style = base.copyWith(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.7,
      color: _textColor,
      height: 1,
    );
    if (_style == style) return;
    _style = style;
    final painter = TextPainter(
      text: TextSpan(text: _tickerText, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    _itemWidth = painter.width + _copyGap;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = _style;
    final itemWidth = _itemWidth;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        0,
      ),
      child: AnimatedBuilder(
        animation: _glowController,
        builder: (context, child) {
          final t = Curves.easeInOut.transform(_glowController.value);
          double lerp(double a, double b) => a + (b - a) * t;
          return DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: _accent.withValues(alpha: 0.6),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: _accent.withValues(alpha: lerp(0.3, 0.65)),
                  blurRadius: lerp(6, 16),
                ),
                const BoxShadow(
                  color: Color(0x1A231C0C),
                  offset: Offset(0, 4),
                  blurRadius: 14,
                ),
              ],
            ),
            child: child,
          );
        },
        child: SizedBox(
          height: 34,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: (style == null || itemWidth == null)
                ? const SizedBox.shrink()
                : ClipRect(
                    child: AnimatedBuilder(
                      animation: _scrollController,
                      builder: (context, _) {
                        return OverflowBox(
                          maxWidth: double.infinity,
                          alignment: Alignment.centerLeft,
                          child: Transform.translate(
                            offset: Offset(
                              -_scrollController.value * itemWidth,
                              0,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_tickerText, style: style, maxLines: 1, softWrap: false),
                                const SizedBox(width: _copyGap),
                                Text(_tickerText, style: style, maxLines: 1, softWrap: false),
                                const SizedBox(width: _copyGap),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
