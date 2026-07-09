import 'package:flutter/material.dart';

import '../core/theme/receipt_sheet_theme.dart';

/// 38×5 pill drag handle used by the receipt-flow sheets.
class ReceiptSheetHandle extends StatelessWidget {
  const ReceiptSheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 38,
        height: 5,
        decoration: BoxDecoration(
          color: ReceiptSheetColors.handle,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
}

/// Full-width gold CTA pill ("Looks good" / "Confirm location").
class ReceiptSheetCta extends StatelessWidget {
  const ReceiptSheetCta({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: enabled
              ? const [
                  BoxShadow(
                    color: ReceiptSheetColors.ctaShadow,
                    blurRadius: 22,
                    offset: Offset(0, 10),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: ReceiptSheetColors.gold,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              padding: const EdgeInsets.all(16),
              alignment: Alignment.center,
              child: Text(
                label,
                style: balooText(
                  16,
                  FontWeight.w800,
                  color: ReceiptSheetColors.ctaText,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Centered text link below the CTA ("Edit details" / "Cancel").
class ReceiptSheetLink extends StatelessWidget {
  const ReceiptSheetLink({
    super.key,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: Text(label, style: balooText(15, FontWeight.w700, color: color)),
        ),
      ),
    );
  }
}
