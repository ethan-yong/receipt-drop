import '../../domain/logic/category_matcher.dart';
import '../../domain/models/ocr_progress_event.dart';
import 'ocr_pipeline.dart';
import 'ocr_progress_notifier.dart';
import 'receipt_parse_pipeline.dart';

/// Runs remote OCR API then parses amount, merchant, and category.
Future<ReceiptParseResult> parseReceiptFile({
  required String filePath,
  required String mimeType,
  required CategoryConfig categories,
  OcrProgressNotifier? notifier,
}) async {
  await notifier?.emit(const OcrStartedEvent());
  final ocr = await runOcrOnReceiptFile(
    filePath: filePath,
    mimeType: mimeType,
  );
  await notifier?.emit(const OcrCompletedEvent());
  return parseReceiptOcrText(
    filePath: filePath,
    ocrText: ocr.text,
    categories: categories,
    ocrServiceConfidence: ocr.serviceConfidence,
    ocrLines: ocr.lines,
    understanding: ocr.understanding,
    understandingError: ocr.understandingError,
  );
}
