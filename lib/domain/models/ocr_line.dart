/// One recognized OCR word with calibrated confidence and geometry —
/// mirrors `services/ocr-api/ocr_api/ocr_engine.py`'s `OcrWordResult` /
/// public `OcrWord`. Attached selectively to low-confidence lines.
class OcrWord {
  const OcrWord({
    required this.text,
    required this.confidence,
    this.digitCorrected = false,
    this.leftRatio = 0.0,
    this.widthRatio = 0.0,
  });

  final String text;

  /// Calibrated per-word OCR confidence (0..1). Already sigmoid-calibrated
  /// by the OCR service — do NOT re-squash (see memory/bugs.md).
  final double confidence;

  /// True when the server substituted a confusable digit character in this
  /// word (Z/z/O/l/I → 2/2/0/1/1). Independent of [confidence].
  final bool digitCorrected;

  final double leftRatio;
  final double widthRatio;

  static double _asDouble(Object? value, {double fallback = 0.0}) {
    if (value is num) return value.toDouble();
    return fallback;
  }

  static OcrWord? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final text = json['text'];
    if (text is! String) return null;
    return OcrWord(
      text: text,
      confidence: _asDouble(json['confidence']),
      digitCorrected: json['digit_corrected'] == true,
      leftRatio: _asDouble(json['left_ratio']),
      widthRatio: _asDouble(json['width_ratio']),
    );
  }

  Map<String, dynamic> toJson() => {
        'text': text,
        'confidence': confidence,
        'digit_corrected': digitCorrected,
        'left_ratio': leftRatio,
        'width_ratio': widthRatio,
      };
}

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
    this.confidence,
    this.words,
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

  /// Calibrated line-level OCR confidence (0..1), when the server populated
  /// it (`TOKEN_LEVEL_CONFIDENCE=1`). Already calibrated — do NOT re-squash.
  /// Null when absent (older response / flag off) — confidence-aware scoring
  /// must treat null as a neutral (zero) contribution, not a penalty.
  final double? confidence;

  /// Per-word detail, only present for low-confidence lines. Null when
  /// absent or the line was above the enrichment threshold.
  final List<OcrWord>? words;

  /// Horizontal center of the line bbox as a fraction of image width.
  double get centerXRatio => leftRatio + widthRatio / 2;

  static double _asDouble(Object? value, {double fallback = 0.0}) {
    if (value is num) return value.toDouble();
    return fallback;
  }

  /// Parses one OCR line from JSON. Missing bbox/height fields default to
  /// 0.0 so a partial geometry payload never drops the line from the array
  /// (index alignment with `ocrText.split('\n')` depends on that).
  /// Malformed `words` lists fail safe to null rather than throwing.
  static OcrLine? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final text = json['text'];
    if (text is! String) return null;

    List<OcrWord>? words;
    final wordsJson = json['words'];
    if (wordsJson is List) {
      final parsed = <OcrWord>[];
      var ok = true;
      for (final entry in wordsJson) {
        final word = OcrWord.tryFromJson(entry);
        if (word == null) {
          ok = false;
          break;
        }
        parsed.add(word);
      }
      words = ok ? parsed : null;
    }

    final confRaw = json['confidence'];
    final confidence = confRaw is num ? confRaw.toDouble() : null;

    return OcrLine(
      text: text,
      heightRatio: _asDouble(json['height_ratio']),
      leftRatio: _asDouble(json['left_ratio']),
      topRatio: _asDouble(json['top_ratio']),
      widthRatio: _asDouble(json['width_ratio']),
      confidence: confidence,
      words: words,
    );
  }

  Map<String, dynamic> toJson() => {
        'text': text,
        'height_ratio': heightRatio,
        'left_ratio': leftRatio,
        'top_ratio': topRatio,
        'width_ratio': widthRatio,
        if (confidence != null) 'confidence': confidence,
        if (words != null) 'words': words!.map((w) => w.toJson()).toList(),
      };
}
