import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/models/ocr_progress_event.dart';
import 'batch_scan_progress.dart';
import 'ocr_progress_notifier.dart';
import 'receipt_ingest_draft.dart';

/// A live OCR attempt: the event stream to listen to, and how to tear it
/// down. Built fresh by [OcrAttemptFactory] each time — once at first show,
/// and again on every Retry — so a retry actually re-runs ingest rather than
/// just re-subscribing to a stream that already finished.
typedef OcrAttemptHandle = ({Stream<OcrProgressEvent> stream, VoidCallback dispose});
typedef OcrAttemptFactory = OcrAttemptHandle Function();

/// Full-screen animated receipt processing view.
///
/// Driven by real pipeline milestones (OCR start, merchant extraction, total
/// extraction, category prediction) via [attemptFactory] — each call starts
/// a fresh OCR attempt. Pops with the [ReceiptIngestDraft] on success, or
/// with null if the user backs out (cancel, or "Skip for now" after a
/// failure). On failure the screen stays open with an inline retry state
/// instead of popping immediately.
///
/// When [batchProgress] is supplied with more than one receipt in the
/// batch, a progress footer ("N of M completed") is shown below the log
/// panel; omit it (or leave totalCount at 1) for a single-receipt scan.
class ReceiptScanProcessingScreen extends StatefulWidget {
  const ReceiptScanProcessingScreen({
    super.key,
    required this.attemptFactory,
    this.batchProgress,
  });

  final OcrAttemptFactory attemptFactory;
  final BatchScanProgress? batchProgress;

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
  static const _kError = Color(0xFFB23A2E);
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

  // Failure / retry state
  bool _failed = false;
  bool _retrying = false;
  int _failedStepIndex = -1;

  OcrAttemptHandle? _attempt;
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

    _startAttempt();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _attempt?.dispose();
    _entranceCtrl.dispose();
    _floatCtrl.dispose();
    _breatheCtrl.dispose();
    _rowScanCtrl.dispose();
    super.dispose();
  }

  // ── Attempt lifecycle ─────────────────────────────────────────────────────

  void _startAttempt() {
    _attempt = widget.attemptFactory();
    _sub = _attempt!.stream.listen(_handleEvent, onError: _handleError);
  }

  void _retry() {
    _sub?.cancel();
    _attempt?.dispose();
    setState(() {
      _failed = false;
      _retrying = true;
      _failedStepIndex = -1;
      _stage = OcrProcessingStage.uploading;
      _merchantName = null;
      _totalAmount = null;
      _categoryName = null;
      _showSuccess = false;
    });
    _breatheCtrl.reset();
    _startAttempt();
  }

  void _skip() => Navigator.of(context).pop();

  // ── Event handling ────────────────────────────────────────────────────────

  void _handleEvent(OcrProgressEvent event) {
    _retrying = false;
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
    final idx = _currentActiveStepIndex();
    setState(() {
      _failed = true;
      _retrying = false;
      _failedStepIndex = idx;
    });
    _breatheCtrl.stop();
  }

  // ── Log step helpers ──────────────────────────────────────────────────────

  int _currentActiveStepIndex() {
    for (var i = 0; i < 5; i++) {
      if (_baseStepState(i) == _LogItemState.active) return i;
    }
    return -1;
  }

  _LogItemState _stepState(int i) {
    if (_failed && i == _failedStepIndex) return _LogItemState.error;
    return _baseStepState(i);
  }

  _LogItemState _baseStepState(int i) => switch (i) {
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

  String _stepText(int i) {
    if (_failed && i == _failedStepIndex) return _failureTextFor(i);
    return switch (i) {
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
  }

  String _failureTextFor(int i) => switch (i) {
        0 => "Couldn't read the receipt",
        1 => "Couldn't identify the merchant",
        2 => "Couldn't extract totals",
        3 => "Couldn't classify spending type",
        _ => 'Something went wrong',
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

  bool get _showBatchFooter =>
      widget.batchProgress != null && widget.batchProgress!.totalCount > 1;

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: Center(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        AnimatedBuilder(
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
                                      _failed
                                          ? _dimmedReceiptCard()
                                          : _receiptCard(),
                                      if (_showSuccess) _successOverlay(),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        if (_failed) _failedOverlay(),
                      ],
                    ),
                  ),
                ),
                _processingPanel(),
              ],
            ),
            if (_failed)
              Positioned(
                top: 4,
                left: 4,
                child: _CloseButton(onTap: _skip),
              ),
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

  Widget _dimmedReceiptCard() {
    return Opacity(
      opacity: 0.55,
      child: ColorFiltered(
        colorFilter: const ColorFilter.matrix(<double>[
          0.2126, 0.7152, 0.0722, 0, 0, //
          0.2126, 0.7152, 0.0722, 0, 0, //
          0.2126, 0.7152, 0.0722, 0, 0, //
          0, 0, 0, 1, 0, //
        ]),
        child: _receiptCard(),
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

  Widget _failedOverlay() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _kError.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.error_outline, color: _kError, size: 22),
          ),
          const SizedBox(height: 12),
          Text(
            "Couldn't read this receipt",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _kText,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'The image is too blurry to extract details. Try retaking the photo in better lighting.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _kText.withValues(alpha: 0.75),
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: _retrying ? null : _retry,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2C2C33),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                child: Text(_retrying ? 'Retrying…' : 'Retry scan'),
              ),
              if (_showBatchFooter)
                TextButton(
                  onPressed: _skip,
                  child: Text(
                    'Skip for now',
                    style: TextStyle(color: _kText.withValues(alpha: 0.7)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _processingPanel() {
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
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _logContent(),
            if (_showBatchFooter) _BatchFooter(progress: widget.batchProgress!),
            SizedBox(height: MediaQuery.paddingOf(context).bottom),
          ],
        ),
      ),
    );
  }

  Widget _logContent() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
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

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.35),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.all(8),
          child: Icon(Icons.close, color: Colors.white, size: 18),
        ),
      ),
    );
  }
}

class _BatchFooter extends StatefulWidget {
  const _BatchFooter({required this.progress});

  final BatchScanProgress progress;

  @override
  State<_BatchFooter> createState() => _BatchFooterState();
}

class _BatchFooterState extends State<_BatchFooter>
    with SingleTickerProviderStateMixin {
  static const _kAccent = Color(0xFFE2885C);
  static const _kText = Color(0xFF5A4632);
  static const _kFooterBg = Color(0xFFF5E9D6);
  static const _kFooterBorder = Color(0xFFEADFC5);

  bool _expanded = false;
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.progress;
    return Container(
      decoration: const BoxDecoration(
        color: _kFooterBg,
        border: Border(top: BorderSide(color: _kFooterBorder)),
      ),
      child: Column(
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            child: _expanded ? _expandedList(progress) : const SizedBox.shrink(),
          ),
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  FadeTransition(
                    opacity: Tween<double>(begin: 0.35, end: 1.0).animate(_pulseCtrl),
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: _kAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      progress.lastCompletedName != null
                          ? '${progress.completedCount} of ${progress.totalCount} completed · last: ${progress.lastCompletedName}'
                          : '${progress.completedCount} of ${progress.totalCount} completed',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF2C2C33),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 220),
                    child: const Icon(
                      Icons.keyboard_arrow_down,
                      size: 18,
                      color: Color(0xFF8A8170),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _expandedList(BatchScanProgress progress) {
    if (progress.completedNames.isEmpty) return const SizedBox.shrink();
    return Container(
      constraints: const BoxConstraints(maxHeight: 150),
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _kFooterBorder)),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: progress.completedNames.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final name = progress.completedNames[i];
          return Row(
            children: [
              Container(
                width: 15,
                height: 15,
                decoration: const BoxDecoration(
                  color: _kAccent,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, size: 9, color: Colors.white),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _kText,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

enum _LogItemState { idle, active, done, error }

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
  static const _kError = Color(0xFFB23A2E);

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
    if (state == _LogItemState.error) {
      return Container(
        width: 16,
        height: 16,
        decoration: const BoxDecoration(
          color: _kError,
          shape: BoxShape.circle,
        ),
        child: const Center(
          child: Text(
            '!',
            style: TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
        ),
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
          color: state == _LogItemState.error ? _kError : _kText,
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
