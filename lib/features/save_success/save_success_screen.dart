import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/platform/platform_feedback.dart';
import '../../core/bootstrap/app_services.dart';
import '../../core/theme/receipt_sheet_theme.dart';
import '../../domain/models/transaction_view.dart';
import '../../widgets/receipt_card.dart';
import 'save_success_painters.dart';

/// 3-second pigeon + mailbox micro-interaction played after a receipt is saved.
/// Navigates to the summary screen when the animation completes (or on Skip).
class SaveSuccessScreen extends StatefulWidget {
  const SaveSuccessScreen({super.key, this.savedTx});

  final TransactionView? savedTx;

  @override
  State<SaveSuccessScreen> createState() => _SaveSuccessScreenState();
}

class _SaveSuccessScreenState extends State<SaveSuccessScreen>
    with TickerProviderStateMixin {
  // Main 3-second sequence controller.
  late final AnimationController _mainCtrl;
  // Pigeon wing flap (240 ms, repeating).
  late final AnimationController _wingCtrl;
  // Pigeon body bob (480 ms, repeating).
  late final AnimationController _bobCtrl;

  // Interval-scoped animations from the main controller.
  late final Animation<double> _flight;
  late final Animation<double> _dropY;
  late final Animation<double> _flag;
  late final Animation<double> _badge;
  late final Animation<double> _cardHandoff;
  late final Animation<double> _mbScale;
  late final Animation<double> _mbSquashRaw;
  late final Animation<double> _cargoFade;

  Timer? _hapticFlagTimer;
  Timer? _hapticBadgeTimer;
  Timer? _navTimer;

  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();

    _mainCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );
    _wingCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    )..repeat(reverse: true);
    _bobCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    )..repeat(reverse: true);

    _flight = CurvedAnimation(
      parent: _mainCtrl,
      curve: const Interval(0.0, 0.70, curve: Curves.easeInOut),
    );
    _dropY = CurvedAnimation(
      parent: _mainCtrl,
      curve: const Interval(0.33, 0.53, curve: Curves.easeOut),
    );
    _flag = CurvedAnimation(
      parent: _mainCtrl,
      curve: const Interval(0.58, 0.75, curve: Curves.elasticOut),
    );
    _badge = CurvedAnimation(
      parent: _mainCtrl,
      curve: const Interval(0.68, 0.83, curve: Curves.easeOutBack),
    );
    _cardHandoff = CurvedAnimation(
      parent: _mainCtrl,
      curve: const Interval(0.83, 1.0, curve: Curves.easeOut),
    );
    _mbScale = CurvedAnimation(
      parent: _mainCtrl,
      curve: const Interval(0.10, 0.30, curve: Cubic(0.3, 0.7, 0.4, 1)),
    );
    _mbSquashRaw = CurvedAnimation(
      parent: _mainCtrl,
      curve: const Interval(0.50, 0.63),
    );
    _cargoFade = CurvedAnimation(
      parent: _mainCtrl,
      curve: const Interval(0.28, 0.45, curve: Curves.easeOut),
    );

    // Stop wing/bob when pigeon exits (past 70% of main controller).
    _mainCtrl.addListener(() {
      if (_mainCtrl.value >= 0.70) {
        if (_wingCtrl.isAnimating) _wingCtrl.stop();
        if (_bobCtrl.isAnimating) _bobCtrl.stop();
      }
    });

    _mainCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        _navigateAway();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.of(context).disableAnimations;

    if (_reduceMotion && !_mainCtrl.isAnimating && _mainCtrl.value == 0) {
      // Jump straight to done state.
      _mainCtrl.duration = Duration.zero;
      _mainCtrl.forward();
      _navTimer = Timer(const Duration(milliseconds: 400), _navigateAway);
    } else if (!_reduceMotion && !_mainCtrl.isAnimating && _mainCtrl.value == 0) {
      PlatformFeedback.lightTap();
      _mainCtrl.forward();

      _hapticFlagTimer = Timer(
        const Duration(milliseconds: 1900),
        PlatformFeedback.mediumTap,
      );
      _hapticBadgeTimer = Timer(
        const Duration(milliseconds: 2300),
        PlatformFeedback.lightTap,
      );
    }
  }

  void _navigateAway() {
    if (!mounted) return;
    context.goNamed('summary');
  }

  void _skip() {
    _mainCtrl.stop();
    _hapticFlagTimer?.cancel();
    _hapticBadgeTimer?.cancel();
    _navigateAway();
  }

  @override
  void dispose() {
    _hapticFlagTimer?.cancel();
    _hapticBadgeTimer?.cancel();
    _navTimer?.cancel();
    _mainCtrl.dispose();
    _wingCtrl.dispose();
    _bobCtrl.dispose();
    super.dispose();
  }

  String get _savedLabel => 'Saved';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFCF6EA),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: Listenable.merge([_mainCtrl, _wingCtrl, _bobCtrl]),
          builder: (context, _) => _buildScene(context),
        ),
      ),
    );
  }

  Widget _buildScene(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final sceneH = screenSize.height * 0.50;

    // --- Flight transform ---
    final f = _flight.value;
    double pigeonDx, pigeonDy, pigeonScale, pigeonRot, pigeonOpacity;
    if (f <= 0.457) {
      final t = f == 0 ? 0.0 : f / 0.457;
      pigeonDx = lerpDouble(170, 0, t)!;
      pigeonDy = lerpDouble(-16, 0, t)!;
      pigeonScale = lerpDouble(0.88, 1.0, t)!;
      pigeonRot = lerpDouble(-6 * pi / 180, 0, t)!;
      pigeonOpacity = (t * 7).clamp(0.0, 1.0); // fade in first 14%
    } else if (f <= 0.757) {
      pigeonDx = 0;
      pigeonDy = 0;
      pigeonScale = 1.0;
      pigeonRot = 0;
      pigeonOpacity = 1.0;
    } else {
      final t = (f - 0.757) / 0.243;
      pigeonDx = lerpDouble(0, -82, t)!;
      pigeonDy = lerpDouble(0, -122, t)!;
      pigeonScale = lerpDouble(1.0, 0.68, t)!;
      pigeonRot = lerpDouble(0, -12 * pi / 180, t)!;
      pigeonOpacity = lerpDouble(1.0, 0.0, t)!;
    }
    final showPigeon = _mainCtrl.value < 0.70;

    // Wing and bob
    final wingDeg = lerpDouble(-22, 28, _wingCtrl.value)!;
    final bobDy = lerpDouble(0, -5, _bobCtrl.value)!;

    // Mailbox scale (0.6→1.0)
    final mbS = 0.6 + 0.4 * _mbScale.value;

    // Mailbox squash envelope: peak at midpoint using sin
    final squash = 1.0 - 0.28 * sin(_mbSquashRaw.value * pi);

    // Flag angle: π/2 (down) → 0 (raised) driven by elasticOut
    final flagAngle = lerpDouble(pi / 2, 0, _flag.value.clamp(0.0, 1.2))!;

    // Badge
    final badgeOpacity = _badge.value.clamp(0.0, 1.0);
    final badgeScale = _badge.value.clamp(0.0, 1.2);

    // Drop: receipt falls toward mailbox
    final drop = _dropY.value;
    final showDrop = _mainCtrl.value >= 0.33 && _mainCtrl.value <= 0.56;
    double dropDy, dropOpacity;
    if (drop <= 0.35) {
      final t = drop == 0 ? 0.0 : drop / 0.35;
      dropDy = lerpDouble(-16, 8, t)!;
      dropOpacity = t;
    } else {
      final t = (drop - 0.35) / 0.65;
      dropDy = lerpDouble(8, 34, t)!;
      dropOpacity = lerpDouble(1.0, 0.0, t)!;
    }

    // Cargo (receipt in pigeon feet) fades out as drop starts
    final cargoOpacity = (1.0 - _cargoFade.value).clamp(0.0, 1.0);

    // Card strip slide-in
    final stripDy = 80 * (1.0 - _cardHandoff.value);
    final showStrip = _mainCtrl.value >= 0.83;

    // Mailbox center: horizontally centered, vertically at ~52-72% of scene
    final mbCenterX = screenSize.width / 2;
    final mbTop = sceneH * 0.50;
    const mbW = 110.0;
    const mbH = 72.0;

    return Stack(
      children: [
        // --- Static scene background ---
        Semantics(
          label: 'Pigeon delivery animation',
          excludeSemantics: true,
          child: RepaintBoundary(
            child: CustomPaint(
              size: Size(screenSize.width, sceneH),
              painter: const ScenePainter(),
            ),
          ),
        ),

        // --- Mailbox (scale-in + squash on delivery) ---
        Positioned(
          left: mbCenterX - mbW * 0.5,
          top: mbTop,
          child: Transform.scale(
            scale: mbS,
            alignment: Alignment.bottomCenter,
            child: Transform.scale(
              scaleX: squash < 1.0 ? 1.0 + (1.0 - squash) * 0.3 : 1.0,
              scaleY: squash,
              alignment: Alignment.bottomCenter,
              child: CustomPaint(
                size: const Size(mbW, mbH),
                painter: MailboxPainter(flagAngle: flagAngle),
              ),
            ),
          ),
        ),

        // --- Pigeon (only during flight phase) ---
        if (showPigeon)
          Positioned(
            left: mbCenterX - 40 + pigeonDx,
            top: sceneH * 0.16 + pigeonDy + bobDy,
            child: Opacity(
              opacity: pigeonOpacity.clamp(0.0, 1.0),
              child: Transform.rotate(
                angle: pigeonRot,
                child: Transform.scale(
                  scale: pigeonScale,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CustomPaint(
                        size: const Size(80, 52),
                        painter: PigeonPainter(wingAngleDeg: wingDeg),
                      ),
                      // Receipt dangling from feet
                      Opacity(
                        opacity: cargoOpacity,
                        child: const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: CustomPaint(
                            size: Size(22, 28),
                            painter: ReceiptSlipPainter(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

        // --- Falling receipt (drop phase) ---
        if (showDrop)
          Positioned(
            left: mbCenterX - 11,
            top: mbTop - 20 + dropDy,
            child: Opacity(
              opacity: dropOpacity.clamp(0.0, 1.0),
              child: const CustomPaint(
                size: Size(22, 28),
                painter: ReceiptSlipPainter(),
              ),
            ),
          ),

        // --- "Saved" badge ---
        if (badgeOpacity > 0.01)
          Positioned(
            top: sceneH * 0.06,
            left: 0,
            right: 0,
            child: Semantics(
              liveRegion: true,
              label: _savedLabel,
              child: Center(
                child: Opacity(
                  opacity: badgeOpacity,
                  child: Transform.scale(
                    scale: badgeScale,
                    child: _SavedBadge(label: _savedLabel),
                  ),
                ),
              ),
            ),
          ),

        // --- Today's Receipts strip ---
        if (showStrip)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Transform.translate(
              offset: Offset(0, stripDy),
              child: IgnorePointer(
                ignoring: _mainCtrl.isAnimating,
                child: _TodayStrip(savedTx: widget.savedTx),
              ),
            ),
          ),

        // --- Skip button ---
        if (_mainCtrl.isAnimating && !_mainCtrl.isCompleted)
          Positioned(
            right: 16,
            top: 16,
            child: Semantics(
              label: 'Skip animation',
              button: true,
              child: GestureDetector(
                onTap: _skip,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF3C2814).withValues(alpha: 0.12),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Text(
                    'Skip',
                    style: balooText(13, FontWeight.w800, color: const Color(0xFF7A6A50)),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// "Saved" badge pill
// ---------------------------------------------------------------------------

class _SavedBadge extends StatelessWidget {
  const _SavedBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF5E9E51),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF325A1E).withValues(alpha: 0.28),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check,
              color: Color(0xFF5E9E51),
              size: 13,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: balooText(15, FontWeight.w800, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Today's Receipts strip
// ---------------------------------------------------------------------------

class _TodayStrip extends StatelessWidget {
  const _TodayStrip({this.savedTx});

  final TransactionView? savedTx;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFFCF6EA),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "TODAY'S RECEIPTS",
            style: balooText(
              11.5,
              FontWeight.w800,
              color: const Color(0xFF8C857B),
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          StreamBuilder<List<TransactionView>>(
            stream: AppServices.transactions.watchAll(),
            builder: (context, snap) {
              final all = snap.data ?? (savedTx != null ? [savedTx!] : const <TransactionView>[]);
              final now = DateTime.now();
              final today = all
                  .where((t) =>
                      t.occurredAt.year == now.year &&
                      t.occurredAt.month == now.month &&
                      t.occurredAt.day == now.day)
                  .toList();
              if (today.isEmpty && savedTx != null) today.insert(0, savedTx!);

              return SizedBox(
                height: 90,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: today.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final tx = today[i];
                    final isNew = tx.id == savedTx?.id;
                    final palette = receiptPaletteForCategory(tx.effectiveCategory);
                    return Opacity(
                      opacity: isNew ? 1.0 : 0.35,
                      child: Container(
                        width: 74,
                        decoration: BoxDecoration(
                          color: palette.tile,
                          borderRadius: BorderRadius.circular(14),
                          border: isNew
                              ? Border.all(color: const Color(0xFFF6C64B), width: 2.5)
                              : null,
                          boxShadow: isNew
                              ? [
                                  BoxShadow(
                                    color: const Color(0xFF46281A).withValues(alpha: 0.16),
                                    blurRadius: 14,
                                    offset: const Offset(0, 6),
                                  ),
                                ]
                              : null,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(palette.emoji, style: const TextStyle(fontSize: 22)),
                            const SizedBox(height: 4),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: Text(
                                tx.effectiveCategory,
                                style: balooText(9.5, FontWeight.w800, color: palette.ink),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
