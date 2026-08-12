import 'package:flutter/material.dart';

import 'receipt_sheet_theme.dart';

export 'receipt_sheet_theme.dart' show balooText, kReceiptSheetRadius;

/// Design tokens for the Receipt Map Sheet (map pin-tap detail), from the
/// Claude Design handoff ("Receipt Map Sheet.dc.html").
///
/// Re-exports [ReceiptSheetColors] entries that are exact matches to this
/// design (the same warm cream + gold, Baloo 2 aesthetic as the receipt-flow
/// sheets and Bill Split) rather than duplicating the hex constants, and adds
/// only what's missing: the pin/CTA orange, which has no existing token.
abstract final class MapSheetColors {
  static const pinAccent = Color(0xFFE2885C);

  static const surface = ReceiptSheetColors.surface;
  static const ink = ReceiptSheetColors.ink;
  static const heading = ReceiptSheetColors.heading;
  static const body = ReceiptSheetColors.body;
  static const sub = ReceiptSheetColors.sub;
  static const subLight = ReceiptSheetColors.subLight;
  static const tile = ReceiptSheetColors.tile;
  static const handle = ReceiptSheetColors.handle;
  static const dashedDivider = ReceiptSheetColors.dashedDivider;
  static const sheetShadow = ReceiptSheetColors.sheetShadow;
}
