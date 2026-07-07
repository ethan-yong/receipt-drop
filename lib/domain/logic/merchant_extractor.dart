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

// A real merchant name has at least one run of 3+ letters. OCR scene junk
// from cluttered photo backgrounds ("- : a a ~~ . ;", "oo a") passes the
// numeric-only check above but never forms a letters run, so this filters it
// from the fallback without touching the shared boilerplate helpers.
final _lettersRun = RegExp(r'[A-Za-z]{3,}');

// OCR scene junk glued to a fragment's edges by cluttered photo backgrounds
// ("\ RESTORAN ANWAR MAU.", "] Limau Ais"). Opening parens and closing
// parens/percent survive — they belong to real names like "(L) Kopi" and
// "Diskaun 10%". Inner punctuation (apostrophes, ampersands) is untouched.
final _leadingEdgeJunk = RegExp(r'^[^A-Za-z0-9(]+');
final _trailingEdgeJunk = RegExp(r'[^A-Za-z0-9)%]+$');

/// Strips leading/trailing OCR scene junk from [text]. May return an empty
/// string when the whole fragment was junk — callers pick their own fallback.
/// Shared with receipt_line_item_extractor.dart for item names.
String stripEdgeJunk(String text) => text
    .replaceFirst(_leadingEdgeJunk, '')
    .replaceFirst(_trailingEdgeJunk, '')
    .trim();

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

  // Edge junk is stripped from the winning line only (not before matching:
  // the raw line is what boilerplate/keyword patterns were tuned against).
  String clean(String line) {
    final stripped = stripEdgeJunk(line);
    return stripped.isEmpty ? line : stripped;
  }

  for (final line in lines) {
    final lower = line.toLowerCase();
    for (final rule in categories.rules) {
      if (rule.keywords.any((kw) => lower.contains(kw.toLowerCase()))) {
        return clean(line);
      }
    }
  }

  for (final line in lines) {
    if (!looksLikeBoilerplate(line) && _lettersRun.hasMatch(line)) {
      return clean(line);
    }
  }
  // Last resort: prefer any line with a real word over raw junk.
  for (final line in lines) {
    if (_lettersRun.hasMatch(line)) return clean(line);
  }
  return clean(lines.first);
}
