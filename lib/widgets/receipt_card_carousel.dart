import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/platform/platform_feedback.dart';
import '../core/theme/app_theme.dart';
import '../domain/models/transaction_view.dart';
import 'receipt_card.dart';

/// Auto-rotating, single-card receipt carousel for the home screen.
///
/// Reimplements the design handoff at
/// `handoff/# Budget App Room Backgrounds/design_handoff_home_carousel/`:
/// exactly one card is ever visible/interactive at rest (no adjacent-card
/// peeking), it crossfades+scales "through a deck" on rotation/swipe/dot-tap,
/// and the newest receipt (index 0 — the list is sorted newest-first by
/// [TransactionRepository.watchAll]) gets a gold highlight border and a
/// "Latest Spending" badge breaking its bottom edge.
class ReceiptCardCarousel extends StatefulWidget {
  const ReceiptCardCarousel({super.key, required this.transactions});

  final List<TransactionView> transactions;

  @override
  State<ReceiptCardCarousel> createState() => _ReceiptCardCarouselState();
}

class _ReceiptCardCarouselState extends State<ReceiptCardCarousel>
    with TickerProviderStateMixin {
  // Card height plus the newest-card gold frame (5px per side), plus room for
  // the "Latest Spending" pill (Positioned bottom: -16) and its shadow so it
  // does not paint over the Drop Receipt CTA below the carousel.
  static const _latestSpendingBadgeOverflow = 32.0;
  static const _rotateInterval = Duration(seconds: 5);
  static const _resumeDelay = Duration(milliseconds: 400);
  static const _dotChainDelay = Duration(milliseconds: 700);

  static const _transformDuration = Duration(milliseconds: 680);
  static const _opacityDuration = Duration(milliseconds: 600);
  static const _transformCurve = Cubic(0.22, 0.9, 0.3, 1.0);
  static const _overshootCurve = Cubic(0.34, 1.56, 0.64, 1.0);
  static const _dragExitNudge = 26.0;
  static const _dragClamp = 140.0;
  static const _dragCommitThreshold = 56.0;
  static const _dragTapTolerance = 4.0;

  late final AnimationController _transitionController;

  int _current = 0;
  int? _previous;
  int _direction = 1;
  double _outDx = 0, _outScale = 1, _outOpacity = 1;

  // Live transform applied only to the resting/interacting active card
  // (press-down, drag tracking, spring-back, tap-bounce) — reset to the
  // identity once a deck-transition takes over.
  double _dx = 0, _scale = 1, _opacity = 1;
  Duration _liveDuration = Duration.zero;
  Curve _liveCurve = Curves.linear;

  double? _dragStartX;
  double _dragRawDx = 0;
  bool _dragMoved = false;

  Timer? _autoTimer;
  Timer? _resumeTimer;
  Timer? _tapSettleTimer;
  Timer? _dotChainTimer;

  final GlobalKey _dotsKey = GlobalKey();
  double? _dotDragStartGlobalX;
  bool _dotDragMoved = false;
  bool _scrubbing = false;

  bool get _busy => _previous != null;

  @override
  void initState() {
    super.initState();
    _transitionController =
        AnimationController(vsync: this, duration: _transformDuration)
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) {
              setState(() => _previous = null);
            }
          });
    _startAutoRotate();
  }

  @override
  void didUpdateWidget(covariant ReceiptCardCarousel old) {
    super.didUpdateWidget(old);
    final n = widget.transactions.length;
    if (n != old.transactions.length) {
      final grew = n > old.transactions.length;
      if (grew || _current >= n) {
        _transitionController.stop();
        setState(() {
          // A longer list means a receipt was just captured (the list is
          // sorted newest-first), so snap to it at index 0; otherwise clamp
          // after removals.
          _current = grew || n == 0 ? 0 : n - 1;
          _previous = null;
          _resetLiveTransform();
        });
      }
      _startAutoRotate();
    }
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _resumeTimer?.cancel();
    _tapSettleTimer?.cancel();
    _dotChainTimer?.cancel();
    _transitionController.dispose();
    super.dispose();
  }

  void _resetLiveTransform() {
    _dx = 0;
    _scale = 1;
    _opacity = 1;
    _liveDuration = Duration.zero;
    _liveCurve = Curves.linear;
  }

  void _startAutoRotate() {
    _autoTimer?.cancel();
    if (widget.transactions.length <= 1) return;
    _autoTimer = Timer.periodic(_rotateInterval, (_) {
      if (_dragStartX != null || _busy) return;
      _commit(1);
    });
  }

  void _pauseAutoRotate() {
    _autoTimer?.cancel();
    _resumeTimer?.cancel();
  }

  void _resumeAutoRotateSoon() {
    _resumeTimer?.cancel();
    _resumeTimer = Timer(_resumeDelay, _startAutoRotate);
  }

  void _commit(int dir, {bool haptic = false}) {
    final n = widget.transactions.length;
    if (_busy || n <= 1) return;
    final from = _current;
    final to = ((_current + dir) % n + n) % n;
    if (haptic) PlatformFeedback.selectionTap();
    setState(() {
      _previous = from;
      _current = to;
      _direction = dir;
      _outDx = _dx;
      _outScale = _scale;
      _outOpacity = _opacity;
      _resetLiveTransform();
    });
    _transitionController.forward(from: 0);
  }

  void _dotJump(int target) {
    final n = widget.transactions.length;
    if (target == _current || _busy) {
      _pauseAutoRotate();
      _resumeAutoRotateSoon();
      return;
    }
    _pauseAutoRotate();
    var diff = target - _current;
    if (diff > n / 2) diff -= n;
    if (diff < -n / 2) diff += n;
    final dir = diff > 0 ? 1 : -1;
    var remaining = diff.abs() - 1;
    _commit(dir);
    _dotChainTimer?.cancel();
    void chain() {
      if (remaining <= 0) {
        _resumeAutoRotateSoon();
        return;
      }
      remaining--;
      _dotChainTimer = Timer(_dotChainDelay, () {
        _commit(dir);
        chain();
      });
    }

    if (remaining > 0) {
      chain();
    } else {
      _resumeAutoRotateSoon();
    }
  }

  void _setScrubIndex(int idx) {
    if (idx == _current) return;
    _transitionController.stop();
    // Subtle tick each time the scrubber lands on a new card — matches
    // iOS-style picker feedback; not a continuous buzz.
    PlatformFeedback.selectionTap();
    setState(() {
      _previous = null;
      _current = idx;
      _resetLiveTransform();
    });
  }

  int _globalXToDotIndex(double globalX) {
    final rb = _dotsKey.currentContext?.findRenderObject() as RenderBox?;
    if (rb == null) return _current;
    final localX = rb.globalToLocal(Offset(globalX, 0)).dx;
    final n = widget.transactions.length;
    return (localX / rb.size.width * n).floor().clamp(0, n - 1);
  }

  void _onDotPanStart(DragStartDetails d) {
    _dotDragStartGlobalX = d.globalPosition.dx;
    _dotDragMoved = false;
    _pauseAutoRotate();
  }

  void _onDotPanUpdate(DragUpdateDetails d) {
    final start = _dotDragStartGlobalX;
    if (start == null) return;
    if (!_dotDragMoved &&
        (d.globalPosition.dx - start).abs() > _dragTapTolerance) {
      _dotDragMoved = true;
      // One-shot enter: medium haptic + pill chrome. Per-card ticks fire
      // from [_setScrubIndex] as the finger crosses dots.
      if (!_scrubbing) {
        setState(() => _scrubbing = true);
        PlatformFeedback.mediumTap();
      }
    }
    if (_dotDragMoved) _setScrubIndex(_globalXToDotIndex(d.globalPosition.dx));
  }

  void _onDotPanEnd(DragEndDetails _) {
    _endDotGesture();
  }

  void _onDotPanCancel() {
    _endDotGesture();
  }

  void _endDotGesture() {
    final start = _dotDragStartGlobalX;
    final wasTap = !_dotDragMoved && start != null;
    if (wasTap) {
      _dotJump(_globalXToDotIndex(start));
    }
    _dotDragStartGlobalX = null;
    _dotDragMoved = false;
    if (_scrubbing) {
      setState(() => _scrubbing = false);
    }
    _resumeAutoRotateSoon();
  }

  void _openDetail(TransactionView tx) {
    context.pushNamed(
      'tx-detail',
      pathParameters: {'id': tx.id},
      queryParameters: const {'edit': '1'},
    );
  }

  // Only bookkeeping here — no visual change yet. Flutter calls this the
  // instant a finger touches the card, before the gesture arena has decided
  // whether it's a horizontal swipe, a tap, or a vertical scroll inside the
  // card's own items list. Applying the press-down scale here would flash it
  // on every scroll attempt too (see _onDragCancel below).
  void _onDragDown(DragDownDetails details) {
    if (_busy) return;
    _pauseAutoRotate();
    _dragStartX = details.globalPosition.dx;
    _dragRawDx = 0;
    _dragMoved = false;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final startX = _dragStartX;
    if (startX == null || _busy) return;
    _dragRawDx = details.globalPosition.dx - startX;
    final justConfirmed = !_dragMoved && _dragRawDx.abs() > _dragTapTolerance;
    if (justConfirmed) _dragMoved = true;
    if (!_dragMoved) return;
    final clamped = _dragRawDx.clamp(-_dragClamp, _dragClamp).toDouble();
    final scale =
        1 - (clamped.abs() / _dragClamp).clamp(0.0, 1.0).toDouble() * 0.08;
    final fade =
        1 - (clamped.abs() / (_dragClamp * 2)).clamp(0.0, 1.0).toDouble() * 0.3;
    setState(() {
      // Ease into the press-down feel on the first confirmed-horizontal
      // frame (now that we know this isn't a vertical scroll); track the
      // finger 1:1 with no animation on every frame after.
      _liveDuration = justConfirmed
          ? const Duration(milliseconds: 100)
          : Duration.zero;
      _liveCurve = justConfirmed ? Curves.easeInOut : Curves.linear;
      _dx = clamped * 0.6;
      _scale = scale;
      _opacity = fade;
    });
  }

  void _onDragEnd(DragEndDetails details) {
    if (_dragStartX == null || _busy) return;
    _dragStartX = null;

    if (_dragMoved && _dragRawDx.abs() > _dragCommitThreshold) {
      _commit(_dragRawDx < 0 ? 1 : -1, haptic: true);
    } else {
      setState(() {
        _liveDuration = const Duration(milliseconds: 300);
        _liveCurve = Curves.easeOut;
        _dx = 0;
        _scale = 1;
        _opacity = 1;
      });
    }
    _resumeAutoRotateSoon();
  }

  // Fires when the horizontal-drag recognizer loses the arena — to the
  // card's inner items scroller, the page's vertical scroll, or the tap
  // recognizer. _onCardTap nulls _dragStartX first, so the tap path skips
  // the spring-back here and keeps its bounce.
  void _onDragCancel() {
    if (_dragStartX == null || _busy) return;
    _dragStartX = null;
    setState(() {
      _liveDuration = const Duration(milliseconds: 300);
      _liveCurve = Curves.easeOut;
      _dx = 0;
      _scale = 1;
      _opacity = 1;
    });
    _resumeAutoRotateSoon();
  }

  /// Haptic-style bounce, then open the receipt. Wired both to the viewport
  /// tap recognizer and (via [ReceiptCard.onTap]) to the item rows inside
  /// the card's scroller, which would otherwise swallow taps.
  void _onCardTap(TransactionView tx) {
    if (_busy) return;
    _dragStartX = null;
    _pauseAutoRotate();
    setState(() {
      _liveDuration = const Duration(milliseconds: 160);
      _liveCurve = _overshootCurve;
      _dx = 0;
      _opacity = 1;
      _scale = 1.02;
    });
    _tapSettleTimer?.cancel();
    _tapSettleTimer = Timer(const Duration(milliseconds: 130), () {
      if (!mounted) return;
      setState(() {
        _liveDuration = const Duration(milliseconds: 180);
        _liveCurve = Curves.easeOut;
        _scale = 1;
      });
    });
    _openDetail(tx);
    _resumeAutoRotateSoon();
  }

  @override
  Widget build(BuildContext context) {
    final txs = widget.transactions;

    if (txs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Center(
          child: Text(
            'No receipts today yet',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
          ),
        ),
      );
    }

    final n = txs.length;
    final current = _current < n ? _current : n - 1;
    final activeTx = txs[current];
    // Newest receipt (index 0) needs room for the gold frame (+10) and the
    // hanging "Latest Spending" badge; other cards are plain card height.
    final viewportHeight = current == 0
        ? kReceiptCardHeight + 10 + _latestSpendingBadgeOverflow
        : kReceiptCardHeight;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: viewportHeight,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // Horizontal-only recognizers (the handlers only ever use dx) so
            // vertical drags reach the items scroller inside the card and
            // the page's own scroll view.
            onHorizontalDragDown: n > 1 ? _onDragDown : null,
            onHorizontalDragUpdate: n > 1 ? _onDragUpdate : null,
            onHorizontalDragEnd: n > 1 ? _onDragEnd : null,
            onHorizontalDragCancel: n > 1 ? _onDragCancel : null,
            onTap: () => _onCardTap(activeTx),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                return AnimatedBuilder(
                  animation: _transitionController,
                  builder: (context, _) {
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        _DepthBlob(visible: !_busy),
                        for (var i = 0; i < n; i++)
                          if (i == current || i == _previous)
                            _buildCard(i, current, txs[i], width),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ),
        if (n > 1) ...[
          const SizedBox(height: 4),
          _DotIndicator(
            key: _dotsKey,
            count: n,
            current: current,
            scrubbing: _scrubbing,
            palettes: txs
                .map((t) => receiptPaletteForCategory(t.effectiveCategory))
                .toList(),
            onPanStart: _onDotPanStart,
            onPanUpdate: _onDotPanUpdate,
            onPanEnd: _onDotPanEnd,
            onPanCancel: _onDotPanCancel,
          ),
        ],
      ],
    );
  }

  Widget _buildCard(int i, int current, TransactionView tx, double width) {
    final isCurrent = i == current;
    final isPrevious = i == _previous;

    double dx, scale, opacity;
    bool interactive;
    Duration duration;
    Curve curve;

    if (_busy && (isCurrent || isPrevious)) {
      final transformT = _transformCurve.transform(_transitionController.value);
      final opacityRaw =
          (_transitionController.value *
                  _transformDuration.inMilliseconds /
                  _opacityDuration.inMilliseconds)
              .clamp(0.0, 1.0)
              .toDouble();
      final opacityT = Curves.easeOut.transform(opacityRaw);
      if (isPrevious) {
        dx = lerpDouble(_outDx, _direction * -_dragExitNudge, transformT)!;
        scale = lerpDouble(_outScale, 0.92, transformT)!;
        opacity = lerpDouble(_outOpacity, 0.0, opacityT)!;
      } else {
        dx = lerpDouble(_direction * _dragExitNudge, 0, transformT)!;
        scale = lerpDouble(0.92, 1.0, transformT)!;
        opacity = lerpDouble(0.0, 1.0, opacityT)!;
      }
      interactive = false;
      duration = Duration.zero;
      curve = Curves.linear;
    } else if (isCurrent) {
      dx = _dx;
      scale = _scale;
      opacity = _opacity;
      interactive = true;
      duration = _liveDuration;
      curve = _liveCurve;
    } else {
      dx = 0;
      scale = 0.92;
      opacity = 0;
      interactive = false;
      duration = Duration.zero;
      curve = Curves.linear;
    }

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: !interactive,
        child: AnimatedSlide(
          duration: duration,
          curve: curve,
          offset: Offset(width > 0 ? dx / width : 0, 0),
          child: AnimatedScale(
            duration: duration,
            curve: curve,
            scale: scale,
            child: AnimatedOpacity(
              duration: duration,
              curve: curve,
              opacity: opacity.clamp(0.0, 1.0).toDouble(),
              child: _CardVisual(
                tx: tx,
                isNewest: i == 0,
                onTap: () => _onCardTap(tx),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DepthBlob extends StatelessWidget {
  const _DepthBlob({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 16,
      left: 0,
      right: 0,
      child: Center(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: visible ? 1 : 0,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              width: 230,
              height: 386,
              decoration: BoxDecoration(
                color: const Color(0x2932280F),
                borderRadius: BorderRadius.circular(22),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A single card at rest — [ReceiptCard]'s existing content, unchanged,
/// wrapped in the newest-receipt gold border + "Latest Spending" badge when
/// [isNewest].
class _CardVisual extends StatelessWidget {
  const _CardVisual({
    required this.tx,
    required this.isNewest,
    required this.onTap,
  });

  final TransactionView tx;
  final bool isNewest;
  final VoidCallback onTap;

  static const _gold = Color(0xFFF6C64B);
  static const _borderWidth = 5.0;

  @override
  Widget build(BuildContext context) {
    final card = ReceiptCard(
      tx: tx,
      onTap: onTap,
      margin: EdgeInsets.zero,
    );
    if (!isNewest) return card;

    // Solid gold padding reads as a crisp frame; Border.all on DecoratedBox
    // was easy to lose against the page background (only the shadow showed).
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          decoration: BoxDecoration(
            color: _gold,
            borderRadius: BorderRadius.circular(
              kReceiptCardBorderRadius + _borderWidth,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x40DCAA28),
                blurRadius: 12,
                offset: Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.all(_borderWidth),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(kReceiptCardBorderRadius),
            child: card,
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: -16,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
              decoration: BoxDecoration(
                color: _gold,
                borderRadius: BorderRadius.circular(999),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x66DCAA28),
                    blurRadius: 14,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: const Text(
                '✨ Latest Spending',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF23201A),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DotIndicator extends StatelessWidget {
  const _DotIndicator({
    super.key,
    required this.count,
    required this.current,
    required this.scrubbing,
    required this.palettes,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
    required this.onPanCancel,
  });

  final int count;
  final int current;
  final bool scrubbing;
  final List<ReceiptCardPalette> palettes;
  final GestureDragStartCallback onPanStart;
  final GestureDragUpdateCallback onPanUpdate;
  final GestureDragEndCallback onPanEnd;
  final VoidCallback onPanCancel;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: onPanStart,
      onPanUpdate: onPanUpdate,
      onPanEnd: onPanEnd,
      onPanCancel: onPanCancel,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: EdgeInsets.symmetric(
          horizontal: scrubbing ? 12 : 0,
          vertical: scrubbing ? 6 : 0,
        ),
        decoration: BoxDecoration(
          color: scrubbing
              ? AppColors.cardSurface.withValues(alpha: 0.92)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: scrubbing ? AppColors.divider : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: List.generate(count, (i) {
            final isActive = i == current;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                width: isActive ? 22 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isActive ? palettes[i].acc : AppColors.divider,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
