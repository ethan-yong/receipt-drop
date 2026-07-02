import 'dart:typed_data';

import '../../data/repositories/ingest_receipt_request.dart';
import '../../domain/models/receipt_line_item.dart';

/// Parsed receipt ready for the save sheet (before user confirms amount).
class ReceiptIngestDraft {
  const ReceiptIngestDraft({
    required this.localFilePath,
    required this.mimeType,
    required this.amountMyr,
    required this.needsAmount,
    required this.merchantRaw,
    required this.categoryGuess,
    this.thumbnailBytes,
    this.shareLocationLat,
    this.shareLocationLng,
    this.shareLocationCapturedAt,
    this.ocrConfidence,
    this.lineItems = const [],
  });

  final String localFilePath;
  final String mimeType;
  final double? amountMyr;
  final bool needsAmount;
  final String? merchantRaw;
  final String categoryGuess;
  final Uint8List? thumbnailBytes;
  final double? shareLocationLat;
  final double? shareLocationLng;
  final DateTime? shareLocationCapturedAt;
  final double? ocrConfidence;
  final List<ReceiptLineItem> lineItems;

  ReceiptIngestDraft copyWith({
    double? amountMyr,
    bool? needsAmount,
    String? merchantRaw,
    String? categoryGuess,
  }) {
    return ReceiptIngestDraft(
      localFilePath: localFilePath,
      mimeType: mimeType,
      amountMyr: amountMyr ?? this.amountMyr,
      needsAmount: needsAmount ?? this.needsAmount,
      merchantRaw: merchantRaw ?? this.merchantRaw,
      categoryGuess: categoryGuess ?? this.categoryGuess,
      thumbnailBytes: thumbnailBytes,
      shareLocationLat: shareLocationLat,
      shareLocationLng: shareLocationLng,
      shareLocationCapturedAt: shareLocationCapturedAt,
      ocrConfidence: ocrConfidence,
      lineItems: lineItems,
    );
  }

  /// Mirrors [ReceiptCaptureFlow] save: confirmed amount, line items carried through.
  IngestReceiptRequest toIngestRequest({
    required double confirmedAmount,
    String? impactUser,
  }) {
    return IngestReceiptRequest(
      localFilePath: localFilePath,
      mimeType: mimeType,
      amountMyr: confirmedAmount,
      needsAmount: false,
      merchantRaw: merchantRaw,
      categoryGuess: categoryGuess,
      thumbnailBytes: thumbnailBytes,
      shareLocationLat: shareLocationLat,
      shareLocationLng: shareLocationLng,
      shareLocationCapturedAt: shareLocationCapturedAt,
      ocrConfidence: ocrConfidence,
      impactUser: impactUser,
      lineItems: lineItems,
    );
  }
}
