import 'dart:typed_data';

import '../../domain/models/receipt_line_item.dart';

/// Parameters for saving a confirmed receipt to the local outbox.
class IngestReceiptRequest {
  const IngestReceiptRequest({
    required this.localFilePath,
    required this.mimeType,
    required this.amountMyr,
    required this.needsAmount,
    required this.merchantRaw,
    required this.categoryGuess,
    this.categoryConfidence,
    this.categoryUser,
    this.thumbnailBytes,
    this.shareLocationLat,
    this.shareLocationLng,
    this.shareLocationCapturedAt,
    this.ocrConfidence,
    this.userId = 'demo-user',
    this.impactUser,
    this.lineItems = const [],
    this.rawOcrText,
    this.ocrServiceConfidence,
    this.lineItemsConfidence,
    this.parseFailureReason,
    this.needsReview = false,
  });

  final String localFilePath;
  final String mimeType;
  final double? amountMyr;
  final bool needsAmount;
  final String? merchantRaw;
  final String categoryGuess;
  final double? categoryConfidence;
  final String? categoryUser;
  final Uint8List? thumbnailBytes;
  final double? shareLocationLat;
  final double? shareLocationLng;
  final DateTime? shareLocationCapturedAt;
  final double? ocrConfidence;
  final String userId;
  final String? impactUser;
  final List<ReceiptLineItem> lineItems;

  /// Raw OCR text — only set when the parse failed or was low-confidence.
  final String? rawOcrText;
  final double? ocrServiceConfidence;
  final double? lineItemsConfidence;
  final String? parseFailureReason;

  /// Routes the transaction into the human review queue
  /// (pipeline_status = 'needs_review') instead of the normal flow.
  final bool needsReview;
}
