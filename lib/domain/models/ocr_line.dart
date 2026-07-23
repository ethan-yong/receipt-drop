/// One recognized OCR line plus its visual prominence relative to the rest
/// of the same receipt image — from the self-hosted OCR API's per-line
/// bounding-box data (`services/ocr-api/ocr_api/ocr_engine.py`'s `OcrLineResult`,
/// mirrored here with the same field names).
///
/// Used by `extractMerchantCandidates()` to prefer a visually large-font
/// header/logo line over the (usually uniform, small-font) itemized body,
/// even when it doesn't match any known keyword.
class OcrLine {
  const OcrLine({
    required this.text,
    required this.heightRatio,
    this.leftRatio = 0.0,
    this.topRatio = 0.0,
    this.widthRatio = 0.0,
  });

  final String text;

  /// Median word bounding-box height on this line, divided by the image's
  /// total height. Relative-to-this-receipt, not an absolute pixel
  /// threshold, so it's comparable regardless of a given scan's resolution.
  final double heightRatio;

  /// Line bounding box min-left / image width.
  final double leftRatio;

  /// Line bounding box min-top / image height.
  final double topRatio;

  /// Line bounding box span width / image width.
  final double widthRatio;

  /// Horizontal center of the line bbox as a fraction of image width.
  double get centerXRatio => leftRatio + widthRatio / 2;

  static double _asDouble(Object? value, {double fallback = 0.0}) {
    if (value is num) return value.toDouble();
    return fallback;
  }

  /// Parses one OCR line from JSON. Missing bbox/height fields default to
  /// 0.0 so a partial geometry payload never drops the line from the array
  /// (index alignment with `ocrText.split('\n')` depends on that).
  static OcrLine? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final text = json['text'];
    if (text is! String) return null;
    return OcrLine(
      text: text,
      heightRatio: _asDouble(json['height_ratio']),
      leftRatio: _asDouble(json['left_ratio']),
      topRatio: _asDouble(json['top_ratio']),
      widthRatio: _asDouble(json['width_ratio']),
    );
  }

  Map<String, dynamic> toJson() => {
        'text': text,
        'height_ratio': heightRatio,
        'left_ratio': leftRatio,
        'top_ratio': topRatio,
        'width_ratio': widthRatio,
      };
}
