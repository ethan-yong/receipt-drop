/// OCR text plus the engine's scan-quality confidence (null on web / PDF-only).
typedef OcrFileResult = ({String text, double? serviceConfidence});

/// Web has no OCR API client — user enters amount on save sheet.
Future<OcrFileResult> runOcrOnReceiptFile({
  required String filePath,
  required String mimeType,
}) async {
  return (text: '', serviceConfidence: null);
}
