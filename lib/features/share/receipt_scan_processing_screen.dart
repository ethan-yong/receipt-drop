import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/platform/platform_feedback.dart';
import '../../domain/models/ocr_progress_event.dart';
import 'ocr_progress_notifier.dart';
import 'receipt_ingest_draft.dart';

/// Full-screen animated receipt processing view.
///
/// Driven by [OcrProgressNotifier.stream] — each real pipeline milestone
/// (OCR start, merchant extraction, total extraction, category prediction)
/// advances the log and animates the receipt card. Pops with the
/// [ReceiptIngestDraft] on success, or with null on failure/cancel.
class ReceiptScanProcessingScreen extends StatefulWidget {
  const ReceiptScanProcessingScreen({super.key, required this.stream});

  final Stream<OcrProgressEvent> stream;

  @override
  State<ReceiptScanProcessingScreen> createState() =>
      _ReceiptScanProcessingScreenState();
}

class _ReceiptScanProcessingScreenState
    extends State<ReceiptScanProcessingScreen> with TickerProviderStateMixin {
  static const _kAccent = Color(0xFFE2885C);
  static const _kBg = Color(0xFFF4E8D6);
  static const _kCardSurface = Color(0xFFFFFDF8);
  static const _kText = Color(0xFF5A4632);
  static const _kHighlightColor = Color(0x8DE2885C);
  static const _kHighlightDuration = Duration(milliseconds: 300);

  // Animation controllers
  late final AnimationController _entranceCtrl;
  late final AnimationController _floatCtrl;
  late final AnimationController _breatheCtrl;
  late final AnimationController _rowScanCtrl;

  // Pipeline state
  OcrProcessingStage _stage = OcrProcessingStage.uploading;
  String? _merchantName;
  double? _totalAmount;
  String? _categoryName;
  bool _showSuccess = false;

  StreamSubscription<OcrProgressEvent>? _sub;

  // Fixed item row widths for variety (name bar width, price bar width)
  static const _itemRows = [
    (118.0, 36.0),
    (86.0, 40.0),
    (102.0, 32.0),
    (134.0, 36.0),
    (94.0, 40.0),
    (78.0, 32.0),
    (110.0, 36.0),
    (90.0, 40.0),
  ];

  @override
  void initState() {
    super.initState();

    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..forward();

    _floatCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    _breatheCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );

    _rowScanCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _sub = widget.stream.listen(_handleEvent, onError: _handleError);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _entranceCtrl.dispose();
    _floatCtrl.dispose();
    _breatheCtrl.dispose();
    _rowScanCtrl.dispose();
    super.dispose();
  }

  // ── Event handling ────────────────────────────────────────────────────────

  void _handleEvent(OcrProgressEvent event) {
    switch (event) {
      case ReceiptUploadedEvent():
        setState(() => _stage = OcrProcessingStage.uploading);
      case OcrStartedEvent():
        setState(() => _stage = OcrProcessingStage.scanning);
        _rowScanCtrl.forward(from: 0);
        _breatheCtrl.repeat(reverse: true);
      case OcrCompletedEvent():
        setState(() => _stage = OcrProcessingStage.extracting);
      case MerchantIdentifiedEvent(:final merchant):
        setState(() {
          _stage = OcrProcessingStage.merchant;
          _merchantName = merchant;
        });
      case ItemsExtractedEvent():
        setState(() => _stage = OcrProcessingStage.items);
      case TotalExtractedEvent(:final amount):
        setState(() {
          _stage = OcrProcessingStage.total;
          _totalAmount = amount;
        });
      case CategoryPredictedEvent(:final category):
        setState(() {
          _stage = OcrProcessingStage.category;
          _categoryName = category;
        });
      case ProcessingCompletedEvent(:final draft):
        _handleCompleted(draft);
      case ProcessingFailedEvent(:final error):
        _handleFailed(error);
    }
  }

  void _handleError(Object error) => _handleFailed(error);

  Future<void> _handleCompleted(ReceiptIngestDraft draft) async {
    setState(() => _stage = OcrProcessingStage.done);
    _breatheCtrl.stop();
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    setState(() => _showSuccess = true);
    await Future<void>.delayed(const Duration(milliseconds: 650));
    if (!mounted) return;
    Navigator.of(context).pop(draft);
  }

  void _handleFailed(Object error) {
    if (!mounted) return;
    PlatformFeedback.showError(context, 'Could not read receipt: $error');
    Navigator.of(context).pop();
  }

  // ── Log step helpers ──────────────────────────────────────────────────────

  _LogItemState _stepState(int i) => switch (i) {
        0 => switch (_stage) {
            OcrProcessingStage.uploading => _LogItemState.idle,
            OcrProcessingStage.scanning ||
            OcrProcessingStage.extracting =>
              _LogItemState.active,
            _ => _LogItemState.done,
          },
        1 => switch (_stage) {
            OcrProcessingStage.uploading ||
            OcrProcessingStage.scanning ||
            OcrProcessingStage.extracting =>
              _LogItemState.idle,
            OcrProcessingStage.merchant ||
            OcrProcessingStage.items =>
              _LogItemState.active,
            _ => _LogItemState.done,
          },
        2 => switch (_stage) {
            OcrProcessingStage.total => _LogItemState.active,
            OcrProcessingStage.category ||
            OcrProcessingStage.done =>
              _LogItemState.done,
            _ => _LogItemState.idle,
          },
        3 => switch (_stage) {
            OcrProcessingStage.category => _LogItemState.active,
            OcrProcessingStage.done => _LogItemState.done,
            _ => _LogItemState.idle,
          },
        4 => _stage == OcrProcessingStage.done
            ? _LogItemState.done
            : _LogItemState.idle,
        _ => _LogItemState.idle,
      };

  String _stepText(int i) => switch (i) {
        0 => 'Reading receipt…',
        1 => _merchantName != null
            ? 'Detected: $_merchantName'
            : 'Identifying merchant…',
        2 => _totalAmount != null
            ? 'Found total: RM${_totalAmount!.toStringAsFixed(2)}'
            : 'Extracting totals…',
        3 => 'Understanding spending type…',
        4 => 'Analysing receipt type…',
        _ => '',
      };

  // ── Row highlight helpers ─────────────────────────────────────────────────

  bool get _merchantHighlighted =>
      _stage == OcrProcessingStage.merchant ||
      _stage == OcrProcessingStage.category;

  bool get _totalHighlighted =>
      _stage == OcrProcessingStage.total ||
      _stage == OcrProcessingStage.category;

  // During scanning a lit window sweeps down over item rows.
  double _scanRowOpacity(int index) {
    if (_stage != OcrProcessingStage.scanning &&
        _stage != OcrProcessingStage.extracting) {
      return 0.0;
    }
    final value = _rowScanCtrl.value;
    final rowCenter = (index + 0.5) / _itemRows.length;
    final dist = (value - rowCenter).abs();
    return (1.0 - dist / 0.18).clamp(0.0, 0.75);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: AnimatedBuilder(
                  animation: Listenable.merge(
                      [_entranceCtrl, _floatCtrl, _rowScanCtrl]),
                  builder: (context, _) {
                    final floatOffset =
                        math.sin(_floatCtrl.value * 2 * math.pi) * 3.0;
                    final tiltAngle =
                        (1.0 - _entranceCtrl.value) * -0.07;
                    return FadeTransition(
                      opacity: CurvedAnimation(
                        parent: _entranceCtrl,
                        curve: Curves.easeOut,
                      ),
                      child: Transform.translate(
                        offset: Offset(0, floatOffset),
                        child: Transform.rotate(
                          angle: tiltAngle,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              _receiptCard(),
                              if (_showSuccess) _successOverlay(),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            _logPanel(),
          ],
        ),
      ),
    );
  }

  Widget _receiptCard() {
    return Container(
      width: 244,
      decoration: BoxDecoration(
        color: _kCardSurface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Merchant row
            AnimatedContainer(
              duration: _kHighlightDuration,
              padding:
                  const EdgeInsets.symmetric(vertical: 7, horizontal: 6),
              decoration: BoxDecoration(
                color: _merchantHighlighted ? _kHighlightColor : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  _bar(width: 104, height: 9, opacity: 0.78),
                  const SizedBox(width: 12),
                  _bar(width: 52, height: 7, opacity: 0.42),
                ],
              ),
            ),
            const SizedBox(height: 6),
            const _DashedDivider(),
            const SizedBox(height: 6),
            // Item rows
            for (var i = 0; i < _itemRows.length; i++) ...[
              _itemRow(i),
              if (i < _itemRows.length - 1) const SizedBox(height: 5),
            ],
            const SizedBox(height: 6),
            const _DashedDivider(),
            const SizedBox(height: 6),
            // Total row
            AnimatedContainer(
              duration: _kHighlightDuration,
              padding:
                  const EdgeInsets.symmetric(vertical: 7, horizontal: 6),
              decoration: BoxDecoration(
                color: _totalHighlighted ? _kHighlightColor : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _bar(width: 50, height: 9, opacity: 0.9),
                  _bar(width: 56, height: 9, opacity: 0.9),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _itemRow(int index) {
    final (nameWidth, priceWidth) = _itemRows[index];
    final highlight = _scanRowOpacity(index);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 6),
      decoration: BoxDecoration(
        color: Color.fromRGBO(
            0xE2, 0x88, 0x5C, highlight * 0.65),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _bar(width: nameWidth, height: 7, opacity: 0.52),
          _bar(width: priceWidth, height: 7, opacity: 0.52),
        ],
      ),
    );
  }

  Widget _bar({
    required double width,
    required double height,
    required double opacity,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: _kText.withValues(alpha: opacity),
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }

  Widget _successOverlay() {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 350),
      opacity: _showSuccess ? 1.0 : 0.0,
      child: Container(
        width: 244,
        decoration: BoxDecoration(
          color: _kCardSurface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(vertical: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: _kAccent,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check, color: Colors.white, size: 32),
            ),
            const SizedBox(height: 14),
            Text(
              'Saved!',
              style: TextStyle(
                color: _kText,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (_categoryName != null) ...[
              const SizedBox(height: 4),
              Text(
                _categoryName!,
                style: const TextStyle(
                  color: _kAccent,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _logPanel() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        20 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'PROCESSING',
            style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: 11.5,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < 5; i++)
            _LogItem(
              state: _stepState(i),
              text: _stepText(i),
              categoryName: i == 4 ? _categoryName : null,
              breathe: _breatheCtrl,
            ),
        ],
      ),
    );
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────

enum _LogItemState { idle, active, done }

class _LogItem extends StatelessWidget {
  const _LogItem({
    required this.state,
    required this.text,
    required this.breathe,
    this.categoryName,
  });

  final _LogItemState state;
  final String text;
  final Animation<double> breathe;
  final String? categoryName;

  static const _kAccent = Color(0xFFE2885C);
  static const _kText = Color(0xFF5A4632);

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 280),
      opacity: state == _LogItemState.idle ? 0.0 : 1.0,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
        offset:
            state == _LogItemState.idle ? const Offset(0, 0.4) : Offset.zero,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(width: 20, height: 20, child: _icon()),
              const SizedBox(width: 10),
              Expanded(child: _label()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _icon() {
    if (state == _LogItemState.done) {
      return Container(
        width: 16,
        height: 16,
        decoration: const BoxDecoration(
          color: _kAccent,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.check, color: Colors.white, size: 10),
      );
    }
    if (state == _LogItemState.active) {
      return Center(
        child: FadeTransition(
          opacity: Tween<double>(begin: 0.42, end: 1.0).animate(breathe),
          child: Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: _kAccent,
              shape: BoxShape.circle,
            ),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _label() {
    // Step 4 final reveal: "This looks like a [Category] expense"
    if (categoryName != null) {
      return Text.rich(
        TextSpan(
          style: const TextStyle(fontSize: 13, color: _kText),
          children: [
            const TextSpan(text: 'This looks like a '),
            TextSpan(
              text: categoryName,
              style: const TextStyle(
                color: _kAccent,
                fontWeight: FontWeight.w700,
              ),
            ),
            const TextSpan(text: ' expense'),
          ],
        ),
      );
    }

    if (state == _LogItemState.active) {
      return FadeTransition(
        opacity: Tween<double>(begin: 0.65, end: 1.0).animate(breathe),
        child: _staticText(),
      );
    }

    return _staticText();
  }

  Widget _staticText() => Text(
        text,
        style: TextStyle(
          fontSize: 13,
          color: _kText,
          fontWeight: state == _LogItemState.done
              ? FontWeight.w500
              : FontWeight.w400,
        ),
      );
}

class _DashedDivider extends StatelessWidget {
  const _DashedDivider();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, constraints) {
      const dashWidth = 5.0;
      const gap = 4.0;
      final count =
          ((constraints.maxWidth + gap) / (dashWidth + gap)).floor();
      return Row(
        children: List.generate(
          count,
          (i) => Padding(
            padding: EdgeInsets.only(right: i < count - 1 ? gap : 0),
            child: Container(
              width: dashWidth,
              height: 1,
              color: const Color(0xFF5A4632).withValues(alpha: 0.18),
            ),
          ),
        ),
      );
    });
  }
}
