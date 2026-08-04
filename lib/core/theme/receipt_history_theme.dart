import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens for the Receipt History screen, from the `Receipt
/// History.dc.html` handoff — a warm cream + near-black + gold palette and
/// the Baloo 2 typeface. A third, scoped design language alongside the
/// app-wide Plus Jakarta Sans theme (`app_typography.dart`) and the
/// receipt-sheet cream/brown palette (`receipt_sheet_theme.dart`).
abstract final class ReceiptHistoryColors {
  static const scaffold = Color(0xFFEFE7D6);
  static const card = Color(0xFFFCF6EA);
  static const ink = Color(0xFF23201A);
  static const gold = Color(0xFFF6C64B);
  static const mutedLabel = Color(0xFFB0A895);
  static const mutedText = Color(0xFF9A9284);
  static const divider = Color(0xFFEEE3CD);
  static const timelineLine = Color(0xFFE6DCC5);
  static const timelineLineNested = Color(0xFFEFE7D6);
  static const rowBorderNested = Color(0xFFF2EADB);
  static const chevronNested = Color(0xFFC9BFA5);
}

/// Layout proportions for the Receipt History handoff mock.
abstract final class ReceiptHistoryLayout {
  static const screenHPad = 20.0;
  static const summaryAspectRatio = 2.65;
  static const summaryRadius = 24.0;
  static const categoryIconSize = 36.0;
  static const timelineDotSize = 10.0;
}

/// Spend-severity color for the week progress bar and day heatmap cells, from
/// the `Receipt History Week Handoff.dc.html` handoff's `severityColor()` —
/// grey when zero, red/gold/green by share of the peak it's compared against.
Color receiptHistorySeverityColor(double pct, {required bool zero}) {
  if (zero) return const Color(0xFFE6DCC5);
  if (pct > 0.66) return const Color(0xFFC0503B);
  if (pct > 0.33) return const Color(0xFFD9922E);
  return const Color(0xFF7C9473);
}

/// Skips the Google Fonts runtime fetch in widget tests, which have no
/// network — same reason `debugReceiptSheetSystemFont` exists.
@visibleForTesting
bool debugReceiptHistorySystemFont = false;

/// Baloo 2 at the handoff's size/weight pairs.
TextStyle receiptHistoryText(
  double size,
  FontWeight weight, {
  Color color = ReceiptHistoryColors.ink,
  double? letterSpacing,
  double? height,
}) {
  if (debugReceiptHistorySystemFont) {
    return TextStyle(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }
  return GoogleFonts.baloo2(
    fontSize: size,
    fontWeight: weight,
    color: color,
    letterSpacing: letterSpacing,
    height: height,
  );
}
