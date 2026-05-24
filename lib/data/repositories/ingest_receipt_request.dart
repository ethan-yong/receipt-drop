import 'dart:typed_data';

/// Parameters for saving a confirmed receipt to the local outbox.
class IngestReceiptRequest {
  const IngestReceiptRequest({
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
    this.userId = 'demo-user',
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
  final String userId;
}
