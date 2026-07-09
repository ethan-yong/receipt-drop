import 'package:flutter/foundation.dart';

import '../../core/utils/current_location.dart';
import '../../domain/logic/category_matcher.dart';
import '../../domain/logic/category_matcher_bundled.dart';
import 'receipt_file_store.dart';
import 'receipt_ingest_draft.dart';
import 'receipt_parse_file.dart';
import 'receipt_parse_pipeline.dart';
import 'receipt_ingest_service_io.dart'
    if (dart.library.html) 'receipt_ingest_service_web.dart' as path_reader;
import 'stored_receipt_file.dart';

/// Shared pipeline for manual upload and OS share intake.
class ReceiptIngestService {
  ReceiptIngestService._();

  static CategoryConfig? _categoryConfig;

  static Future<CategoryConfig> _categories() async {
    _categoryConfig ??= await loadBundledCategoryConfig();
    return _categoryConfig!;
  }

  /// Build a draft from raw bytes (file picker, camera, share).
  static Future<ReceiptIngestDraft> ingestBytes({
    required Uint8List bytes,
    required String mimeType,
  }) async {
    final stored = await persistReceiptBytes(bytes, mimeType);
    return _buildDraft(stored);
  }

  /// Build a draft from a filesystem path (native share / image picker path).
  static Future<ReceiptIngestDraft> ingestPath({
    required String path,
    required String mimeType,
  }) async {
    final bytes = await path_reader.readPathBytes(path);
    return ingestBytes(bytes: bytes, mimeType: mimeType);
  }

  static Future<ReceiptIngestDraft> _buildDraft(StoredReceiptFile stored) async {
    final categories = await _categories();
    final parsed = stored.localPath.startsWith('web:')
        ? parseReceiptOcrText(
            filePath: stored.localPath,
            ocrText: '',
            categories: categories,
          )
        : await parseReceiptFile(
            filePath: stored.localPath,
            mimeType: stored.mimeType,
            categories: categories,
          );

    final location = await getCurrentPositionOrNull();

    return ReceiptIngestDraft(
      localFilePath: stored.localPath,
      mimeType: stored.mimeType,
      amountMyr: parsed.amountMyr,
      needsAmount: parsed.needsAmount,
      merchantRaw: parsed.merchantRaw,
      categoryGuess: parsed.categoryGuess,
      categoryConfidence: parsed.categoryConfidence,
      thumbnailBytes: stored.bytes,
      shareLocationLat: location?.latitude,
      shareLocationLng: location?.longitude,
      shareLocationCapturedAt: location != null ? DateTime.now().toUtc() : null,
      ocrConfidence: parsed.ocrConfidence,
      lineItems: parsed.lineItems,
      // Always kept now (capped): the server-side LLM receipt-understanding
      // step (enrich-transaction) needs the full receipt body, not just the
      // merchant header, to infer category from line items.
      rawOcrText: parsed.ocrText.isNotEmpty
          ? _capOcrText(parsed.ocrText)
          : null,
      ocrServiceConfidence: parsed.ocrServiceConfidence,
      lineItemsConfidence: parsed.lineItemsConfidence,
      parseFailureReason: parsed.parseFailureReason,
      lowConfidence: parsed.lowConfidence,
      merchantCandidates: parsed.merchantCandidates,
      ocrHeaderText: parsed.ocrHeaderText,
    );
  }

  static const int _maxRawOcrTextChars = 8000;

  static String _capOcrText(String text) => text.length > _maxRawOcrTextChars
      ? text.substring(0, _maxRawOcrTextChars)
      : text;

  static Future<void> discardDraft(ReceiptIngestDraft draft) async {
    if (!draft.localFilePath.startsWith('web:')) {
      await deleteStoredReceipt(draft.localFilePath);
    }
  }
}
