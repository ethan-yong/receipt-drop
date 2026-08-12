import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/platform/platform_feedback.dart';
import '../../core/theme/receipt_sheet_theme.dart';
import '../../domain/models/transaction_view.dart';
import '../bill_split/bill_split_sheet.dart';

/// Full-screen route shown right after a single receipt is saved — sits
/// between the pigeon `SaveSuccessScreen` and Home, making "Split this bill"
/// one tap away instead of buried in a reopened receipt. Close returns to
/// Home. From the Claude Design handoff "Receipt Saved Screen.dc.html".
class ReceiptSavedScreen extends StatefulWidget {
  const ReceiptSavedScreen({super.key, required this.receipt});

  final TransactionView receipt;

  @override
  State<ReceiptSavedScreen> createState() => _ReceiptSavedScreenState();
}

class _ReceiptSavedScreenState extends State<ReceiptSavedScreen>
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

  void _close() => context.goNamed('home');

  void _split() {
    PlatformFeedback.lightTap();
    BillSplitSheet.show(context, transactionId: widget.receipt.id);
  }

  void _viewReceipt() {
    // Replace this screen so system/app-bar back from detail lands on Home,
    // not back on the post-save celebration.
    context.goNamed('tx-detail', pathParameters: {'id': widget.receipt.id});
  }

  String get _merchant => widget.receipt.displayPlace;

  String get _total => 'RM ${(widget.receipt.amountMyr ?? 0).toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ReceiptSheetColors.screenBackground,
      body: SafeArea(
        child: Semantics(
          liveRegion: true,
          label: 'Receipt saved, $_total at $_merchant',
          child: Column(
            children: [
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 10, 20, 0),
                  child: _CloseButton(onTap: _close),
                ),
              ),
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
                        child: const _SavedPill(),
                      ),
                      const SizedBox(height: 16),
                      AnimatedBuilder(
                        animation: _card,
                        builder: (context, child) => Opacity(
                          opacity: _card.value.clamp(0.0, 1.0),
                          child: Transform.translate(
                            offset: Offset(0, 14 * (1 - _card.value.clamp(0.0, 1.0))),
                            child: child,
                          ),
                        ),
                        child: _ReceiptSummaryCard(receipt: widget.receipt),
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
                    offset: Offset(0, 14 * (1 - _footer.value.clamp(0.0, 1.0))),
                    child: child,
                  ),
                ),
                child: _ActionFooter(onSplit: _split, onViewReceipt: _viewReceipt),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Close',
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 32,
          height: 32,
          decoration: const BoxDecoration(
            color: ReceiptSheetColors.tile,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.close, size: 16, color: ReceiptSheetColors.sub),
        ),
      ),
    );
  }
}

/// Green "Receipt saved!" pill — same check-in-circle motif as the pigeon
/// animation's `_SavedBadge`, but this screen's own copy: different label,
/// and a smaller pill (14px text / 16px icon) per the handoff spec.
class _SavedPill extends StatelessWidget {
  const _SavedPill();

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
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: const Icon(Icons.check, color: Color(0xFF5E9E51), size: 9),
          ),
          const SizedBox(width: 8),
          Text('Receipt saved!', style: balooText(14, FontWeight.w800, color: Colors.white)),
        ],
      ),
    );
  }
}

class _ReceiptSummaryCard extends StatelessWidget {
  const _ReceiptSummaryCard({required this.receipt});

  final TransactionView receipt;

  String get _merchant => receipt.displayPlace;

  String get _merchantInitial {
    final trimmed = _merchant.trim();
    return trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
  }

  String get _total => 'RM ${(receipt.amountMyr ?? 0).toStringAsFixed(2)}';

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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                  color: ReceiptSheetColors.avatarGold,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  _merchantInitial,
                  style: balooText(17, FontWeight.w800, color: Colors.white),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _merchant,
                      style: balooText(
                        17,
                        FontWeight.w800,
                        color: ReceiptSheetColors.ink,
                        letterSpacing: -0.2,
                        height: 1.25,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      'Saved just now',
                      style: balooText(12.5, FontWeight.w600, color: ReceiptSheetColors.sub),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(
              _total,
              style: balooText(
                30,
                FontWeight.w800,
                color: ReceiptSheetColors.ink,
                letterSpacing: -0.4,
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 15),
            child: _DashedDivider(),
          ),
          _LocationPreview(receipt: receipt),
        ],
      ),
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

const _locationPreviewHeight = 118.0;

class _LocationPreview extends StatelessWidget {
  const _LocationPreview({required this.receipt});

  final TransactionView receipt;

  @override
  Widget build(BuildContext context) {
    final lat = receipt.placeLat;
    final lng = receipt.placeLng;
    if (lat == null || lng == null) return const _LocationFallback();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            height: _locationPreviewHeight,
            width: double.infinity,
            // Decorative, non-interactive: gesture-disabled GoogleMap, same
            // convention as _MapPreview in receipt_confirm_sheet.dart.
            child: IgnorePointer(
              child: GoogleMap(
                key: ValueKey('receipt-saved-map-$lat-$lng'),
                initialCameraPosition: CameraPosition(target: LatLng(lat, lng), zoom: 15),
                markers: {
                  Marker(markerId: const MarkerId('place'), position: LatLng(lat, lng)),
                },
                zoomControlsEnabled: false,
                zoomGesturesEnabled: false,
                scrollGesturesEnabled: false,
                rotateGesturesEnabled: false,
                tiltGesturesEnabled: false,
                myLocationButtonEnabled: false,
                mapToolbarEnabled: false,
                compassEnabled: false,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(
            children: [
              const Icon(Icons.location_on, size: 13, color: Color(0xFFE2885C)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  receipt.placeName ?? receipt.displayPlace,
                  style: balooText(13.5, FontWeight.w800, color: ReceiptSheetColors.ink),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LocationFallback extends StatelessWidget {
  const _LocationFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: _locationPreviewHeight,
      decoration: BoxDecoration(
        color: ReceiptSheetColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ReceiptSheetColors.checkboxBorder, width: 2),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(color: ReceiptSheetColors.tile, shape: BoxShape.circle),
            child: const Icon(
              Icons.location_off_outlined,
              size: 16,
              color: ReceiptSheetColors.subLight,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Location not detected',
            style: balooText(13, FontWeight.w800, color: ReceiptSheetColors.sub),
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'You can add it from the receipt later',
              textAlign: TextAlign.center,
              style: balooText(11.5, FontWeight.w600, color: ReceiptSheetColors.subLight),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionFooter extends StatelessWidget {
  const _ActionFooter({required this.onSplit, required this.onViewReceipt});

  final VoidCallback onSplit;
  final VoidCallback onViewReceipt;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          _PrimaryButton(label: 'Split this bill', onTap: onSplit),
          GestureDetector(
            onTap: onViewReceipt,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Text(
                  'View receipt',
                  style: balooText(15, FontWeight.w700, color: ReceiptSheetColors.sub),
                ),
              ),
            ),
          ),
        ],
      ),
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
            style: balooText(16.5, FontWeight.w800, color: ReceiptSheetColors.ctaText),
          ),
        ),
      ),
    );
  }
}
