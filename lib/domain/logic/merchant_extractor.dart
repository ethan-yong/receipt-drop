import '../models/ocr_line.dart';
import '../models/receipt_line_zone.dart';
import 'category_matcher.dart';

/// Only the lines near the top of the receipt are worth considering — the
/// merchant name never appears buried deep in the itemized body. Raised from
/// 8 to 15 so multi-line headers (banner + brand + branch + address block)
/// still surface the real name as a ranked candidate even when it isn't the
/// very first non-boilerplate line.
const merchantScanLines = 15;

/// A line counts as visually "large text" when its median glyph height
/// clears this multiple of the receipt's typical (body-text) line height.
/// 1.4x is deliberately conservative — most receipts print item rows in a
/// near-uniform size, so a real header/logo line usually clears this by a
/// wide margin; tune after batch runs, same as the OCR engine's constants.
const _largeTextRatioThreshold = 1.4;

/// How strongly line-level OCR confidence blends into merchant candidate
/// scores. Missing confidence → neutral (no change).
const _ocrConfidenceBlendWeight = 0.15;

/// When top-2 merchant candidate confidences differ by less than this,
/// treat as ambiguous and surface both in the UI.
const merchantAmbiguousDelta = 0.08;

final boilerplateHints = RegExp(
  r'(tax invoice|simplified tax invoice|cash bill|official receipt|'
  r'gst reg|gst no|sst reg|sst no|company reg|tel:|phone:|www\.|receipt no|'
  r'tin no|tax id)',
  caseSensitive: false,
);

final numericOrPunctuationOnly = RegExp(r'^[\d\s\-+()/:.,]+$');

/// Malaysian mobile/landline numbers, with or without a label — "012-345
/// 6789", "03-1234 5678". Checked in addition to [boilerplateHints]'s
/// label-based "tel:"/"phone:" match, since receipts often print a bare
/// number with no label at all.
final _phoneNumberHint = RegExp(
  r'(?:\+?6?0)?1\d[\s-]?\d{3,4}[\s-]?\d{3,4}\b|\b0\d[\s-]\d{3,4}[\s-]\d{4}\b',
);

/// Dates in any common receipt format: 12/05/2026, 12-05-26, 12.05.2026.
final _dateHint = RegExp(r'\b\d{1,2}[/\-.]\d{1,2}[/\-.]\d{2,4}\b');

/// Malaysian street-address markers. A merchant's own name sometimes
/// contains "Jalan" (a street name used as a brand, e.g. shopping streets),
/// so this alone doesn't exclude a line from the last-resort fallback below
/// — only from the higher-confidence candidate passes.
final _addressHint = RegExp(
  r'(jalan\b|jln\.?\s|taman\b|lorong\b|lot\s*\d|persiaran\b|seksyen\b)',
  caseSensitive: false,
);

/// A bare 5-digit run, the shape of a Malaysian postcode. Deliberately not
/// combined with [_addressHint] into one match — a postcode often sits alone
/// on its own line ("47500 Subang Jaya") without any street-marker keyword.
final _postcodeHint = RegExp(r'\b\d{5}\b');

bool looksLikeBoilerplate(String line) =>
    boilerplateHints.hasMatch(line) || numericOrPunctuationOnly.hasMatch(line);

/// Lines that are clearly metadata rather than a merchant name — phone
/// numbers, dates, addresses, postcodes — even though they contain letters
/// and would otherwise pass [_lettersRun]. Shared with
/// [receipt_layout_analyzer.dart] and [receipt_line_item_extractor.dart].
bool looksLikeReceiptMetadata(String line) =>
    _phoneNumberHint.hasMatch(line) ||
    _dateHint.hasMatch(line) ||
    _addressHint.hasMatch(line) ||
    _postcodeHint.hasMatch(line);

/// Lines that are clearly metadata rather than a merchant name — phone
/// numbers, dates, addresses, postcodes — even though they contain letters
/// and would otherwise pass [_lettersRun]. Applied only when ranking
/// candidates; the last-resort fallback in [extractMerchantCandidates] still
/// prefers any line with real content over nothing at all.
bool _looksLikeMetadata(String line) => looksLikeReceiptMetadata(line);

// A real merchant name has at least one run of 3+ letters. OCR scene junk
// from cluttered photo backgrounds ("- : a a ~~ . ;", "oo a") passes the
// numeric-only check above but never forms a letters run, so this filters it
// from the fallback without touching the shared boilerplate helpers.
final _lettersRun = RegExp(r'[A-Za-z]{3,}');

/// Generic business/venue-type words — a much weaker signal than an exact
/// category-keyword hit (that's still checked first), but a useful tiebreak
/// when no bundled category rule matches (unusual chains, generic kopitiams).
final _businessWordHints = RegExp(
  r'(restoran\b|restaurant|kedai\b|caf[eé]\b|kopitiam|bistro|eatery|'
  r'baker[iy]|sdn\.?\s*bhd|enterprise|trading\b|holdings\b|warehouse\b|'
  r'\bmart\b|\bstore\b|grocer|supermarket|pasar\b)',
  caseSensitive: false,
);

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

/// A ranked guess at the merchant name, with a rough provenance tag so
/// callers (and Google Places enrichment) can tell a near-certain brand-name
/// hit from a weak positional fallback.
///
/// [source] is one of:
/// - `llm`: the LLM's cleaned merchant name from the synchronous
///   receipt-understanding step (`receipt_parse_pipeline.dart`), prepended
///   ahead of every candidate below when present — not produced by this
///   function itself.
/// - `header`: matched a known category-rule keyword (strongest signal).
/// - `keyword`: matched a generic business/venue word (RESTORAN, SDN BHD, ...).
/// - `largeText`: no keyword hit, but printed visibly larger than the rest
///   of the receipt (a logo/header line Tesseract couldn't keyword-match) —
///   only available when [OcrLine] height data was supplied.
/// - `position`: no keyword/large-text hit; ranked by how early it appears.
/// - `fallback`: last resort — every line looked like boilerplate/metadata.
class MerchantCandidate {
  const MerchantCandidate({
    required this.text,
    required this.confidence,
    required this.source,
  });

  final String text;
  final double confidence;
  final String source;

  Map<String, dynamic> toJson() => {
    'text': text,
    'confidence': confidence,
    'source': source,
  };

  @override
  String toString() =>
      'MerchantCandidate($text, ${confidence.toStringAsFixed(2)}, $source)';
}

/// Picks ranked merchant-name candidates from raw OCR text.
///
/// Prefers a line matching a known brand keyword from [categories] (a strong,
/// exact signal) over generic business-word hints, over the positional
/// fallback of "early non-boilerplate line near the top of the receipt" —
/// logos/promo banners often precede the merchant name and receipt headers
/// (tax invoice/GST labels, phone numbers, addresses) often surround it.
///
/// Always returns at least one candidate for non-empty, non-whitespace input
/// (mirroring the previous single-guess contract); returns `[]` only when
/// there's no real content to scan.
List<MerchantCandidate> extractMerchantCandidates(
  String ocrText,
  CategoryConfig categories, {
  List<OcrLine>? ocrLines,
  ReceiptLayoutAnalysis? layout,
}) {
  final rawLines = ocrText
      .split(RegExp(r'\r?\n'))
      .map((l) => l.trim())
      .where((l) => l.length >= 3)
      .take(merchantScanLines)
      .toList();
  if (rawLines.isEmpty) return const [];

  // Pre-compute raw-line index once (avoids O(n) scan per candidate).
  final allLines = ocrText.split(RegExp(r'\r?\n'));
  final rawIndexByTrimmed = <String, int>{};
  for (var i = 0; i < allLines.length; i++) {
    rawIndexByTrimmed.putIfAbsent(allLines[i].trim(), () => i);
  }

  double? ocrConfFor(String trimmedLine) {
    final idx = rawIndexByTrimmed[trimmedLine];
    if (idx == null || ocrLines == null || idx >= ocrLines.length) return null;
    // Prefer index alignment over text-keyed lookup.
    final line = ocrLines[idx];
    if (line.text.trim() != trimmedLine) return null;
    return line.confidence;
  }

  double blendOcr(double base, String line) {
    final conf = ocrConfFor(line);
    if (conf == null) return base;
    // Soft blend: high OCR confidence lifts slightly, low confidence lowers.
    return (base + (conf - 0.5) * _ocrConfidenceBlendWeight).clamp(0.05, 0.98);
  }

  // Edge junk is stripped from a winning line only (not before matching: the
  // raw line is what boilerplate/keyword/metadata patterns were tuned
  // against).
  String clean(String line) {
    final stripped = stripEdgeJunk(line);
    return stripped.isEmpty ? line : stripped;
  }

  final candidates = <MerchantCandidate>[];
  final seenNormalized = <String>{};

  void addCandidate(String line, double confidence, String source) {
    final text = clean(line);
    if (text.isEmpty) return;
    if (!seenNormalized.add(text.toLowerCase())) return;
    candidates.add(
      MerchantCandidate(
        text: text,
        confidence: blendOcr(confidence, line),
        source: source,
      ),
    );
  }

  // Pass 1: exact category-rule keyword hits — a known brand name is
  // essentially certain wherever it appears among the scanned lines.
  for (final line in rawLines) {
    final lower = line.toLowerCase();
    for (final rule in categories.rules) {
      if (rule.keywords.any((kw) => lower.contains(kw.toLowerCase()))) {
        addCandidate(line, 0.92, 'header');
        break;
      }
    }
  }

  // Pass 2: generic business/venue-type words, skipping anything that reads
  // as metadata (phone/date/address/postcode) even if it has real letters.
  // When layout zones are reliable, skip business-word hits inside the body
  // zone (e.g. Kopitiam Fried Rice) — they stay eligible in header/ambiguous.
  for (final line in rawLines) {
    if (looksLikeBoilerplate(line) || _looksLikeMetadata(line)) continue;
    if (layout?.isReliable == true) {
      final rawIndex = rawIndexByTrimmed[line];
      if (rawIndex != null &&
          layout!.zoneAt(rawIndex) == ReceiptLineZone.body) {
        continue;
      }
    }
    if (_businessWordHints.hasMatch(line) && _lettersRun.hasMatch(line)) {
      addCandidate(line, 0.82, 'keyword');
    }
  }

  // Pass "large text": a visually prominent line (relative to this same
  // receipt's typical body-text height) is a strong merchant-name signal
  // even when Tesseract garbled it too badly for any keyword to match —
  // exactly the case a plain position-based fallback can't distinguish from
  // an isolated short noise fragment. Runs after the keyword tiers (so an
  // exact brand match still wins outright) and before the position
  // fallback (so a big-font unrecognized name still beats a small-font
  // early line). No-ops entirely when height data wasn't supplied — fully
  // additive, doesn't change behavior for existing callers.
  if (ocrLines != null && ocrLines.isNotEmpty) {
    final heightByLine = <String, double>{
      for (final l in ocrLines) l.text.trim(): l.heightRatio,
    };
    final lineHeights = ocrLines
        .map((l) => l.heightRatio)
        .where((h) => h > 0)
        .toList()
      ..sort();
    if (lineHeights.isNotEmpty) {
      final bodyBaseline = lineHeights[lineHeights.length ~/ 2];
      if (bodyBaseline > 0) {
        for (final line in rawLines) {
          if (_looksLikeMetadata(line)) continue;
          final height = heightByLine[line];
          if (height == null) continue;
          if (height >= bodyBaseline * _largeTextRatioThreshold) {
            addCandidate(line, 0.80, 'largeText');
          }
        }
      }
    }
  }

  // Pass 3: fallback over whatever's left, scored mainly by how much real
  // letter content the line has — a proxy for "looks like a substantive
  // name/header" rather than an isolated OCR-noise fragment — with position
  // as a secondary tiebreak only.
  var positionRank = 0;
  for (final line in rawLines) {
    if (looksLikeBoilerplate(line) || _looksLikeMetadata(line)) continue;
    if (layout?.isReliable == true) {
      final rawIndex = rawIndexByTrimmed[line];
      if (rawIndex != null &&
          layout!.zoneAt(rawIndex) == ReceiptLineZone.body) {
        continue;
      }
    }
    final letterCount = line.replaceAll(RegExp(r'[^A-Za-z]'), '').length;
    if (letterCount < 4) continue;
    final lengthScore = (letterCount / 20).clamp(0.0, 1.0);
    final confidence =
        (0.35 + 0.35 * lengthScore - positionRank * 0.03).clamp(0.2, 0.7);
    addCandidate(line, confidence, 'position');
    positionRank++;
  }

  // Last resort: every line looked like boilerplate/metadata. Prefer any
  // line with a real word over raw scene junk, then the first scanned line.
  if (candidates.isEmpty) {
    for (final line in rawLines) {
      if (_lettersRun.hasMatch(line)) {
        addCandidate(line, 0.2, 'fallback');
        break;
      }
    }
  }
  if (candidates.isEmpty) {
    addCandidate(rawLines.first, 0.1, 'fallback');
  }

  candidates.sort((a, b) => b.confidence.compareTo(a.confidence));
  return candidates.take(5).toList();
}

/// The single highest-confidence merchant guess — kept for backward
/// compatibility with existing callers/tests. Prefer
/// [extractMerchantCandidates] for anything that can make use of the full
/// ranked list (e.g. Places enrichment).
String? extractMerchant(
  String ocrText,
  CategoryConfig categories, {
  List<OcrLine>? ocrLines,
}) {
  final candidates =
      extractMerchantCandidates(ocrText, categories, ocrLines: ocrLines);
  return candidates.isEmpty ? null : candidates.first.text;
}

/// The same top-of-receipt lines [extractMerchantCandidates] scans, joined
/// as extra context sent to Places enrichment. Always populated (capped to
/// [maxChars]) — unlike `rawOcrText`, which is only kept for failed/low-
/// confidence parses.
String extractOcrHeaderText(String ocrText, {int maxChars = 500}) {
  final lines = ocrText
      .split(RegExp(r'\r?\n'))
      .map((l) => l.trim())
      .where((l) => l.length >= 3)
      .take(merchantScanLines)
      .toList();
  final joined = lines.join('\n');
  return joined.length > maxChars ? joined.substring(0, maxChars) : joined;
}
