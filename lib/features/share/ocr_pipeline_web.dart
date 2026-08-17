import '../../domain/models/ocr_line.dart';
import '../../domain/models/receipt_understanding.dart';

/// OCR text plus the engine's scan-quality confidence (null on web / PDF-only).
/// Mirrors `ocr_pipeline_io.dart`'s `OcrFileResult` shape so both conditional
/// exports satisfy the same call sites.
typedef OcrFileResult = ({
  String text,
  double? serviceConfidence,
  List<OcrLine>? lines,
  ReceiptUnderstanding? understanding,
  String? understandingError,
});

/// Web has no OCR API client — user enters amount on save sheet.
Future<OcrFileResult> runOcrOnReceiptFile({
  required String filePath,
  required String mimeType,
}) async {
  return (
    text: '',
    serviceConfidence: null,
    lines: null,
    understanding: null,
    understandingError: null,
  );
}
