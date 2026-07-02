import '../../domain/logic/category_matcher.dart';
import 'ocr_pipeline.dart';
import 'receipt_parse_pipeline.dart';

/// Runs on-device / remote OCR then parses amount, merchant, and category.
Future<ReceiptParseResult> parseReceiptFile({
  required String filePath,
  required String mimeType,
  required CategoryConfig categories,
}) async {
  final ocrText = await runOcrOnReceiptFile(
    filePath: filePath,
    mimeType: mimeType,
  );
  return parseReceiptOcrText(
    filePath: filePath,
    ocrText: ocrText,
    categories: categories,
  );
}
