import 'dart:typed_data';

import '../../data/repositories/ingest_receipt_request.dart';
import '../../domain/logic/merchant_extractor.dart';
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
    this.categoryConfidence,
    this.categoryUser,
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
    this.merchantCandidates = const [],
    this.ocrHeaderText,
    this.pickedPlaceName,
    this.pickedPlaceGooglePlaceId,
    this.pickedPlaceLat,
    this.pickedPlaceLng,
    this.pickedPlaceLocked = false,
  });

  final String localFilePath;
  final String mimeType;
  final double? amountMyr;
  final bool needsAmount;
  final String? merchantRaw;
  final String categoryGuess;
  final double? categoryConfidence;

  /// Category override set by the user in the save sheet (writes to
  /// `category_user`; original `categoryGuess` is preserved).
  final String? categoryUser;
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

  /// Ranked merchant-name guesses, carried through to enrichment.
  final List<MerchantCandidate> merchantCandidates;

  /// Extra OCR context (top-of-receipt lines), carried through to enrichment.
  final String? ocrHeaderText;

  /// Place chosen by the user in the pre-save picker.
  final String? pickedPlaceName;
  final String? pickedPlaceGooglePlaceId;
  final double? pickedPlaceLat;
  final double? pickedPlaceLng;
  final bool pickedPlaceLocked;

  ReceiptIngestDraft copyWith({
    double? amountMyr,
    bool? needsAmount,
    String? merchantRaw,
    String? categoryGuess,
    String? categoryUser,
    String? pickedPlaceName,
    String? pickedPlaceGooglePlaceId,
    double? pickedPlaceLat,
    double? pickedPlaceLng,
    bool? pickedPlaceLocked,
  }) {
    return ReceiptIngestDraft(
      localFilePath: localFilePath,
      mimeType: mimeType,
      amountMyr: amountMyr ?? this.amountMyr,
      needsAmount: needsAmount ?? this.needsAmount,
      merchantRaw: merchantRaw ?? this.merchantRaw,
      categoryGuess: categoryGuess ?? this.categoryGuess,
      categoryConfidence: categoryConfidence,
      categoryUser: categoryUser ?? this.categoryUser,
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
      merchantCandidates: merchantCandidates,
      ocrHeaderText: ocrHeaderText,
      pickedPlaceName: pickedPlaceName ?? this.pickedPlaceName,
      pickedPlaceGooglePlaceId:
          pickedPlaceGooglePlaceId ?? this.pickedPlaceGooglePlaceId,
      pickedPlaceLat: pickedPlaceLat ?? this.pickedPlaceLat,
      pickedPlaceLng: pickedPlaceLng ?? this.pickedPlaceLng,
      pickedPlaceLocked: pickedPlaceLocked ?? this.pickedPlaceLocked,
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
      categoryConfidence: categoryConfidence,
      categoryUser: categoryUser,
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
      merchantCandidates: merchantCandidates,
      ocrHeaderText: ocrHeaderText,
      pickedPlaceName: pickedPlaceName,
      pickedPlaceGooglePlaceId: pickedPlaceGooglePlaceId,
      pickedPlaceLat: pickedPlaceLat,
      pickedPlaceLng: pickedPlaceLng,
      pickedPlaceLocked: pickedPlaceLocked,
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
      categoryConfidence: categoryConfidence,
      categoryUser: categoryUser,
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
      merchantCandidates: merchantCandidates,
      ocrHeaderText: ocrHeaderText,
      pickedPlaceName: pickedPlaceName,
      pickedPlaceGooglePlaceId: pickedPlaceGooglePlaceId,
      pickedPlaceLat: pickedPlaceLat,
      pickedPlaceLng: pickedPlaceLng,
      pickedPlaceLocked: pickedPlaceLocked,
    );
  }
}
