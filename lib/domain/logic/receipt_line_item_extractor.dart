import '../models/receipt_line_item.dart';
import 'merchant_extractor.dart' show looksLikeBoilerplate, numericOrPunctuationOnly;
import 'rm_amount_parser.dart'
    show
        discountOrSummaryHints,
        itemsSubtotalExactToleranceMyr,
        itemsSubtotalTaxServiceAllowanceFraction,
        totalKeywordHints;

export 'rm_amount_parser.dart'
    show itemsSubtotalExactToleranceMyr, itemsSubtotalTaxServiceAllowanceFraction;

class ReceiptLineItemsResult {
  const ReceiptLineItemsResult({
    required this.items,
    required this.confidence,
    required this.itemsSubtotalMyr,
    required this.itemsMatchTotal,
  });

  final List<ReceiptLineItem> items;
  final double confidence;
  final double? itemsSubtotalMyr;
  final bool itemsMatchTotal;
}

const maxExtractedLineItems = 30;

const _qtyPatternConfidence = 0.90;
const _rmPatternConfidence = 0.85;
const _barePatternConfidence = 0.55;

/// Summary-row wording not already covered by [discountOrSummaryHints] /
/// [totalKeywordHints] (those two are tuned for *picking the paid total*,
/// not for *rejecting non-item rows*).
final _extraSummaryLineHints = RegExp(
  r'(service charge|svc chg|rounding|round adj|\bgst\b|\bsst\b|'
  r'no\.?\s*of items?|qty\s*:|item\(s\))',
  caseSensitive: false,
);

// Malaysian SST/GST tax codes printed after the price, e.g. "2.50 SR",
// "7.00 -Z" (Z = zero-rated on mamak/kopitiam receipts). Non-capturing so the
// price group numbers below stay stable; alternation is longest-first so
// e.g. ZRL wins over ZR/Z instead of leaving unmatched trailing chars.
const _taxCodeSuffix = r'(?:\s*-?\s*(?:ZRL|SR|ZR|OS|RS|GS|AJS|Z|S|E)\b\.?)?';

// 1st: quantity-prefixed item, e.g. "2 x Kopi O   RM 6.00". Tried before the
// plain RM pattern below, otherwise that pattern's lazy `.+?` would swallow
// "2 x Kopi O" as the whole item name instead of splitting out the quantity.
final _qtyItemRegex = RegExp(
  r'^(\d+)\s*x\s*(.+?)\s+RM\s*([\d,]+\.\d{2})' + _taxCodeSuffix + r'\s*$',
  caseSensitive: false,
);

// 2nd: plain "name  RM price" (most common). Tried before the bare-price
// pattern below, otherwise that pattern would capture the literal word "RM"
// into the name (nothing anchors it to stop before "RM").
final _rmItemRegex = RegExp(
  r'^(.+?)\s+RM\s*([\d,]+\.\d{2})' + _taxCodeSuffix + r'\s*$',
  caseSensitive: false,
);

// 3rd: no "RM" token at all, e.g. "Broccoli   4.20" — lower confidence, only
// reached when a line has no RM-prefixed price for the patterns above to match.
final _bareItemRegex = RegExp(
  r'^(.+?)\s+([\d,]+\.\d{2})' + _taxCodeSuffix + r'\s*$',
  caseSensitive: false,
);

bool _isValidName(String name) {
  final trimmed = name.trim();
  if (trimmed.length < 2) return false;
  if (numericOrPunctuationOnly.hasMatch(trimmed)) return false;
  return true;
}

double _lineConfidence(double base, String name, double price) {
  var score = base;
  if (name.length < 3) score -= 0.20;
  if (name.length > 40) score -= 0.10;
  if (price > 500) score -= 0.10;
  if (price < 0.10) score -= 0.15;
  return score.clamp(0.05, 0.98);
}

({String name, double price, int? quantity, double confidence})?
    _tryParseItemLine(String line) {
  final qty = _qtyItemRegex.firstMatch(line);
  if (qty != null) {
    final name = qty.group(2)!.trim();
    final price = double.tryParse(qty.group(3)!.replaceAll(',', ''));
    if (price != null && _isValidName(name)) {
      return (
        name: name,
        price: price,
        quantity: int.tryParse(qty.group(1)!),
        confidence: _lineConfidence(_qtyPatternConfidence, name, price),
      );
    }
  }

  final rm = _rmItemRegex.firstMatch(line);
  if (rm != null) {
    final name = rm.group(1)!.trim();
    final price = double.tryParse(rm.group(2)!.replaceAll(',', ''));
    if (price != null && _isValidName(name)) {
      return (
        name: name,
        price: price,
        quantity: null,
        confidence: _lineConfidence(_rmPatternConfidence, name, price),
      );
    }
  }

  final bare = _bareItemRegex.firstMatch(line);
  if (bare != null) {
    final name = bare.group(1)!.trim();
    final price = double.tryParse(bare.group(2)!.replaceAll(',', ''));
    if (price != null && _isValidName(name)) {
      return (
        name: name,
        price: price,
        quantity: null,
        confidence: _lineConfidence(_barePatternConfidence, name, price),
      );
    }
  }

  return null;
}

/// Extracts item + price rows from raw receipt OCR text.
///
/// [totalMyr], when supplied (typically the value from
/// [parseRmAmountFromOcr]), is used to reconcile the summed item prices
/// against the receipt's paid total.
ReceiptLineItemsResult extractReceiptLineItems(
  String ocrText, {
  double? totalMyr,
  int maxItems = maxExtractedLineItems,
}) {
  final lines = ocrText.split(RegExp(r'\r?\n'));
  final items = <ReceiptLineItem>[];

  for (var i = 0; i < lines.length && items.length < maxItems; i++) {
    final line = lines[i].trim();
    if (line.length < 3) continue;
    if (looksLikeBoilerplate(line)) continue;
    if (discountOrSummaryHints.hasMatch(line)) continue;
    if (totalKeywordHints.hasMatch(line)) continue;
    if (_extraSummaryLineHints.hasMatch(line)) continue;

    final parsed = _tryParseItemLine(line);
    if (parsed == null) continue;

    items.add(ReceiptLineItem(
      name: parsed.name,
      priceMyr: parsed.price,
      quantity: parsed.quantity,
      confidence: parsed.confidence,
      lineIndex: i,
    ));
  }

  if (items.isEmpty) {
    return const ReceiptLineItemsResult(
      items: [],
      confidence: 0.0,
      itemsSubtotalMyr: null,
      itemsMatchTotal: false,
    );
  }

  final rawSubtotal = items.fold<double>(0, (s, it) => s + it.priceMyr);
  final subtotal = double.parse(rawSubtotal.toStringAsFixed(2));

  final meanLineConfidence =
      items.map((it) => it.confidence ?? 0.5).reduce((a, b) => a + b) /
          items.length;

  final base = ReceiptLineItemsResult(
    items: items,
    confidence: meanLineConfidence.clamp(0.05, 0.98),
    itemsSubtotalMyr: subtotal,
    itemsMatchTotal: false,
  );
  return reconcileWithTotal(base, totalMyr);
}

/// Reconciles already-extracted items against the receipt's paid total:
/// sets [ReceiptLineItemsResult.itemsMatchTotal] and applies the mismatch
/// penalty to the aggregate confidence. Split out from extraction so the
/// pipeline can extract items first, use their subtotal to help *pick* the
/// total, then reconcile against whatever total won.
ReceiptLineItemsResult reconcileWithTotal(
  ReceiptLineItemsResult result,
  double? totalMyr,
) {
  final subtotal = result.itemsSubtotalMyr;
  if (totalMyr == null || subtotal == null || result.items.isEmpty) {
    return result;
  }

  var itemsMatchTotal = false;
  final diff = (subtotal - totalMyr).abs();
  if (diff <= itemsSubtotalExactToleranceMyr) {
    itemsMatchTotal = true;
  } else if (subtotal < totalMyr &&
      (totalMyr - subtotal) <=
          totalMyr * itemsSubtotalTaxServiceAllowanceFraction) {
    // Items should not normally exceed the paid total; an under-total gap
    // within the allowance is treated as SST/service charge, not a miss.
    itemsMatchTotal = true;
  }

  var overallConfidence = result.confidence;
  if (!itemsMatchTotal) overallConfidence -= 0.15;

  return ReceiptLineItemsResult(
    items: result.items,
    confidence: overallConfidence.clamp(0.05, 0.98),
    itemsSubtotalMyr: subtotal,
    itemsMatchTotal: itemsMatchTotal,
  );
}
