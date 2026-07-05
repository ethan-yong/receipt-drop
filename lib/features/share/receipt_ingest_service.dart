import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

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

    final location = await _captureLocation();

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
      // Failed/shaky parses keep their raw OCR text as evidence for fixing
      // parser rules later; clean parses don't need the payload.
      rawOcrText: (parsed.needsAmount || parsed.lowConfidence) &&
              parsed.ocrText.isNotEmpty
          ? parsed.ocrText
          : null,
      ocrServiceConfidence: parsed.ocrServiceConfidence,
      lineItemsConfidence: parsed.lineItemsConfidence,
      parseFailureReason: parsed.parseFailureReason,
      lowConfidence: parsed.lowConfidence,
    );
  }

  static Future<Position?> _captureLocation() async {
    if (kIsWeb) return null;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      return Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 8),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> discardDraft(ReceiptIngestDraft draft) async {
    if (!draft.localFilePath.startsWith('web:')) {
      await deleteStoredReceipt(draft.localFilePath);
    }
  }
}
