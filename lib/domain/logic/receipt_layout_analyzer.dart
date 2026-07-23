import '../models/ocr_line.dart';
import '../models/receipt_line_zone.dart';
import 'merchant_extractor.dart';
import 'receipt_line_item_extractor.dart';
import 'rm_amount_parser.dart';

/// Kill switch while zone-boundary thresholds are tuned against real fixtures.
const receiptLayoutAnalysisEnabled = true;

/// Minimum raw line count before layout structure is inferred.
const layoutMinLineCount = 4;

/// Proportional header window: at most [merchantScanLines], at least 3 lines,
/// otherwise ~25% of the receipt.
const layoutHeaderFraction = 0.25;

/// A line whose bbox center falls within this band of image width is treated
/// as horizontally centered (typical store-name headers).
const layoutCenteredBandHalfWidth = 0.15;

/// Same large-text threshold as the merchant extractor's largeText pass.
const layoutLargeTextRatioThreshold = 1.4;

int _headerWindowEnd(int lineCount) {
  final proportional = (lineCount * layoutHeaderFraction).ceil();
  final capped = proportional.clamp(3, merchantScanLines);
  return (capped - 1).clamp(0, lineCount - 1);
}

bool _isHorizontallyCentered(OcrLine line) {
  if (line.widthRatio <= 0) return false;
  final center = line.centerXRatio;
  return (center - 0.5).abs() <= layoutCenteredBandHalfWidth;
}

bool _isLargeTextLine(OcrLine line, List<OcrLine> ocrLines) {
  final heights = ocrLines.map((l) => l.heightRatio).where((h) => h > 0).toList()
    ..sort();
  if (heights.isEmpty || line.heightRatio <= 0) return false;
  final baseline = heights[heights.length ~/ 2];
  if (baseline <= 0) return false;
  return line.heightRatio >= baseline * layoutLargeTextRatioThreshold;
}

bool _looksLikeFooterLine(String line) =>
    totalKeywordHints.hasMatch(line) || discountOrSummaryHints.hasMatch(line);

/// Classifies [ocrText] lines into header/body/footer zones using [ocrLines]
/// geometry and existing keyword/item regexes. Returns `null` when layout
/// analysis is disabled, inputs are mismatched, or structure can't be inferred
/// reliably — in that case every consumer behaves as today.
ReceiptLayoutAnalysis? analyzeReceiptLayout(
  String ocrText,
  List<OcrLine>? ocrLines,
) {
  if (!receiptLayoutAnalysisEnabled || ocrLines == null || ocrLines.isEmpty) {
    return null;
  }

  final rawLines = ocrText.split(RegExp(r'\r?\n'));
  if (rawLines.length < layoutMinLineCount) return null;
  if (ocrLines.length != rawLines.length) return null;

  final itemIndices = <int>[];
  final footerIndices = <int>[];
  for (var i = 0; i < rawLines.length; i++) {
    final trimmed = rawLines[i].trim();
    if (trimmed.length < 3) continue;
    if (looksLikeItemLine(trimmed) && !_looksLikeFooterLine(trimmed)) {
      itemIndices.add(i);
    }
    if (_looksLikeFooterLine(trimmed)) footerIndices.add(i);
  }

  if (itemIndices.isEmpty && footerIndices.isEmpty) return null;

  final bodyStart = itemIndices.isEmpty ? rawLines.length : itemIndices.first;
  final bodyEnd = itemIndices.isEmpty ? -1 : itemIndices.last;
  final headerEnd = _headerWindowEnd(rawLines.length);

  final zones = List<ReceiptLineZone>.filled(rawLines.length, ReceiptLineZone.ambiguous);

  for (var i = 0; i < rawLines.length; i++) {
    final trimmed = rawLines[i].trim();
    if (trimmed.length < 3) {
      zones[i] = ReceiptLineZone.ambiguous;
      continue;
    }

    if (itemIndices.isNotEmpty && i >= bodyStart && i <= bodyEnd) {
      if (_looksLikeFooterLine(trimmed)) {
        zones[i] = ReceiptLineZone.footer;
      } else if (looksLikeReceiptMetadata(trimmed) || looksLikeBoilerplate(trimmed)) {
        zones[i] = ReceiptLineZone.header;
      } else if (looksLikeItemLine(trimmed)) {
        zones[i] = ReceiptLineZone.body;
      } else {
        zones[i] = ReceiptLineZone.ambiguous;
      }
      continue;
    }

    if (footerIndices.isNotEmpty && i >= (bodyEnd >= 0 ? bodyEnd + 1 : 0)) {
      if (_looksLikeFooterLine(trimmed)) {
        zones[i] = ReceiptLineZone.footer;
        continue;
      }
      if (bodyEnd >= 0 && i > bodyEnd) {
        zones[i] = ReceiptLineZone.footer;
        continue;
      }
    }

    if (i <= headerEnd && (bodyStart == rawLines.length || i < bodyStart)) {
      final line = ocrLines[i];
      if (looksLikeBoilerplate(trimmed) ||
          looksLikeReceiptMetadata(trimmed) ||
          _isLargeTextLine(line, ocrLines) ||
          _isHorizontallyCentered(line)) {
        zones[i] = ReceiptLineZone.header;
        continue;
      }
      if (i <= headerEnd) {
        zones[i] = ReceiptLineZone.header;
        continue;
      }
    }

    zones[i] = ReceiptLineZone.ambiguous;
  }

  final hasBody = zones.contains(ReceiptLineZone.body);
  final hasFooter = zones.contains(ReceiptLineZone.footer);
  if (!hasBody && !hasFooter) return null;

  return ReceiptLayoutAnalysis(zones: zones, isReliable: true);
}
