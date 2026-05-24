import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../../domain/logic/category_matcher.dart';
import '../../domain/logic/rm_amount_parser.dart';
import 'ocr_pipeline.dart';
import 'receipt_file_store.dart';
import 'receipt_ingest_draft.dart';
import 'receipt_ingest_service_io.dart'
    if (dart.library.html) 'receipt_ingest_service_web.dart' as path_reader;
import 'stored_receipt_file.dart';

/// Shared pipeline for manual upload and OS share intake.
class ReceiptIngestService {
  ReceiptIngestService._();

  static CategoryConfig? _categoryConfig;

  static Future<CategoryConfig> _categories() async {
    _categoryConfig ??= await CategoryConfig.loadBundled();
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
    final ocrText = stored.localPath.startsWith('web:')
        ? ''
        : await runOcrOnReceiptFile(
            filePath: stored.localPath,
            mimeType: stored.mimeType,
          );

    final parseResult = parseRmAmountFromOcr(ocrText);
    final amount = parseResult.amount;
    final needsAmount = amount == null;
    final merchantRaw = _firstMeaningfulLine(ocrText);
    final categories = await _categories();
    final categoryGuess = categories
        .guessForMerchant(merchantRaw ?? '')
        .category;

    final location = await _captureLocation();

    return ReceiptIngestDraft(
      localFilePath: stored.localPath,
      mimeType: stored.mimeType,
      amountMyr: amount,
      needsAmount: needsAmount,
      merchantRaw: merchantRaw,
      categoryGuess: categoryGuess,
      thumbnailBytes: stored.bytes,
      shareLocationLat: location?.latitude,
      shareLocationLng: location?.longitude,
      shareLocationCapturedAt: location != null ? DateTime.now().toUtc() : null,
      ocrConfidence: parseResult.confidence,
    );
  }

  static String? _firstMeaningfulLine(String ocrText) {
    for (final line in ocrText.split(RegExp(r'\r?\n'))) {
      final trimmed = line.trim();
      if (trimmed.length >= 3) return trimmed;
    }
    return null;
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
