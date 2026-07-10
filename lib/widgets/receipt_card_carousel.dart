import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
  static const _viewportHeight = 480.0;
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

  bool get _busy => _previous != null;

  @override
  void initState() {
    super.initState();
    _transitionController = AnimationController(
      vsync: this,
      duration: _transformDuration,
    )..addStatusListener((status) {
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
      if (_current >= n) {
        _transitionController.stop();
        setState(() {
          _current = n == 0 ? 0 : n - 1;
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

  void _commit(int dir) {
    final n = widget.transactions.length;
    if (_busy || n <= 1) return;
    final from = _current;
    final to = ((_current + dir) % n + n) % n;
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

  void _openDetail(TransactionView tx) {
    context.pushNamed('tx-detail', pathParameters: {'id': tx.id});
  }

  void _onPanDown(DragDownDetails details) {
    if (_busy) return;
    _pauseAutoRotate();
    _dragStartX = details.globalPosition.dx;
    _dragRawDx = 0;
    _dragMoved = false;
    setState(() {
      _liveDuration = const Duration(milliseconds: 100);
      _liveCurve = Curves.easeInOut;
      _dx = 0;
      _opacity = 1;
      _scale = 0.965;
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final startX = _dragStartX;
    if (startX == null || _busy) return;
    _dragRawDx = details.globalPosition.dx - startX;
    if (!_dragMoved && _dragRawDx.abs() > _dragTapTolerance) {
      _dragMoved = true;
    }
    if (!_dragMoved) return;
    final clamped = _dragRawDx.clamp(-_dragClamp, _dragClamp).toDouble();
    final scale =
        1 - (clamped.abs() / _dragClamp).clamp(0.0, 1.0).toDouble() * 0.08;
    final fade =
        1 - (clamped.abs() / (_dragClamp * 2)).clamp(0.0, 1.0).toDouble() * 0.3;
    setState(() {
      _liveDuration = Duration.zero;
      _liveCurve = Curves.linear;
      _dx = clamped * 0.6;
      _scale = scale;
      _opacity = fade;
    });
  }

  void _onPanEnd(DragEndDetails details, TransactionView activeTx) {
    if (_dragStartX == null || _busy) return;
    _dragStartX = null;

    if (_dragMoved && _dragRawDx.abs() > _dragCommitThreshold) {
      _commit(_dragRawDx < 0 ? 1 : -1);
    } else if (_dragMoved) {
      setState(() {
        _liveDuration = const Duration(milliseconds: 300);
        _liveCurve = Curves.easeOut;
        _dx = 0;
        _scale = 1;
        _opacity = 1;
      });
    } else {
      // Plain tap: haptic-style bounce, then open the receipt.
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
      _openDetail(activeTx);
    }
    _resumeAutoRotateSoon();
  }

  void _onPanCancel() {
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

  @override
  Widget build(BuildContext context) {
    final txs = widget.transactions;

    if (txs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Center(
          child: Text(
            'No receipts today yet',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textMuted,
                ),
          ),
        ),
      );
    }

    final n = txs.length;
    final current = _current < n ? _current : n - 1;
    final activeTx = txs[current];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: _viewportHeight,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanDown: n > 1 ? _onPanDown : null,
            onPanUpdate: n > 1 ? _onPanUpdate : null,
            onPanEnd: n > 1 ? (d) => _onPanEnd(d, activeTx) : null,
            onPanCancel: n > 1 ? _onPanCancel : null,
            onTap: n == 1 ? () => _openDetail(activeTx) : null,
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
          const SizedBox(height: 14),
          _DotIndicator(
            count: n,
            current: current,
            palettes:
                txs.map((t) => receiptPaletteForCategory(t.effectiveCategory)).toList(),
            onTap: _dotJump,
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
          (_transitionController.value * _transformDuration.inMilliseconds /
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
              child: _CardVisual(tx: tx, isNewest: i == 0),
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
  const _CardVisual({required this.tx, required this.isNewest});

  final TransactionView tx;
  final bool isNewest;

  static const _gold = Color(0xFFF6C64B);

  @override
  Widget build(BuildContext context) {
    final card = ReceiptCard(tx: tx);
    if (!isNewest) return card;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: _gold, width: 3),
            borderRadius: BorderRadius.circular(27),
          ),
          padding: const EdgeInsets.all(3),
          child: card,
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
    required this.count,
    required this.current,
    required this.palettes,
    required this.onTap,
  });

  final int count;
  final int current;
  final List<ReceiptCardPalette> palettes;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final isActive = i == current;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onTap(i),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 7),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              width: isActive ? 22 : 7,
              height: 7,
              decoration: BoxDecoration(
                color: isActive ? palettes[i].acc : AppColors.divider,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        );
      }),
    );
  }
}
