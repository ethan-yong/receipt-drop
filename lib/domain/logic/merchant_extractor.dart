import 'category_matcher.dart';

/// Only the lines near the top of the receipt are worth considering — the
/// merchant name never appears buried deep in the itemized body.
const merchantScanLines = 8;

final boilerplateHints = RegExp(
  r'(tax invoice|simplified tax invoice|cash bill|official receipt|'
  r'gst reg|gst no|sst reg|sst no|company reg|tel:|phone:|www\.|receipt no)',
  caseSensitive: false,
);

final numericOrPunctuationOnly = RegExp(r'^[\d\s\-+()/:.,]+$');

bool looksLikeBoilerplate(String line) =>
    boilerplateHints.hasMatch(line) || numericOrPunctuationOnly.hasMatch(line);

/// Picks the most likely merchant name from raw OCR text.
///
/// Prefers a line matching a known brand keyword from [categories] (a strong,
/// exact signal) over the generic fallback of "first non-boilerplate line
/// near the top of the receipt", since logos/promo banners often precede the
/// merchant name and receipt headers (tax invoice/GST labels, phone numbers)
/// often precede or follow it.
String? extractMerchant(String ocrText, CategoryConfig categories) {
  final lines = ocrText
      .split(RegExp(r'\r?\n'))
      .map((l) => l.trim())
      .where((l) => l.length >= 3)
      .take(merchantScanLines)
      .toList();
  if (lines.isEmpty) return null;

  for (final line in lines) {
    final lower = line.toLowerCase();
    for (final rule in categories.rules) {
      if (rule.keywords.any((kw) => lower.contains(kw.toLowerCase()))) {
        return line;
      }
    }
  }

  for (final line in lines) {
    if (!looksLikeBoilerplate(line)) return line;
  }
  return lines.first;
}
