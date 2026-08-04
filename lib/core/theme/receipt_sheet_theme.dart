import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens for the receipt-flow sheets (receipt confirmation sheet and
/// restaurant location picker), from the handoff bundle in
/// `docs/design/design_handoff_receipt_flows/`.
///
/// These two screens use their own warm cream + gold palette and the Baloo 2
/// typeface, per the high-fidelity handoff — distinct from the app-wide
/// Plus Jakarta Sans theme in `app_typography.dart`.
abstract final class ReceiptSheetColors {
  static const background = Color(0xFFFAF3E7);
  static const surface = Color(0xFFFFFDF8);
  static const ink = Color(0xFF4F2D23);
  static const error = Color(0xFFB4483B);
  static const body = Color(0xFF5A4632);
  static const sub = Color(0xFF9C8A72);
  static const subLight = Color(0xFFB0A48D);
  static const tile = Color(0xFFF4E8D6);
  static const gold = Color(0xFFF5C242);
  static const avatarGold = Color(0xFFF0AA2A);
  static const ctaText = Color(0xFF5A3E0A);
  static const link = Color(0xFFD89B1F);
  static const linkStrong = Color(0xFFC4841C);
  static const handle = Color(0xFFE9DDC8);
  static const checkboxBorder = Color(0xFFE4D8C2);
  static const selectedTint = Color(0xFFFBF0D7);
  static const rowBorder = Color(0xFFF0E6D4);
  static const pinNeutral = Color(0xFFC9BB9E);
  static const distanceSelected = Color(0xFFB8860F);
  static const youAreHere = Color(0xFF3B82D6);

  /// `rgba(79,45,35,.2)` — the dashed divider stroke.
  static const dashedDivider = Color(0x334F2D23);

  /// `rgba(197,142,20,.35)` — soft glow under the gold CTA.
  static const ctaShadow = Color(0x59C58E14);

  /// `rgba(60,40,20,.16)` — shadow above the pull-up sheet.
  static const sheetShadow = Color(0x293C2814);
}

/// Top corner radius shared by both sheets.
const double kReceiptSheetRadius = 28;

/// Skips the Google Fonts runtime fetch in widget tests, which have no
/// network — same reason `buildReceiptDropTestTheme` exists.
@visibleForTesting
bool debugReceiptSheetSystemFont = false;

/// Baloo 2 at the handoff's size/weight pairs.
TextStyle balooText(
  double size,
  FontWeight weight, {
  Color color = ReceiptSheetColors.body,
  double? letterSpacing,
  TextDecoration? decoration,
  double? height,
}) {
  if (debugReceiptSheetSystemFont) {
    return TextStyle(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
      decoration: decoration,
      height: height,
    );
  }
  return GoogleFonts.baloo2(
    fontSize: size,
    fontWeight: weight,
    color: color,
    letterSpacing: letterSpacing,
    decoration: decoration,
    height: height,
  );
}
