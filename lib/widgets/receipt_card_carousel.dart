import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:go_router/go_router.dart';

import '../core/platform/platform_feedback.dart';
import '../core/theme/app_theme.dart';
import '../domain/models/transaction_view.dart';
import 'receipt_card.dart';
import 'receipt_carousel_physics.dart';

/// Auto-rotating, single-card receipt carousel for the home screen.
///
/// Reimplements the design handoff at
/// `handoff/# Budget App Room Backgrounds/design_handoff_home_carousel/`:
/// exactly one card is ever visible/interactive at rest (no adjacent-card
/// peeking), it crossfades+scales "through a deck" on rotation/swipe/dot-tap,
/// and the newest receipt (index 0 — the list is sorted newest-first by
/// [TransactionRepository.watchAll]) gets a gold highlight border and a
/// "Latest Spending" badge breaking its bottom edge.
///
/// Swipes use velocity-based paging: a slow drag advances one receipt, a fast
/// fling can skip several, then the carousel decelerates and spring-snaps onto
/// an integer page (see [computeTargetPage]).
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

  static const _overshootCurve = Cubic(0.34, 1.56, 0.64, 1.0);
  static const _dragExitNudge = 26.0;
  static const _dragClamp = 140.0;
  static const _dragTapTolerance = 4.0;

  /// Unbounded controller whose value is the fractional (possibly unwrapped)
  /// page offset during a fling / spring snap.
  late final AnimationController _flingController;

  /// Settled integer page index.
  int _current = 0;

  /// Live fractional page offset. Equals [_current] when idle.
  double _pageOffset = 0;

  /// +1 advancing (left swipe), −1 going back. Used while flinging.
  int _flingDirection = 1;

  double _flingStart = 0;
  double _flingEnd = 0;
  int _hapticPagesCrossed = 0;
  bool _flinging = false;

  // Live transform applied only to the resting/interacting active card
  // (press-down, drag tracking, spring-back, tap-bounce) — reset to the
  // identity once a deck-transition takes over.
  double _dx = 0, _scale = 1, _opacity = 1;
  Duration _liveDuration = Duration.zero;
  Curve _liveCurve = Curves.linear;

  double? _dragStartX;
  double _dragRawDx = 0;
  bool _dragMoved = false;
  double _viewportWidth = 300;

  Timer? _autoTimer;
  Timer? _resumeTimer;
  Timer? _tapSettleTimer;

  final GlobalKey _dotsKey = GlobalKey();
  double? _dotDragStartGlobalX;
  bool _dotDragMoved = false;
  bool _scrubbing = false;

  bool get _busy => _flinging;

  @override
  void initState() {
    super.initState();
    _flingController = AnimationController.unbounded(vsync: this)
      ..addListener(_onFlingTick)
      ..addStatusListener(_onFlingStatus);
    _startAutoRotate();
  }

  @override
  void didUpdateWidget(covariant ReceiptCardCarousel old) {
    super.didUpdateWidget(old);
    final n = widget.transactions.length;
    if (n != old.transactions.length) {
      final grew = n > old.transactions.length;
      if (grew || _current >= n) {
        _stopFling();
        setState(() {
          // A longer list means a receipt was just captured (the list is
          // sorted newest-first), so snap to it at index 0; otherwise clamp
          // after removals.
          _current = grew || n == 0 ? 0 : n - 1;
          _pageOffset = _current.toDouble();
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
    _flingController.dispose();
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
      final n = widget.transactions.length;
      _animateToPage((_current + 1) % n, haptic: false);
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

  void _stopFling() {
    if (!_flinging && !_flingController.isAnimating) return;
    _flingController.stop();
    _flinging = false;
  }

  void _onFlingTick() {
    final x = _flingController.value;
    final progress = (x - _flingStart).abs();
    final pagesCrossed = progress.floor();
    if (pagesCrossed > _hapticPagesCrossed) {
      PlatformFeedback.selectionTap();
      _hapticPagesCrossed = pagesCrossed;
    }
    setState(() => _pageOffset = x);
  }

  void _onFlingStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    final n = widget.transactions.length;
    if (n <= 0) return;
    final settled = _wrapIndex(_flingEnd.round(), n);
    setState(() {
      _flinging = false;
      _current = settled;
      _pageOffset = settled.toDouble();
      _resetLiveTransform();
    });
    _resumeAutoRotateSoon();
  }

  /// Animate from the current settled page to [target] with a spring that
  /// carries [initialVelocityPages] (positive = advance toward higher indices).
  void _animateToPage(
    int target, {
    double initialVelocityPages = 0,
    bool haptic = false,
  }) {
    final n = widget.transactions.length;
    if (n <= 1) return;

    final delta = shortestPageDelta(_current, target, n);
    if (delta == 0) {
      _springBackLiveTransform();
      _resumeAutoRotateSoon();
      return;
    }

    _pauseAutoRotate();
    _stopFling();
    if (haptic) PlatformFeedback.selectionTap();

    _flingDirection = delta > 0 ? 1 : -1;
    _flingStart = _current.toDouble();
    _flingEnd = (_current + delta).toDouble();
    _hapticPagesCrossed = 0;
    _resetLiveTransform();

    final spring = SpringDescription(
      mass: kSnapSpringMass,
      stiffness: kSnapSpringStiffness,
      damping: kSnapSpringDamping,
    );
    // Bias velocity toward the travel direction so a slow drag still lands
    // cleanly, and a fast fling overshoots slightly before settling.
    var velocity = initialVelocityPages;
    if (velocity == 0) {
      velocity = _flingDirection * 2.5;
    } else if (velocity.sign != _flingDirection && velocity != 0) {
      // Finger velocity disagreed with computed target — keep magnitude but
      // point it at the target so the spring doesn't fight itself.
      velocity = velocity.abs() * _flingDirection;
    }

    setState(() {
      _flinging = true;
      _pageOffset = _flingStart;
    });
    _flingController.animateWith(
      SpringSimulation(spring, _flingStart, _flingEnd, velocity),
    );
  }

  void _springBackLiveTransform() {
    setState(() {
      _liveDuration = const Duration(milliseconds: 300);
      _liveCurve = Curves.easeOut;
      _dx = 0;
      _scale = 1;
      _opacity = 1;
    });
  }

  void _dotJump(int target) {
    if (target == _current || _busy) {
      _pauseAutoRotate();
      _resumeAutoRotateSoon();
      return;
    }
    _animateToPage(target, haptic: true);
  }

  void _setScrubIndex(int idx) {
    if (idx == _current) return;
    _stopFling();
    PlatformFeedback.selectionTap();
    setState(() {
      _current = idx;
      _pageOffset = idx.toDouble();
      _flinging = false;
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
  // card's own items list.
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

    final velocityPx = details.velocity.pixelsPerSecond.dx;
    final n = widget.transactions.length;
    if (!_dragMoved || n <= 1) {
      _springBackLiveTransform();
      _resumeAutoRotateSoon();
      return;
    }

    final target = computeTargetPage(
      currentPage: _current.toDouble(),
      dragDeltaPx: _dragRawDx,
      velocityPxPerSec: velocityPx,
      viewportWidthPx: _viewportWidth,
      pageCount: n,
    );

    if (target == _current) {
      _springBackLiveTransform();
      _resumeAutoRotateSoon();
      return;
    }

    // Convert px/s → pages/s (left swipe / negative px → positive pages).
    final velocityPages = _viewportWidth > 0
        ? -velocityPx / _viewportWidth
        : 0.0;

    _animateToPage(
      target,
      initialVelocityPages: velocityPages,
      haptic: true,
    );
  }

  void _onDragCancel() {
    if (_dragStartX == null || _busy) return;
    _dragStartX = null;
    _springBackLiveTransform();
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

  int _wrapIndex(int index, int pageCount) {
    if (pageCount <= 0) return 0;
    return ((index % pageCount) + pageCount) % pageCount;
  }

  /// Which settled/display index should drive viewport height (gold badge).
  int get _heightIndex {
    if (!_flinging) return _current;
    final n = widget.transactions.length;
    if (n <= 0) return 0;
    final blend = pageBlendDirected(
      pageOffset: _pageOffset,
      pageCount: n,
      direction: _flingDirection,
    );
    // Prefer the incoming card once past halfway so the badge room opens
    // before the newest card fully settles.
    return blend.t >= 0.5 ? blend.to : blend.from;
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
    final activeTx = txs[_flinging
        ? _wrapIndex(
            pageBlendDirected(
              pageOffset: _pageOffset,
              pageCount: n,
              direction: _flingDirection,
            ).to,
            n,
          )
        : current];

    final heightIndex = _heightIndex.clamp(0, n - 1);
    final viewportHeight = heightIndex == 0
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
                _viewportWidth = constraints.maxWidth;
                final width = constraints.maxWidth;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _DepthBlob(visible: !_busy),
                    ..._buildVisibleCards(txs, width),
                  ],
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
            current: _dotCurrentIndex(n),
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

  int _dotCurrentIndex(int n) {
    if (!_flinging) return _current.clamp(0, n - 1);
    final blend = pageBlendDirected(
      pageOffset: _pageOffset,
      pageCount: n,
      direction: _flingDirection,
    );
    return (blend.t >= 0.5 ? blend.to : blend.from).clamp(0, n - 1);
  }

  List<Widget> _buildVisibleCards(
    List<TransactionView> txs,
    double width,
  ) {
    final n = txs.length;

    if (!_flinging) {
      final i = _current.clamp(0, n - 1);
      return [
        _buildSettledCard(i, txs[i], width),
      ];
    }

    final blend = pageBlendDirected(
      pageOffset: _pageOffset,
      pageCount: n,
      direction: _flingDirection,
    );

    if (blend.from == blend.to || blend.t < 1e-4) {
      return [
        _buildFlingCard(
          index: blend.from,
          tx: txs[blend.from],
          width: width,
          t: 0,
          role: _FlingRole.incoming,
        ),
      ];
    }

    // Outgoing underneath, incoming on top so it fades in over the deck.
    return [
      _buildFlingCard(
        index: blend.from,
        tx: txs[blend.from],
        width: width,
        t: blend.t,
        role: _FlingRole.outgoing,
      ),
      _buildFlingCard(
        index: blend.to,
        tx: txs[blend.to],
        width: width,
        t: blend.t,
        role: _FlingRole.incoming,
      ),
    ];
  }

  Widget _buildSettledCard(int i, TransactionView tx, double width) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: AnimatedSlide(
        duration: _liveDuration,
        curve: _liveCurve,
        offset: Offset(width > 0 ? _dx / width : 0, 0),
        child: AnimatedScale(
          duration: _liveDuration,
          curve: _liveCurve,
          scale: _scale,
          child: AnimatedOpacity(
            duration: _liveDuration,
            curve: _liveCurve,
            opacity: _opacity.clamp(0.0, 1.0).toDouble(),
            child: _CardVisual(
              tx: tx,
              isNewest: i == 0,
              onTap: () => _onCardTap(tx),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFlingCard({
    required int index,
    required TransactionView tx,
    required double width,
    required double t,
    required _FlingRole role,
  }) {
    final dir = _flingDirection;
    late final double dx;
    late final double scale;
    late final double opacity;

    if (role == _FlingRole.outgoing) {
      dx = dir * -_dragExitNudge * t;
      scale = lerpDouble(1.0, 0.92, t)!;
      opacity = 1.0 - t;
    } else {
      dx = dir * _dragExitNudge * (1.0 - t);
      scale = lerpDouble(0.92, 1.0, t)!;
      opacity = t;
    }

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: role == _FlingRole.outgoing,
        child: Transform.translate(
          offset: Offset(dx, 0),
          child: Transform.scale(
            scale: scale,
            child: Opacity(
              opacity: opacity.clamp(0.0, 1.0).toDouble(),
              child: _CardVisual(
                tx: tx,
                isNewest: index == 0,
                onTap: () => _onCardTap(tx),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _FlingRole { outgoing, incoming }

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
              width: 207,
              height: 347,
              decoration: BoxDecoration(
                color: const Color(0x2932280F),
                borderRadius: BorderRadius.circular(20),
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
      key: const ValueKey('receipt-carousel-dots'),
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
