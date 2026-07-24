import '../../data/repositories/category_preference_repository.dart';
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

  // Consult the learned per-user category preference ahead of parsing, keyed
  // on the LLM's own merchant read when available (parseReceiptOcrText's
  // heuristic merchant candidates aren't known until parsing runs, so this
  // covers the common LLM-available case only — no preference is applied
  // when the LLM didn't run, same as today's baseline). Best-effort and
  // short-timeout inside the repository itself: never blocks capture.
  final categoryPreferenceHint = await CategoryPreferenceRepository.lookup(
    ocr.understanding?.merchantName,
  );

  return parseReceiptOcrText(
    filePath: filePath,
    ocrText: ocr.text,
    categories: categories,
    ocrServiceConfidence: ocr.serviceConfidence,
    ocrLines: ocr.lines,
    understanding: ocr.understanding,
    understandingError: ocr.understandingError,
    categoryPreferenceHint: categoryPreferenceHint,
  );
}
