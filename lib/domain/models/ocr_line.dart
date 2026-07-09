/// One recognized OCR line plus its visual prominence relative to the rest
/// of the same receipt image — from the self-hosted OCR API's per-line
/// bounding-box data (`services/ocr-api/app/ocr_engine.py`'s `OcrLineResult`,
/// mirrored here with the same field names).
///
/// Used by `extractMerchantCandidates()` to prefer a visually large-font
/// header/logo line over the (usually uniform, small-font) itemized body,
/// even when it doesn't match any known keyword.
class OcrLine {
  const OcrLine({required this.text, required this.heightRatio});

  final String text;

  /// Median word bounding-box height on this line, divided by the image's
  /// total height. Relative-to-this-receipt, not an absolute pixel
  /// threshold, so it's comparable regardless of a given scan's resolution.
  final double heightRatio;

  static OcrLine? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final text = json['text'];
    final heightRatio = json['height_ratio'];
    if (text is! String || heightRatio is! num) return null;
    return OcrLine(text: text, heightRatio: heightRatio.toDouble());
  }

  Map<String, dynamic> toJson() => {
        'text': text,
        'height_ratio': heightRatio,
      };
}
