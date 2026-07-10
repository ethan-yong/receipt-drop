import '../../domain/logic/category_matcher.dart';
import 'ocr_pipeline.dart';
import 'receipt_parse_pipeline.dart';

/// Runs remote OCR API then parses amount, merchant, and category.
Future<ReceiptParseResult> parseReceiptFile({
  required String filePath,
  required String mimeType,
  required CategoryConfig categories,
}) async {
  final ocr = await runOcrOnReceiptFile(
    filePath: filePath,
    mimeType: mimeType,
  );
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
