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

/// Continuously-scrolling, momentum-driven receipt carousel for the home
/// screen, styled after the Pokémon TCG Pocket card browser: the whole deck
/// tracks the finger 1:1 while dragging (neighbor receipts always peeking in
/// on either side), and the newest receipt (index 0 — the list is sorted
/// newest-first by [TransactionRepository.watchAll]) gets a gold highlight
/// border and a "Latest Spending" badge breaking its bottom edge whenever
/// it's centered.
///
/// Settling is intentionally split in two: a real drag release decelerates
/// naturally via friction, then a slightly-overdamped spring snaps it onto
/// the nearest receipt with no bounce/overshoot (swipe velocity determines
/// how many receipts a hard flick carries past — see
/// [receipt_carousel_physics.dart] for the offset, windowing, and
/// friction/spring handoff math). Programmatic transitions with no real
/// gesture velocity (auto-rotate, dot-tap, tap-to-recenter a peeking card)
/// use a plain eased tween instead of that spring — see [_animateToIndex] —
/// so bounce stays exclusive to genuine flicks.
class ReceiptCardCarousel extends StatefulWidget {
  const ReceiptCardCarousel({super.key, required this.transactions});

  final List<TransactionView> transactions;

  @override
  State<ReceiptCardCarousel> createState() => _ReceiptCardCarouselState();
}

enum _MomentumPhase { idle, friction, settling }

class _ReceiptCardCarouselState extends State<ReceiptCardCarousel>
    with TickerProviderStateMixin {
  // Card height plus the newest-card gold frame (5px per side), plus room for
  // the "Latest Spending" pill (Positioned bottom: -16) and its shadow so it
  // does not paint over the Drop Receipt CTA below the carousel.
  static const _latestSpendingBadgeOverflow = 32.0;
  static const _rotateInterval = Duration(seconds: 5);
  static const _resumeDelay = Duration(milliseconds: 400);
  static const _dragTapTolerance = 4.0;

  /// Unbounded controller whose value IS the live, continuous page offset —
  /// the single source of truth read by drag updates, the friction/spring
  /// simulations, and every renderer. Assigning `.value` while a simulation
  /// is animating implicitly stops it, which is what lets a new touch grab
  /// the deck mid-flight for free.
  late final AnimationController _controller;

  _MomentumPhase _momentumPhase = _MomentumPhase.idle;
  bool get _busy => _momentumPhase != _MomentumPhase.idle;

  /// Where the current friction/spring gesture started, for the travel cap.
  double _momentumStartOffset = 0;

  /// Last integer page floor we fired a haptic tick for.
  double _lastHapticFloor = 0;

  /// Rounded-nearest real (wrapped) transaction index. Only notifies when
  /// the value actually changes, so its listeners (dots, badge height)
  /// don't rebuild on every animation tick.
  late final ValueNotifier<int> _activeIndexNotifier;

  double? _dragStartGlobalX;
  double? _lastDragGlobalX;
  bool _dragMoved = false;
  double _viewportWidth = 300;

  Timer? _autoTimer;
  Timer? _resumeTimer;

  final GlobalKey _dotsKey = GlobalKey();
  double? _dotDragStartGlobalX;
  bool _dotDragMoved = false;
  bool _scrubbing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController.unbounded(vsync: this)
      ..addListener(_onControllerChanged)
      ..addStatusListener(_onControllerStatus);
    _activeIndexNotifier = ValueNotifier(0);
    _startAutoRotate();
  }

  @override
  void didUpdateWidget(covariant ReceiptCardCarousel old) {
    super.didUpdateWidget(old);
    final n = widget.transactions.length;
    if (n != old.transactions.length) {
      final grew = n > old.transactions.length;
      final currentReal = nearestRealIndex(
        _controller.value,
        old.transactions.length,
      );
      if (grew || currentReal >= n) {
        // A longer list means a receipt was just captured (the list is
        // sorted newest-first), so snap to it at index 0; otherwise clamp
        // after removals.
        _momentumPhase = _MomentumPhase.idle;
        final settled = grew || n == 0 ? 0 : n - 1;
        _controller.value = settled.toDouble();
        _activeIndexNotifier.value = settled;
      }
      _startAutoRotate();
    }
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _resumeTimer?.cancel();
    _controller.dispose();
    _activeIndexNotifier.dispose();
    super.dispose();
  }

  void _startAutoRotate() {
    _autoTimer?.cancel();
    if (widget.transactions.length <= 1) return;
    _autoTimer = Timer.periodic(_rotateInterval, (_) {
      if (_dragStartGlobalX != null || _busy) return;
      final n = widget.transactions.length;
      final currentReal = nearestRealIndex(_controller.value, n);
      _animateToIndex((currentReal + 1) % n, haptic: false);
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

  void _maybeHaptic() {
    final floor = _controller.value.floorToDouble();
    if (floor != _lastHapticFloor) {
      PlatformFeedback.selectionTap();
      _lastHapticFloor = floor;
    }
  }

  /// Fires on every tick of the friction/spring simulations AND on every
  /// direct `.value` write (drag updates, scrub, jumps) — the single place
  /// that keeps [_activeIndexNotifier] and the friction→spring handoff in
  /// sync with the live offset. No `setState` here: the card stack listens
  /// to [_controller] directly via [AnimatedBuilder].
  void _onControllerChanged() {
    final n = widget.transactions.length;
    if (n <= 0) return;

    if (_momentumPhase == _MomentumPhase.friction) {
      // Capture velocity before anything below could mutate `.value` (a
      // direct write stops the running simulation, which would zero out a
      // later read of `_controller.velocity`).
      final v = _controller.velocity;
      if (frictionShouldHandoffToSpring(
        velocityPagesPerSec: v,
        offset: _controller.value,
        flingStart: _momentumStartOffset,
      )) {
        _startSpringPhase(v);
      }
    }

    _maybeHaptic();
    final idx = nearestRealIndex(_controller.value, n);
    if (idx != _activeIndexNotifier.value) _activeIndexNotifier.value = idx;
  }

  void _onControllerStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    final n = widget.transactions.length;
    if (n <= 0) return;
    final settled = wrapIndex(roundToNearestPage(_controller.value), n);
    // Set phase before mutating `.value` so the reentrant change-notify this
    // triggers doesn't re-enter the (now-stale) friction handoff check.
    _momentumPhase = _MomentumPhase.idle;
    _controller.value = settled.toDouble();
    _activeIndexNotifier.value = settled;
    _resumeAutoRotateSoon();
  }

  /// Starts post-release momentum: a [FrictionSimulation] glide that hands
  /// off to a centering [SpringSimulation] once it decays (or hits the
  /// travel cap) — see [_onControllerChanged]. Zero/near-zero velocity
  /// degenerates straight into the settle spring.
  void _startMomentum(double velocityPagesPerSec) {
    _pauseAutoRotate();
    _momentumStartOffset = _controller.value;
    if (frictionShouldHandoffToSpring(
      velocityPagesPerSec: velocityPagesPerSec,
      offset: _momentumStartOffset,
      flingStart: _momentumStartOffset,
    )) {
      _startSpringPhase(velocityPagesPerSec);
      return;
    }
    _momentumPhase = _MomentumPhase.friction;
    _controller.animateWith(
      FrictionSimulation(
        kFrictionDrag,
        _momentumStartOffset,
        velocityPagesPerSec,
      ),
    );
  }

  void _startSpringPhase(double velocityPagesPerSec) {
    _momentumPhase = _MomentumPhase.settling;
    final start = _controller.value;
    final target = roundToNearestPage(start).toDouble();
    final spring = SpringDescription(
      mass: kSnapSpringMass,
      stiffness: kSnapSpringStiffness,
      damping: kSnapSpringDamping,
    );
    _controller.animateWith(
      SpringSimulation(spring, start, target, velocityPagesPerSec),
    );
  }

  /// Duration/curve for a programmatic jump — see [_animateToIndex].
  static const _jumpDuration = Duration(milliseconds: 420);
  static const _jumpCurve = Curves.easeOutCubic;

  /// Smooth eased jump to [targetIndex] — no real gesture velocity involved
  /// (auto-rotate, dot-tap, tap-to-recenter a peeking card), so this is a
  /// plain curved tween rather than a physics spring: there's no gesture
  /// momentum to stay continuous with, and a tween can't overshoot, keeping
  /// "bounce" exclusive to real flick releases (see [_startSpringPhase]).
  void _animateToIndex(int targetIndex, {bool haptic = false}) {
    final n = widget.transactions.length;
    if (n <= 1) return;
    final currentRounded = roundToNearestPage(_controller.value);
    final currentReal = wrapIndex(currentRounded, n);
    final delta = shortestPageDelta(currentReal, targetIndex, n);
    if (delta == 0) {
      _resumeAutoRotateSoon();
      return;
    }

    _pauseAutoRotate();
    if (haptic) PlatformFeedback.selectionTap();

    final start = currentRounded.toDouble();
    _momentumPhase = _MomentumPhase.settling;
    _controller.value = start; // rebase onto the nearest integer before jumping
    _controller.animateTo(start + delta, duration: _jumpDuration, curve: _jumpCurve);
  }

  void _dotJump(int target) {
    final n = widget.transactions.length;
    final currentReal = nearestRealIndex(_controller.value, n);
    if (target == currentReal || _busy) {
      _pauseAutoRotate();
      _resumeAutoRotateSoon();
      return;
    }
    _animateToIndex(target, haptic: true);
  }

  void _setScrubIndex(int idx) {
    final n = widget.transactions.length;
    final currentReal = nearestRealIndex(_controller.value, n);
    if (idx == currentReal) return;
    _momentumPhase = _MomentumPhase.idle;
    _controller.value = idx.toDouble();
  }

  int _globalXToDotIndex(double globalX) {
    final rb = _dotsKey.currentContext?.findRenderObject() as RenderBox?;
    if (rb == null) return nearestRealIndex(_controller.value, widget.transactions.length);
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

  /// Tapping the centered card opens its detail; tapping a peeking neighbor
  /// spring-recenters it instead. Ignored mid-hard-flick so it doesn't fight
  /// the gesture.
  void _onCardTap(int index, TransactionView tx) {
    if (_momentumPhase == _MomentumPhase.friction) return;
    _pauseAutoRotate();
    if (index == _activeIndexNotifier.value) {
      _openDetail(tx);
    } else {
      _animateToIndex(index, haptic: true);
    }
    _resumeAutoRotateSoon();
  }

  // Only bookkeeping here — no visual change yet. Flutter calls this the
  // instant a finger touches the card, before the gesture arena has decided
  // whether it's a horizontal swipe, a tap, or a vertical scroll inside the
  // card's own items list.
  void _onDragDown(DragDownDetails details) {
    _pauseAutoRotate();
    _dragStartGlobalX = details.globalPosition.dx;
    _lastDragGlobalX = details.globalPosition.dx;
    _dragMoved = false;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final startX = _dragStartGlobalX;
    final lastX = _lastDragGlobalX;
    if (startX == null || lastX == null) return;
    final frameDx = details.globalPosition.dx - lastX;
    _lastDragGlobalX = details.globalPosition.dx;
    if (!_dragMoved && (details.globalPosition.dx - startX).abs() > _dragTapTolerance) {
      _dragMoved = true;
    }
    if (!_dragMoved) return;
    // A real drag always takes over immediately, even mid-momentum — this
    // direct `.value` write implicitly stops whatever simulation is running.
    _momentumPhase = _MomentumPhase.idle;
    _controller.value += pxDeltaToPages(
      deltaPx: frameDx,
      viewportWidth: _viewportWidth,
    );
  }

  void _onDragEnd(DragEndDetails details) {
    final startX = _dragStartGlobalX;
    if (startX == null) return;
    _dragStartGlobalX = null;
    _lastDragGlobalX = null;

    if (!_dragMoved) {
      _startMomentum(0);
      return;
    }

    final velocityPages = pxVelocityToPagesPerSecond(
      velocityPxPerSec: details.velocity.pixelsPerSecond.dx,
      viewportWidth: _viewportWidth,
    );
    _startMomentum(velocityPages);
  }

  void _onDragCancel() {
    if (_dragStartGlobalX == null) return;
    _dragStartGlobalX = null;
    _lastDragGlobalX = null;
    _startMomentum(0);
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ValueListenableBuilder<int>(
          valueListenable: _activeIndexNotifier,
          builder: (context, activeIndex, child) {
            final viewportHeight = activeIndex == 0
                ? kReceiptCardHeight + 10 + _latestSpendingBadgeOverflow
                : kReceiptCardHeight;
            return SizedBox(height: viewportHeight, child: child);
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // Horizontal-only recognizers (the handlers only ever use dx) so
            // vertical drags reach the items scroller inside the card and
            // the page's own scroll view. Tap handling lives per-card below.
            onHorizontalDragDown: n > 1 ? _onDragDown : null,
            onHorizontalDragUpdate: n > 1 ? _onDragUpdate : null,
            onHorizontalDragEnd: n > 1 ? _onDragEnd : null,
            onHorizontalDragCancel: n > 1 ? _onDragCancel : null,
            child: LayoutBuilder(
              builder: (context, constraints) {
                _viewportWidth = constraints.maxWidth;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _DepthBlob(visible: !_busy),
                    _buildCardStack(txs, constraints.maxWidth),
                  ],
                );
              },
            ),
          ),
        ),
        if (n > 1) ...[
          const SizedBox(height: 4),
          ValueListenableBuilder<int>(
            valueListenable: _activeIndexNotifier,
            builder: (context, activeIndex, _) => _DotIndicator(
              key: _dotsKey,
              count: n,
              current: activeIndex.clamp(0, n - 1),
              scrubbing: _scrubbing,
              palettes: txs
                  .map((t) => receiptPaletteForCategory(t.effectiveCategory))
                  .toList(),
              onPanStart: _onDotPanStart,
              onPanUpdate: _onDotPanUpdate,
              onPanEnd: _onDotPanEnd,
              onPanCancel: _onDotPanCancel,
            ),
          ),
        ],
      ],
    );
  }

  /// The continuously-driven card deck. Scoped to its own [AnimatedBuilder]
  /// listening to [_controller] directly (no `setState`) so a 60-120Hz drag
  /// or simulation tick only rebuilds this small subtree, not the whole
  /// carousel.
  Widget _buildCardStack(List<TransactionView> txs, double width) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final n = txs.length;
        final slots = visibleSlots(offset: _controller.value, pageCount: n);
        final ordered = [...slots]
          ..sort((a, b) => b.delta.abs().compareTo(a.delta.abs()));
        final activeIndex = nearestRealIndex(_controller.value, n);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            for (final slot in ordered)
              _buildPeekCard(
                slot,
                txs[slot.index],
                width,
                isActive: slot.index == activeIndex,
              ),
          ],
        );
      },
    );
  }

  Widget _buildPeekCard(
    CarouselSlot slot,
    TransactionView tx,
    double width, {
    required bool isActive,
  }) {
    final transform = cardTransformForDelta(
      delta: slot.delta,
      cardExtentPx: cardExtentPx(width),
    );
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Transform.translate(
        offset: Offset(transform.dx, 0),
        child: Transform.scale(
          scale: transform.scale,
          child: Opacity(
            opacity: transform.opacity.clamp(0.0, 1.0),
            child: Center(
              child: SizedBox(
                // Keyed here (not on the ancestor `Positioned`, which always
                // spans the full `left:0, right:0` width regardless of this
                // card's actual transformed/scaled position) so tests can
                // find the centered card's true on-screen bounds.
                key: isActive
                    ? ValueKey('receipt-carousel-active-${slot.index}')
                    : null,
                width: cardSlotWidth(width),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _onCardTap(slot.index, tx),
                  child: _CardVisual(
                    tx: tx,
                    // Gated on `isActive`, not just index 0: the badge's
                    // bottom-edge overflow only has reserved room when its
                    // card is centered (see the viewportHeight calc above),
                    // so showing it on a merely-peeking neighbor would let
                    // it bleed into the CTA button below.
                    isNewest: slot.index == 0 && isActive,
                    onTap: () => _onCardTap(slot.index, tx),
                  ),
                ),
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
