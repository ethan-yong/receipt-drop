import 'dart:math' as math;

import '../../domain/logic/category_matcher.dart';
import '../../domain/logic/impact_level.dart';
import '../../domain/logic/merchant_extractor.dart';
import '../../domain/logic/receipt_line_item_extractor.dart';
import '../../domain/logic/rm_amount_parser.dart';
import '../../domain/models/receipt_line_item.dart';

/// Weights for blending extraction confidence with scan quality in
/// [ReceiptParseResult.combinedConfidence]. The OCR service already sigmoid-
/// calibrates its mean word confidence before returning it, so the scan value
/// is used as-is here; expect to tune these weights against batch runs.
const combinedExtractionWeight = 0.6;
const combinedScanWeight = 0.4;

/// A good parse can't lift the combined score more than this above the scan
/// quality — a confident regex match on a barely-readable image is still a
/// guess.
const combinedScanCeilingMargin = 0.25;

/// Parsed fields from a receipt image or OCR text (before user confirmation).
class ReceiptParseResult {
  const ReceiptParseResult({
    required this.filePath,
    required this.ocrText,
    required this.amountMyr,
    required this.needsAmount,
    required this.ocrConfidence,
    required this.merchantRaw,
    required this.categoryGuess,
    required this.impactLevel,
    this.categoryConfidence = 0.0,
    this.ocrServiceConfidence,
    this.lineItems = const [],
    this.lineItemsConfidence = 0.0,
    this.itemsSubtotalMyr,
    this.itemsMatchTotal = false,
    this.amountSource = 'none',
    this.parseFailureReason,
  });

  final String filePath;
  final String ocrText;
  final double? amountMyr;
  final bool needsAmount;

  /// Extraction confidence: how sure the *parser* is that it picked the right
  /// paid amount. Distinct from [ocrServiceConfidence] (scan quality).
  final double ocrConfidence;

  final String? merchantRaw;
  final String categoryGuess;

  /// How confident the category guesser is: 0.85 (merchant-name hit),
  /// 0.55 (OCR-body fallback), 0.10 (default).
  final double categoryConfidence;
  final String impactLevel;

  /// Scan quality: the OCR engine's mean word confidence, already sigmoid-
  /// calibrated by the service (`_calibrate_confidence` in ocr_engine.py).
  /// Says nothing about whether the right fields were extracted.
  final double? ocrServiceConfidence;

  final List<ReceiptLineItem> lineItems;
  final double lineItemsConfidence;
  final double? itemsSubtotalMyr;
  final bool itemsMatchTotal;

  /// [AmountParseSource] name: how the amount was found.
  final String amountSource;

  /// Machine-readable reason when parsing failed outright (e.g.
  /// 'no_amount_pattern'). A failure is a failure — not a confidence score.
  final String? parseFailureReason;

  /// Blend of extraction confidence and scan quality, min-gated so a bad scan
  /// caps the ceiling regardless of how clean the parse looked.
  ///
  /// [ocrServiceConfidence] arrives already sigmoid-calibrated by the OCR
  /// service and must NOT be re-squashed here: applying the same sigmoid twice
  /// mapped a 0.34 scan to 0.036, capping the combined score at ~0.29 and
  /// flagging every receipt for review no matter how clean the parse was.
  double get combinedConfidence {
    if (needsAmount) return 0.0;
    final scan = ocrServiceConfidence;
    if (scan == null) return ocrConfidence;
    final blend = combinedExtractionWeight * ocrConfidence +
        combinedScanWeight * scan;
    return math.min(blend, scan + combinedScanCeilingMargin).clamp(0.0, 1.0);
  }

  bool get lowConfidence =>
      !needsAmount &&
      (combinedConfidence < lowOcrConfidenceThreshold ||
          amountSource == AmountParseSource.totalKeywordFallback.name);

  Map<String, dynamic> toJson({bool includeOcrText = false}) {
    return {
      'file': _basename(filePath),
      if (includeOcrText) 'ocrText': ocrText,
      'amountMyr': amountMyr,
      'needsAmount': needsAmount,
      'ocrConfidence': ocrConfidence,
      'combinedConfidence': combinedConfidence,
      'amountSource': amountSource,
      if (parseFailureReason != null) 'parseFailureReason': parseFailureReason,
      'merchantRaw': merchantRaw,
      'categoryGuess': categoryGuess,
      'categoryConfidence': categoryConfidence,
      'impactLevel': impactLevel,
      'lowConfidence': lowConfidence,
      'lineItems': lineItems.map((it) => it.toJson()).toList(),
      'lineItemsConfidence': lineItemsConfidence,
      'itemsSubtotalMyr': itemsSubtotalMyr,
      'itemsMatchTotal': itemsMatchTotal,
      if (ocrServiceConfidence != null)
        'ocrServiceConfidence': ocrServiceConfidence,
    };
  }

  static String _basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    final slash = normalized.lastIndexOf('/');
    return slash >= 0 ? normalized.substring(slash + 1) : normalized;
  }
}

/// Applies amount, merchant, and category heuristics to raw OCR text.
ReceiptParseResult parseReceiptOcrText({
  required String filePath,
  required String ocrText,
  required CategoryConfig categories,
  double? ocrServiceConfidence,
}) {
  // Items are extracted before the amount so their subtotal can vote on
  // which amount candidate is the real paid total (semantic cross-check),
  // then reconciled against whichever total won.
  final extracted = extractReceiptLineItems(ocrText);
  final largestItemPrice = extracted.items.isEmpty
      ? null
      : extracted.items
          .map((it) => it.priceMyr)
          .reduce((a, b) => a > b ? a : b);

  final parseResult = parseRmAmountFromOcr(
    ocrText,
    itemsSubtotalMyr: extracted.itemsSubtotalMyr,
    largestItemPriceMyr: largestItemPrice,
    lineItemCount: extracted.items.length,
  );
  final amount = parseResult.amount;
  final lineItemsResult = reconcileWithTotal(extracted, amount);

  final merchantRaw = extractMerchant(ocrText, categories);
  final (:category, :confidence) =
      categories.guessWithConfidence(merchantRaw ?? '', ocrText);
  final categoryGuess = category;
  final categoryConfidence = confidence;

  return ReceiptParseResult(
    filePath: filePath,
    ocrText: ocrText,
    amountMyr: amount,
    needsAmount: amount == null,
    ocrConfidence: parseResult.confidence,
    merchantRaw: merchantRaw,
    categoryGuess: categoryGuess,
    categoryConfidence: categoryConfidence,
    impactLevel: deriveImpactLevel(amount).storageValue,
    ocrServiceConfidence: ocrServiceConfidence,
    lineItems: lineItemsResult.items,
    lineItemsConfidence: lineItemsResult.confidence,
    itemsSubtotalMyr: lineItemsResult.itemsSubtotalMyr,
    itemsMatchTotal: lineItemsResult.itemsMatchTotal,
    amountSource: parseResult.source.name,
    parseFailureReason: parseResult.failureReason,
  );
}

/// Supported receipt file extensions for batch processing.
const receiptBatchExtensions = {
  '.png',
  '.jpg',
  '.jpeg',
  '.webp',
  '.pdf',
};

/// Infers MIME type from a file path extension.
String mimeFromPath(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.pdf')) return 'application/pdf';
  if (lower.endsWith('.jpeg') || lower.endsWith('.jpg')) return 'image/jpeg';
  return 'image/jpeg';
}
