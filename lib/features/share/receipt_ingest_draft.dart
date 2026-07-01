import 'dart:typed_data';

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
    );
  }
}
