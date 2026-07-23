import 'dart:math' as math;

import '../../domain/logic/bank_receipt_parser.dart';
import '../../domain/logic/category_matcher.dart';
import '../../domain/logic/impact_level.dart';
import '../../domain/logic/merchant_extractor.dart';
import '../../domain/logic/receipt_layout_analyzer.dart';
import '../../domain/logic/receipt_line_item_extractor.dart';
import '../../domain/logic/rm_amount_parser.dart';
import '../../domain/models/ocr_line.dart';
import '../../domain/models/receipt_line_item.dart';
import '../../domain/models/receipt_understanding.dart';

/// Maps the LLM's closed `vendor_category` vocabulary (see
/// `services/ocr-api/app/receipt_understanding.py`'s `VENDOR_CATEGORIES`) to
/// this app's display-category strings (`assets/config/categories-v1.json`).
/// `entertainment`/`services`/`other` and anything unrecognized have no
/// display-category equivalent today and fall back to
/// [CategoryConfig.defaultCategory].
const vendorCategoryToDisplayCategory = {
  'food_and_drink': 'Food & Drink',
  'groceries': 'Groceries',
  'transport': 'Transport',
  'travel': 'Travel',
  'shopping': 'Shopping',
  'health_beauty': 'Health & Beauty',
};

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
    this.merchantCandidates = const [],
    this.ocrHeaderText,
    this.understanding,
    this.understandingError,
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

  /// Ranked merchant-name guesses (see [MerchantCandidate]); [merchantRaw] is
  /// always the top entry's text, kept for backward compatibility.
  final List<MerchantCandidate> merchantCandidates;

  /// Extra OCR context (top-of-receipt lines) synced alongside
  /// [merchantCandidates] so Places enrichment can try more than one query.
  final String? ocrHeaderText;

  /// The LLM's structured interpretation of this receipt, produced
  /// synchronously alongside OCR (see `ocr_pipeline_io.dart`). `null` when
  /// OCR found no text or the LLM call itself failed — see
  /// [understandingError]. [merchantRaw]/[categoryGuess]/[lineItems] above
  /// already prefer this over the heuristic extraction when present; it's
  /// also kept here for downstream use (place-picker prefill from
  /// `addressText`/`locationClues`/`googlePlaceTypes`).
  final ReceiptUnderstanding? understanding;

  /// Machine-readable LLM failure code (e.g. `llm_timeout`) when
  /// [understanding] is `null` but OCR itself succeeded.
  final String? understandingError;

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
      'merchantCandidates':
          merchantCandidates.map((c) => c.toJson()).toList(),
      if (ocrHeaderText != null) 'ocrHeaderText': ocrHeaderText,
      if (understanding != null) 'understanding': understanding!.toJson(),
      if (understandingError != null) 'understandingError': understandingError,
    };
  }

  static String _basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    final slash = normalized.lastIndexOf('/');
    return slash >= 0 ? normalized.substring(slash + 1) : normalized;
  }
}

/// Applies amount, merchant, and category heuristics to raw OCR text, then
/// lets the synchronous LLM [understanding] (if any) override the
/// merchant/category/line-items it's confident about — see
/// `docs/decisions.md` for why this now runs in the same request as OCR
/// instead of as a later async enrichment step.
ReceiptParseResult parseReceiptOcrText({
  required String filePath,
  required String ocrText,
  required CategoryConfig categories,
  double? ocrServiceConfidence,
  List<OcrLine>? ocrLines,
  ReceiptUnderstanding? understanding,
  String? understandingError,
}) {
  // Prefer the LLM OCR-cleanup step's corrected transcript as the heuristic
  // extractors' input whenever it's present (opt-in server-side via
  // LLM_CLEANUP_ENABLED — usually absent). This is purely a better *input*
  // to the same heuristics below; it never changes precedence between the
  // heuristic pass and the LLM's own structured fields, and — critically —
  // `ReceiptParseResult.ocrText` below stays the true OCR-original text:
  // that field is persisted as `raw_ocr_text` and must never be replaced
  // with a corrected rewrite (see docs/system/decisions.md).
  final cleanedOcrText = understanding?.cleanedOcrText;
  final heuristicText =
      (cleanedOcrText != null && cleanedOcrText.isNotEmpty) ? cleanedOcrText : ocrText;

  // extractMerchantCandidates() additionally needs each line's height_ratio,
  // which the cleaned text (a flat string) doesn't carry — pair cleaned
  // line text with the *original* per-line height_ratio by position instead
  // (cleaned_lines is always the same length/order as the lines actually
  // sent for cleanup — see ocr_api/receipt_understanding.py). Falls back to
  // the original ocrLines untouched if the lengths don't line up.
  final cleanedLines = understanding?.cleanedLines;
  final heuristicOcrLines =
      (cleanedLines != null && ocrLines != null && cleanedLines.length == ocrLines.length)
          ? [
              for (var i = 0; i < cleanedLines.length; i++)
                OcrLine(
                  text: cleanedLines[i],
                  heightRatio: ocrLines[i].heightRatio,
                  leftRatio: ocrLines[i].leftRatio,
                  topRatio: ocrLines[i].topRatio,
                  widthRatio: ocrLines[i].widthRatio,
                ),
            ]
          : ocrLines;

  final layout = analyzeReceiptLayout(heuristicText, heuristicOcrLines);

  // Fast path: known bank/wallet providers have templated, labeled-field output
  // that regex can read reliably. Heuristic amount stays authoritative here,
  // but pass understanding through so receipt_type/payment_method/etc. are
  // available to downstream consumers.
  final bankParse = tryParseBankReceipt(heuristicText);
  if (bankParse != null) {
    return ReceiptParseResult(
      filePath: filePath,
      ocrText: ocrText,
      amountMyr: bankParse.amountMyr,
      needsAmount: false,
      ocrConfidence: 0.92,
      merchantRaw: bankParse.merchantRaw,
      categoryGuess: bankParse.category,
      categoryConfidence: 0.90,
      impactLevel: deriveImpactLevel(bankParse.amountMyr).storageValue,
      amountSource: AmountParseSource.rmPrefixed.name,
      merchantCandidates: [
        MerchantCandidate(
          text: bankParse.merchantRaw,
          confidence: 0.92,
          source: 'bankParser',
        ),
      ],
      // No line items — bank screenshots never have itemized lists.
      // ocrHeaderText: null — not a physical merchant; skip Places enrichment.
      understanding: understanding,
      understandingError: understandingError,
    );
  }

  // The heuristic pass always runs first: its line-item subtotal feeds the
  // amount-parsing cross-check below regardless of the LLM's own extraction,
  // and it's the fallback whenever the LLM found nothing or failed outright.
  final extracted = extractReceiptLineItems(heuristicText, layout: layout);
  final largestItemPrice = extracted.items.isEmpty
      ? null
      : extracted.items
          .map((it) => it.priceMyr)
          .reduce((a, b) => a > b ? a : b);

  final parseResult = parseRmAmountFromOcr(
    heuristicText,
    itemsSubtotalMyr: extracted.itemsSubtotalMyr,
    largestItemPriceMyr: largestItemPrice,
    lineItemCount: extracted.items.length,
    layout: layout,
  );
  // For payment and transport receipts the LLM skill extracts the actual
  // transaction amount (distinguishing it from account balance / surcharges).
  // Prefer that over the heuristic when available.
  final _receiptType = understanding?.receiptType;
  final amount = (_receiptType == 'payment' || _receiptType == 'transport')
      ? (understanding?.amount ?? parseResult.amount)
      : parseResult.amount;
  final heuristicLineItems = reconcileWithTotal(extracted, amount);

  // LLM items are the source of truth whenever the LLM extracted any — the
  // understanding call already completed synchronously with OCR, before this
  // function (and the first local save) ever runs, so there's no dedup/
  // insert-order conflict with the heuristic pass above.
  final llmLineItems = _lineItemsFromUnderstanding(understanding, amount);
  final lineItemsResult = llmLineItems == null
      ? heuristicLineItems
      : reconcileWithTotal(llmLineItems, amount);

  final heuristicMerchantCandidates = extractMerchantCandidates(
    heuristicText,
    categories,
    ocrLines: heuristicOcrLines,
    layout: layout,
  );
  final llmMerchantName = understanding?.merchantName;
  final merchantCandidates = llmMerchantName == null
      ? heuristicMerchantCandidates
      : [
          MerchantCandidate(
            text: llmMerchantName,
            confidence: understanding!.confidence.merchant,
            source: 'llm',
          ),
          ...heuristicMerchantCandidates,
        ];
  final merchantRaw =
      merchantCandidates.isEmpty ? null : merchantCandidates.first.text;
  final headerText = extractOcrHeaderText(heuristicText);

  final llmCategory = understanding?.vendorCategory;
  final String categoryGuess;
  final double categoryConfidence;
  if (llmCategory != null) {
    categoryGuess =
        vendorCategoryToDisplayCategory[llmCategory] ?? categories.defaultCategory;
    categoryConfidence = understanding!.confidence.category;
  } else {
    final (:category, :confidence) =
        categories.guessWithConfidence(merchantRaw ?? '', heuristicText);
    categoryGuess = category;
    categoryConfidence = confidence;
  }

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
    merchantCandidates: merchantCandidates,
    ocrHeaderText: headerText.isEmpty ? null : headerText,
    understanding: understanding,
    understandingError: understandingError,
  );
}

/// Converts the LLM's line items into a [ReceiptLineItemsResult] ready for
/// [reconcileWithTotal], or `null` when there's nothing usable (no
/// [understanding], or every item lacked a usable price). Entries without a
/// price are dropped — [ReceiptLineItem.priceMyr] is required, and a
/// nameless price row isn't useful to show the user either. Entries priced
/// above [amount] are also dropped: a single line item can never
/// legitimately cost more than the receipt's own total, so this catches LLM
/// digit-transcription hallucinations (e.g. a printed "3.00" misread as
/// "93.00") without discarding the rest of an otherwise-good extraction —
/// see docs/decisions.md.
ReceiptLineItemsResult? _lineItemsFromUnderstanding(
  ReceiptUnderstanding? understanding,
  double? amount,
) {
  if (understanding == null || understanding.lineItems.isEmpty) return null;

  final items = [
    for (final it in understanding.lineItems)
      if (it.price != null && (amount == null || it.price! <= amount))
        ReceiptLineItem(
          name: it.name,
          priceMyr: it.price!,
          quantity: it.quantity?.round(),
          confidence: understanding.confidence.lineItems,
        ),
  ].take(maxExtractedLineItems).toList();

  if (items.isEmpty) return null;

  final subtotal = items.fold<double>(0, (sum, it) => sum + it.priceMyr);
  return ReceiptLineItemsResult(
    items: items,
    confidence: understanding.confidence.lineItems,
    itemsSubtotalMyr: subtotal,
    itemsMatchTotal: false,
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
