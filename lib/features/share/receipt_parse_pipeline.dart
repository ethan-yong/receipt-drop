import '../../domain/logic/category_matcher.dart';
import '../../domain/logic/impact_level.dart';
import '../../domain/logic/merchant_extractor.dart';
import '../../domain/logic/receipt_line_item_extractor.dart';
import '../../domain/logic/rm_amount_parser.dart';
import '../../domain/models/receipt_line_item.dart';

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
    this.ocrServiceConfidence,
    this.lineItems = const [],
    this.lineItemsConfidence = 0.0,
    this.itemsSubtotalMyr,
    this.itemsMatchTotal = false,
  });

  final String filePath;
  final String ocrText;
  final double? amountMyr;
  final bool needsAmount;
  final double ocrConfidence;
  final String? merchantRaw;
  final String categoryGuess;
  final String impactLevel;
  final double? ocrServiceConfidence;
  final List<ReceiptLineItem> lineItems;
  final double lineItemsConfidence;
  final double? itemsSubtotalMyr;
  final bool itemsMatchTotal;

  bool get lowConfidence =>
      !needsAmount && ocrConfidence < lowOcrConfidenceThreshold;

  Map<String, dynamic> toJson({bool includeOcrText = false}) {
    return {
      'file': _basename(filePath),
      if (includeOcrText) 'ocrText': ocrText,
      'amountMyr': amountMyr,
      'needsAmount': needsAmount,
      'ocrConfidence': ocrConfidence,
      'merchantRaw': merchantRaw,
      'categoryGuess': categoryGuess,
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
  final parseResult = parseRmAmountFromOcr(ocrText);
  final amount = parseResult.amount;
  final merchantRaw = extractMerchant(ocrText, categories);
  final categoryGuess =
      categories.guessForMerchant(merchantRaw ?? '').category;
  final lineItemsResult = extractReceiptLineItems(ocrText, totalMyr: amount);

  return ReceiptParseResult(
    filePath: filePath,
    ocrText: ocrText,
    amountMyr: amount,
    needsAmount: amount == null,
    ocrConfidence: parseResult.confidence,
    merchantRaw: merchantRaw,
    categoryGuess: categoryGuess,
    impactLevel: deriveImpactLevel(amount).storageValue,
    ocrServiceConfidence: ocrServiceConfidence,
    lineItems: lineItemsResult.items,
    lineItemsConfidence: lineItemsResult.confidence,
    itemsSubtotalMyr: lineItemsResult.itemsSubtotalMyr,
    itemsMatchTotal: lineItemsResult.itemsMatchTotal,
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
