import 'package:flutter/foundation.dart';

import '../../core/utils/current_location.dart';
import '../../domain/logic/category_matcher.dart';
import '../../domain/logic/category_matcher_bundled.dart';
import '../../domain/models/ocr_progress_event.dart';
import 'ocr_progress_notifier.dart';
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
    OcrProgressNotifier? notifier,
  }) async {
    await notifier?.emit(const ReceiptUploadedEvent());
    final stored = await persistReceiptBytes(bytes, mimeType);
    return _buildDraft(stored, notifier: notifier);
  }

  /// Build a draft from a filesystem path (native share / image picker path).
  static Future<ReceiptIngestDraft> ingestPath({
    required String path,
    required String mimeType,
    OcrProgressNotifier? notifier,
  }) async {
    await notifier?.emit(const ReceiptUploadedEvent());
    final bytes = await path_reader.readPathBytes(path);
    final stored = await persistReceiptBytes(bytes, mimeType);
    return _buildDraft(stored, notifier: notifier);
  }

  static Future<ReceiptIngestDraft> _buildDraft(
    StoredReceiptFile stored, {
    OcrProgressNotifier? notifier,
  }) async {
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
            notifier: notifier,
          );

    // Emit extracted-data events sequentially so the UI log fills in with
    // real values. The notifier enforces a minimum display time per step.
    await notifier?.emit(MerchantIdentifiedEvent(
      merchant: parsed.understanding?.merchantName ?? parsed.merchantRaw,
    ));
    if (parsed.lineItems.isNotEmpty) {
      await notifier?.emit(ItemsExtractedEvent(count: parsed.lineItems.length));
    }
    await notifier?.emit(TotalExtractedEvent(amount: parsed.amountMyr));
    await notifier?.emit(CategoryPredictedEvent(category: parsed.categoryGuess));

    final location = await getCurrentPositionOrNull();

    final draft = ReceiptIngestDraft(
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
      rawOcrText: parsed.ocrText.isNotEmpty
          ? _capOcrText(parsed.ocrText)
          : null,
      ocrServiceConfidence: parsed.ocrServiceConfidence,
      lineItemsConfidence: parsed.lineItemsConfidence,
      parseFailureReason: parsed.parseFailureReason,
      lowConfidence: parsed.lowConfidence,
      merchantCandidates: parsed.merchantCandidates,
      ocrHeaderText: parsed.ocrHeaderText,
      understanding: parsed.understanding,
      amountAlternativeMyr: parsed.amountAlternative?.value,
      amountSuspicious: parsed.amountSuspicious,
      amountFieldLowConfidence: parsed.amountOcrConfidence != null &&
          parsed.amountOcrConfidence! < 0.5,
      merchantAmbiguous: parsed.merchantAmbiguous,
      merchantConfidence: parsed.merchantConfidence,
    );

    await notifier?.emit(ProcessingCompletedEvent(draft: draft));
    return draft;
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
