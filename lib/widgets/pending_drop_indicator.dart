import 'package:flutter/material.dart';

import '../domain/models/pending_import_model.dart';

/// Animated beacon for pending (not-yet-OCR'd) receipts, shown just above
/// "Today's Receipts" on the home screen. The caller hides it entirely when
/// [pending] is empty.
///
/// Three states, matching the "Drop Indicator" design concept:
/// - idle: slow breathing loop while receipts sit waiting.
/// - new arrival: a quick double-pulse + expanding ring when the count goes
///   up, then settles back to idle.
/// - processing: a faster shimmer while any pending import is mid-OCR.
class PendingDropIndicator extends StatefulWidget {
  const PendingDropIndicator({
    super.key,
    required this.pending,
    required this.onTap,
  });

  final List<PendingImportModel> pending;
  final VoidCallback onTap;

  @override
  State<PendingDropIndicator> createState() => _PendingDropIndicatorState();
}

class _PendingDropIndicatorState extends State<PendingDropIndicator>
    with TickerProviderStateMixin {
  static const _kAccent = Color(0xFFE2885C);
  static const _kGold = Color(0xFFF5C242);
  static const _kInk = Color(0xFF23201A);
  static const _kSub = Color(0xFF9C8A5E);
  static const _kAction = Color(0xFFB4483B);

  late final AnimationController _breatheCtrl;
  late final AnimationController _burstCtrl;
  late final AnimationController _processingCtrl;

  late final Animation<double> _burstScale;
  late final Animation<double> _burstRingScale;
  late final Animation<double> _burstRingOpacity;

  int _previousCount = 0;
  bool _bursting = false;

  @override
  void initState() {
    super.initState();
    _previousCount = widget.pending.length;

    _breatheCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);

    _processingCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _burstCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() => _bursting = false);
        }
      });

    // Two back-to-back pulses (scale .75 -> 1.3 -> 1.0) packed into one
    // 1800ms timeline, so a single forward() plays as "two quick pulses".
    _burstScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.75, end: 1.3).chain(CurveTween(curve: Curves.easeOut)),
        weight: 55,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.3, end: 1.0).chain(CurveTween(curve: Curves.easeIn)),
        weight: 45,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.75, end: 1.3).chain(CurveTween(curve: Curves.easeOut)),
        weight: 55,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.3, end: 1.0).chain(CurveTween(curve: Curves.easeIn)),
        weight: 45,
      ),
    ]).animate(_burstCtrl);

    _burstRingScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.5, end: 2.4), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 0.5, end: 2.4), weight: 50),
    ]).animate(_burstCtrl);

    _burstRingOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.5, end: 0.0), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 0.5, end: 0.0), weight: 50),
    ]).animate(_burstCtrl);

    // The indicator appearing at all is itself a new-arrival event.
    if (widget.pending.isNotEmpty) _triggerBurst();
  }

  @override
  void didUpdateWidget(covariant PendingDropIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newCount = widget.pending.length;
    if (newCount > _previousCount) _triggerBurst();
    _previousCount = newCount;
  }

  void _triggerBurst() {
    setState(() => _bursting = true);
    _burstCtrl.forward(from: 0);
  }

  @override
  void dispose() {
    _breatheCtrl.dispose();
    _burstCtrl.dispose();
    _processingCtrl.dispose();
    super.dispose();
  }

  bool get _isProcessing => widget.pending.any((p) => p.isProcessing);

  String _relativeTime(DateTime createdAt) {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String _subtitleFor(PendingImportModel import) {
    final time = _relativeTime(import.createdAt);
    return import.sourceApp != null ? '${import.sourceApp} · $time' : time;
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.pending.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Material(
        color: const Color(0xFFFFFBF2),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFFFFBF2), Color(0xFFFFF6E4)],
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _kGold.withValues(alpha: 0.28), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: _kGold.withValues(alpha: 0.18),
                  blurRadius: 28,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  SizedBox(
                    width: count > 1 ? _stackWidth(count) : 14,
                    height: 20,
                    child: count > 1 ? _stackedDots(count) : Center(child: _singleDot()),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          count == 1 ? 'New Drop' : '$count New Drops',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: _kInk,
                          ),
                        ),
                        if (count == 1) ...[
                          const SizedBox(height: 1),
                          Text(
                            _subtitleFor(widget.pending.single),
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: _kSub,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Text(
                    count == 1 ? 'Review →' : 'Review all →',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: _kAction,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  double _stackWidth(int count) {
    final visible = count > 3 ? 3 : count;
    final dotsWidth = (visible - 1) * 7.0 + 10;
    return count > 3 ? dotsWidth + 16 : dotsWidth;
  }

  Widget _stackedDots(int count) {
    final visible = count > 3 ? 3 : count;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (var i = 0; i < visible; i++)
          Positioned(
            left: i * 7.0,
            top: 5,
            child: i == visible - 1
                ? _singleDot(size: 10, showRing: false)
                : _staticDot(opacity: i == 0 ? 0.3 : 0.55),
          ),
        if (count > 3)
          Positioned(
            left: visible * 7.0 + 12,
            top: 3,
            child: Text(
              '+${count - 3}',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: _kAction,
              ),
            ),
          ),
      ],
    );
  }

  Widget _staticDot({required double opacity}) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: _kAccent.withValues(alpha: opacity),
        shape: BoxShape.circle,
      ),
    );
  }

  Widget _singleDot({double size = 14, bool showRing = true}) {
    return AnimatedBuilder(
      animation: Listenable.merge([_breatheCtrl, _burstCtrl, _processingCtrl]),
      builder: (context, _) {
        double scale;
        double opacity;
        var ringOpacity = 0.0;
        var ringScale = 0.0;

        if (_bursting) {
          scale = _burstScale.value;
          opacity = 1;
          ringOpacity = _burstRingOpacity.value;
          ringScale = _burstRingScale.value;
        } else if (_isProcessing) {
          scale = 1;
          opacity = 0.3 + 0.7 * _processingCtrl.value;
        } else {
          opacity = 0.5 + 0.5 * _breatheCtrl.value;
          scale = 1 + 0.18 * _breatheCtrl.value;
        }

        final dotSize = size * 0.72;
        return SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              if (showRing && ringOpacity > 0)
                Opacity(
                  opacity: ringOpacity,
                  child: Transform.scale(
                    scale: ringScale,
                    child: Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: _kAccent, width: 1.5),
                      ),
                    ),
                  ),
                ),
              Transform.scale(
                scale: scale,
                child: Opacity(
                  opacity: opacity,
                  child: Container(
                    width: dotSize,
                    height: dotSize,
                    decoration: const BoxDecoration(
                      color: _kAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
