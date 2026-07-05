/// OCR text plus the engine's scan-quality confidence (null when the source
/// provides none: local ML Kit, PDF text extraction, or web).
typedef OcrFileResult = ({String text, double? serviceConfidence});

/// Web has no ML Kit — OCR is skipped; user enters amount on save sheet.
Future<OcrFileResult> runOcrOnReceiptFile({
  required String filePath,
  required String mimeType,
}) async {
  return (text: '', serviceConfidence: null);
}
