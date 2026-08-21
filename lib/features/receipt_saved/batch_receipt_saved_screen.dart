import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/platform/platform_feedback.dart';
import '../../core/theme/receipt_sheet_theme.dart';
import '../../domain/models/transaction_view.dart';

/// Full-screen celebration shown after a "Process all" batch save of N > 1
/// receipts — the batch equivalent of ReceiptSavedScreen. Lists each saved
/// receipt with merchant + amount, shows the total, then "Done" lands on
/// Insights exactly once.
class BatchReceiptSavedScreen extends StatefulWidget {
  const BatchReceiptSavedScreen({super.key, required this.receipts});

  final List<TransactionView> receipts;

  @override
  State<BatchReceiptSavedScreen> createState() =>
      _BatchReceiptSavedScreenState();
}

class _BatchReceiptSavedScreenState extends State<BatchReceiptSavedScreen>
    with SingleTickerProviderStateMixin {
  static const _totalDuration = Duration(milliseconds: 650);

  late final AnimationController _ctrl;
  late final Animation<double> _badge;
  late final Animation<double> _card;
  late final Animation<double> _footer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: _totalDuration);
    _badge = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.0, 450 / 650, curve: Curves.easeOutBack),
    );
    _card = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(100 / 650, 550 / 650, curve: Curves.easeOut),
    );
    _footer = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(200 / 650, 1.0, curve: Curves.easeOut),
    );
    PlatformFeedback.lightTap();
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _done() => context.goNamed('insights');

  double get _total =>
      widget.receipts.fold(0.0, (sum, tx) => sum + (tx.amountMyr ?? 0));

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _done();
      },
      child: Scaffold(
        backgroundColor: ReceiptSheetColors.screenBackground,
        body: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 42),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedBuilder(
                        animation: _badge,
                        builder: (context, child) => Opacity(
                          opacity: _badge.value.clamp(0.0, 1.0),
                          child: Transform.scale(
                            scale: _badge.value.clamp(0.0, 1.2),
                            child: child,
                          ),
                        ),
                        child: _BatchSavedPill(count: widget.receipts.length),
                      ),
                      const SizedBox(height: 16),
                      AnimatedBuilder(
                        animation: _card,
                        builder: (context, child) => Opacity(
                          opacity: _card.value.clamp(0.0, 1.0),
                          child: Transform.translate(
                            offset: Offset(
                              0,
                              14 * (1 - _card.value.clamp(0.0, 1.0)),
                            ),
                            child: child,
                          ),
                        ),
                        child: _BatchSummaryCard(
                          receipts: widget.receipts,
                          total: _total,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              AnimatedBuilder(
                animation: _footer,
                builder: (context, child) => Opacity(
                  opacity: _footer.value.clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(
                      0,
                      14 * (1 - _footer.value.clamp(0.0, 1.0)),
                    ),
                    child: child,
                  ),
                ),
                child: _DoneFooter(onDone: _done),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}

class _BatchSavedPill extends StatelessWidget {
  const _BatchSavedPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFF5E9E51),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF325A1E).withValues(alpha: 0.3),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check,
              color: Color(0xFF5E9E51),
              size: 9,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$count receipts saved!',
            style: balooText(14, FontWeight.w800, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _BatchSummaryCard extends StatelessWidget {
  const _BatchSummaryCard({
    required this.receipts,
    required this.total,
  });

  final List<TransactionView> receipts;
  final double total;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: ReceiptSheetColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3C2814).withValues(alpha: 0.14),
            blurRadius: 26,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < receipts.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            _ReceiptRow(receipt: receipts[i]),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: _DashedDivider(),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total',
                style: balooText(
                  14,
                  FontWeight.w700,
                  color: ReceiptSheetColors.sub,
                ),
              ),
              Text(
                'RM ${total.toStringAsFixed(2)}',
                style: balooText(
                  17,
                  FontWeight.w800,
                  color: ReceiptSheetColors.ink,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow({required this.receipt});

  final TransactionView receipt;

  String get _merchant => receipt.displayPlace;

  String get _initial {
    final trimmed = _merchant.trim();
    return trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
  }

  String get _amount =>
      'RM ${(receipt.amountMyr ?? 0).toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(
            color: ReceiptSheetColors.avatarGold,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            _initial,
            style: balooText(14, FontWeight.w800, color: Colors.white),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            _merchant,
            style: balooText(
              15,
              FontWeight.w800,
              color: ReceiptSheetColors.ink,
              letterSpacing: -0.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _amount,
          style: balooText(
            14,
            FontWeight.w700,
            color: ReceiptSheetColors.body,
          ),
        ),
      ],
    );
  }
}

class _DashedDivider extends StatelessWidget {
  const _DashedDivider();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 2,
      width: double.infinity,
      child: CustomPaint(painter: _DashedLinePainter()),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  const _DashedLinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = ReceiptSheetColors.dashedDivider
      ..strokeWidth = 2;
    const dashWidth = 6.0;
    const gap = 5.0;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 1), Offset(x + dashWidth, 1), paint);
      x += dashWidth + gap;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DoneFooter extends StatelessWidget {
  const _DoneFooter({required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: _PrimaryButton(label: 'Done', onTap: onDone),
    );
  }
}

class _PrimaryButton extends StatefulWidget {
  const _PrimaryButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<_PrimaryButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 17),
          decoration: BoxDecoration(
            color: ReceiptSheetColors.gold,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: ReceiptSheetColors.ctaShadow,
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            widget.label,
            style: balooText(
              16.5,
              FontWeight.w800,
              color: ReceiptSheetColors.ctaText,
            ),
          ),
        ),
      ),
    );
  }
}
