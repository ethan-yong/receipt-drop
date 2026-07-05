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
    this.rawOcrText,
    this.ocrServiceConfidence,
    this.lineItemsConfidence,
    this.parseFailureReason,
    this.lowConfidence = false,
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

  /// Raw OCR text, carried only when the parse failed or was low-confidence.
  final String? rawOcrText;
  final double? ocrServiceConfidence;
  final double? lineItemsConfidence;
  final String? parseFailureReason;

  /// Combined-confidence verdict from [ReceiptParseResult.lowConfidence];
  /// kept on the draft so the save sheet doesn't re-derive it from
  /// [ocrConfidence] alone.
  final bool lowConfidence;

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
      rawOcrText: rawOcrText,
      ocrServiceConfidence: ocrServiceConfidence,
      lineItemsConfidence: lineItemsConfidence,
      parseFailureReason: parseFailureReason,
      lowConfidence: lowConfidence,
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
      rawOcrText: rawOcrText,
      ocrServiceConfidence: ocrServiceConfidence,
      lineItemsConfidence: lineItemsConfidence,
      parseFailureReason: parseFailureReason,
    );
  }

  /// Saves without a confirmed amount: routes into the review queue instead
  /// of silently dropping the receipt. Parsed values (if any) are kept so the
  /// review screen can prefill them.
  IngestReceiptRequest toNeedsReviewRequest({String? impactUser}) {
    return IngestReceiptRequest(
      localFilePath: localFilePath,
      mimeType: mimeType,
      amountMyr: amountMyr,
      needsAmount: needsAmount,
      merchantRaw: merchantRaw,
      categoryGuess: categoryGuess,
      thumbnailBytes: thumbnailBytes,
      shareLocationLat: shareLocationLat,
      shareLocationLng: shareLocationLng,
      shareLocationCapturedAt: shareLocationCapturedAt,
      ocrConfidence: ocrConfidence,
      impactUser: impactUser,
      lineItems: lineItems,
      rawOcrText: rawOcrText,
      ocrServiceConfidence: ocrServiceConfidence,
      lineItemsConfidence: lineItemsConfidence,
      parseFailureReason: parseFailureReason,
      needsReview: true,
    );
  }
}
