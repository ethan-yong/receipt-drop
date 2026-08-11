import 'package:flutter/material.dart';

import 'receipt_sheet_theme.dart';

export 'receipt_sheet_theme.dart' show balooText, kReceiptSheetRadius;

/// Design tokens for the Bill Split flow, from the Claude Design handoff
/// ("Bill Split Flow.dc.html").
///
/// Re-exports [ReceiptSheetColors] entries that are exact matches to this
/// design (gold/ink/tile/etc. — the handoff shares the same warm cream +
/// gold, Baloo 2 aesthetic as the receipt-flow sheets) rather than
/// duplicating the hex constants, and adds only what's missing: the page
/// background and the two "paid" greens, which have no existing token.
abstract final class BillSplitColors {
  static const background = Color(0xFFEDE4D3);
  static const paidBg = Color(0xFFE3F0DC);
  static const paidText = Color(0xFF3F7A34);
  static const progressFill = Color(0xFF5E9E51);

  static const surface = ReceiptSheetColors.surface;
  static const ink = ReceiptSheetColors.ink;
  static const body = ReceiptSheetColors.body;
  static const sub = ReceiptSheetColors.sub;
  static const subLight = ReceiptSheetColors.subLight;
  static const tile = ReceiptSheetColors.tile;
  static const gold = ReceiptSheetColors.gold;
  static const ctaText = ReceiptSheetColors.ctaText;
  static const ctaShadow = ReceiptSheetColors.ctaShadow;
  static const checkboxBorder = ReceiptSheetColors.checkboxBorder;
}
